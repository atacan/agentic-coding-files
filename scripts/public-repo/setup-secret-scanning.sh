#!/bin/bash

# ==========================================
# Secret Scanning Setup & Audit Script
# Based on: Betterleaks + Trufflehog Tutorial
# ==========================================

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Secret Scanning Setup & Audit Script  ${NC}"
echo -e "${GREEN}========================================${NC}"

# ==========================================
# 1. PRE-FLIGHT CHECKS
# ==========================================
echo -e "\n${BLUE}--- Pre-flight Checks ---${NC}"

if [ ! -d ".git" ]; then
    echo -e "${RED}Error: This script must be run from the root of a Git repository.${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Git repository detected."

TOOLS_MISSING=0

if ! command -v betterleaks &> /dev/null; then
    echo -e "${RED}✗ betterleaks is not installed.${NC}"
    echo "  Install: brew install betterleaks"
    TOOLS_MISSING=1
else
    BETTERLEAKS_VERSION=$(betterleaks version 2>&1)
    echo -e "${GREEN}✓${NC} betterleaks found (${BETTERLEAKS_VERSION})"
fi

if ! command -v trufflehog &> /dev/null; then
    echo -e "${RED}✗ trufflehog is not installed.${NC}"
    echo "  Install: brew install trufflehog"
    TOOLS_MISSING=1
else
    TRUFFLEHOG_VERSION=$(trufflehog --version 2>&1 | head -1)
    echo -e "${GREEN}✓${NC} trufflehog found (${TRUFFLEHOG_VERSION})"
fi

if [ $TOOLS_MISSING -eq 1 ]; then
    echo -e "${RED}Please install missing tools and re-run.${NC}"
    exit 1
fi

# ==========================================
# 2. BETTERLEAKS CONFIG (with exclusions)
# ==========================================
echo -e "\n${BLUE}--- Setting up Betterleaks config ---${NC}"

BETTERLEAKS_CONFIG=".betterleaks.toml"

if [ -f "$BETTERLEAKS_CONFIG" ]; then
    echo "Updating existing: $BETTERLEAKS_CONFIG"
else
    echo "Creating new: $BETTERLEAKS_CONFIG"
fi

cat > "$BETTERLEAKS_CONFIG" <<'TOML'
# Betterleaks configuration
# https://github.com/betterleaks/betterleaks/blob/main/docs/config.md

title = "Betterleaks config"

# Extend the default rules (don't replace them)
[extend]
useDefault = true

# Paths to exclude from scanning
# These are dependency/build directories that contain
# test fixtures with fake secrets, not real leaks.
[allowlist]
  description = "Global allowlist"
  paths = [
    # Swift Package Manager
    '''\.build/''',
    '''\.swiftpm/''',

    # CocoaPods
    '''Pods/''',

    # Dependency checkouts and caches
    '''Carthage/Checkouts/''',
    '''vendor/''',
    '''node_modules/''',

    # Build artifacts
    '''DerivedData/''',
    '''build/''',
    '''dist/''',

    # Package lock files (contain hashes, not secrets)
    '''Package\.resolved$''',
    '''Podfile\.lock$''',
    '''package-lock\.json$''',
    '''yarn\.lock$''',
    '''pnpm-lock\.yaml$''',
    '''Gemfile\.lock$''',

    # Test fixtures that intentionally contain fake secrets
    '''(test|tests|spec|specs|__tests__)/.*fixtures?/''',
    '''(test|tests|spec|specs|__tests__)/.*mocks?/''',
    '''(test|tests|spec|specs|__tests__)/.*stubs?/''',
  ]
TOML

echo -e "${GREEN}✓${NC} Betterleaks config written: $BETTERLEAKS_CONFIG"

# ==========================================
# 3. TRUFFLEHOG EXCLUDE FILE
# ==========================================
echo -e "\n${BLUE}--- Setting up Trufflehog exclusions ---${NC}"

TRUFFLEHOG_EXCLUDE=".trufflehog-exclude-paths.txt"

if [ -f "$TRUFFLEHOG_EXCLUDE" ]; then
    echo "Updating existing: $TRUFFLEHOG_EXCLUDE"
else
    echo "Creating new: $TRUFFLEHOG_EXCLUDE"
fi

cat > "$TRUFFLEHOG_EXCLUDE" <<'PATHS'
# Trufflehog path exclusions
# One path/pattern per line (glob syntax)

# Swift Package Manager
.build/
.swiftpm/

# CocoaPods
Pods/

# Carthage
Carthage/Checkouts/

# Other dependency/vendor dirs
vendor/
node_modules/

# Build artifacts
DerivedData/
build/
dist/

# Lock files
Package.resolved
Podfile.lock
package-lock.json
yarn.lock
pnpm-lock.yaml
Gemfile.lock
PATHS

echo -e "${GREEN}✓${NC} Trufflehog exclusions written: $TRUFFLEHOG_EXCLUDE"

# ==========================================
# 4. LOCAL AUDIT (Every commit, every branch)
# ==========================================
echo -e "\n${YELLOW}--- Phase 1: Running Local Full History Audit ---${NC}"
echo "This scans every commit across all branches for leaked secrets."
echo "Excluded: .build/, Pods/, vendor/, node_modules/, etc."
echo ""

AUDIT_FAILED=0

echo -e "${YELLOW}[1/2] Running Betterleaks (full history, all branches)...${NC}"
betterleaks git . --verbose --redact \
    --config="$BETTERLEAKS_CONFIG" \
    --log-opts="--all --full-history"
BETTERLEAKS_EXIT=$?
if [ $BETTERLEAKS_EXIT -ne 0 ]; then
    echo -e "${RED}  ⚠ Betterleaks found potential secrets.${NC}"
    AUDIT_FAILED=1
else
    echo -e "${GREEN}  ✓ Betterleaks: clean.${NC}"
fi

echo ""
echo -e "${YELLOW}[2/2] Running Trufflehog (verified & unknown secrets)...${NC}"
trufflehog git file://. \
    --results=verified,unknown \
    --exclude-paths="$TRUFFLEHOG_EXCLUDE" \
    --fail
TRUFFLEHOG_EXIT=$?
if [ $TRUFFLEHOG_EXIT -ne 0 ]; then
    echo -e "${RED}  ⚠ Trufflehog found potential secrets.${NC}"
    AUDIT_FAILED=1
else
    echo -e "${GREEN}  ✓ Trufflehog: clean.${NC}"
fi

if [ $AUDIT_FAILED -eq 1 ]; then
    echo -e "\n${RED}!!! Potential secrets detected in repository history !!!${NC}"
    echo "Review the output above. Continuing with setup to prevent future leaks..."
    sleep 2
fi

# ==========================================
# 5. GITHUB ACTIONS SETUP
# ==========================================
echo -e "\n${YELLOW}--- Phase 2: Configuring GitHub Actions ---${NC}"

WORKFLOW_DIR=".github/workflows"
WORKFLOW_FILE="$WORKFLOW_DIR/secret-scan.yml"

mkdir -p "$WORKFLOW_DIR"

if [ -f "$WORKFLOW_FILE" ]; then
    echo "Updating existing: $WORKFLOW_FILE"
else
    echo "Creating new: $WORKFLOW_FILE"
fi

# Detect default branch name
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$DEFAULT_BRANCH" ]; then
    DEFAULT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
fi
if [ -z "$DEFAULT_BRANCH" ]; then
    DEFAULT_BRANCH="main"
fi
echo "  Default branch detected: $DEFAULT_BRANCH"

cat > "$WORKFLOW_FILE" <<YAML
name: Secret Scanning

on:
  push:
    branches: [${DEFAULT_BRANCH}]
  pull_request:
    branches: [${DEFAULT_BRANCH}]

jobs:
  betterleaks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Betterleaks
        uses: docker://ghcr.io/betterleaks/betterleaks:v1.7.2
        with:
          args: git . --config=.betterleaks.toml --redact --verbose --log-opts="--all --full-history"

  trufflehog:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Trufflehog
        uses: trufflesecurity/trufflehog@main
        with:
          extra_args: --only-verified --exclude-paths=.trufflehog-exclude-paths.txt
YAML

echo -e "${GREEN}✓${NC} GitHub Action configured: $WORKFLOW_FILE"

# ==========================================
# 6. PRE-COMMIT SETUP
# ==========================================
echo -e "\n${YELLOW}--- Phase 3: Configuring Pre-commit Hooks ---${NC}"

if ! command -v pre-commit &> /dev/null; then
    echo -e "${RED}✗ 'pre-commit' framework is not installed.${NC}"
    echo "  Install: brew install pre-commit  (or)  pip install pre-commit"
    PRE_COMMIT_INSTALLED=0
else
    PRE_COMMIT_VERSION=$(pre-commit --version 2>&1)
    echo -e "${GREEN}✓${NC} pre-commit found (${PRE_COMMIT_VERSION})"
    PRE_COMMIT_INSTALLED=1
fi

CONFIG_FILE=".pre-commit-config.yaml"

if [ -f "$CONFIG_FILE" ]; then
    echo "Updating existing: $CONFIG_FILE"
else
    echo "Creating new: $CONFIG_FILE"
fi

BETTERLEAKS_PATH=$(command -v betterleaks)
TRUFFLEHOG_PATH=$(command -v trufflehog)

cat > "$CONFIG_FILE" <<YAML
repos:
  # -------------------------------------------------------
  # Betterleaks — configurable secret detection
  # Uses the installed Betterleaks binary and project config.
  # -------------------------------------------------------
  - repo: local
    hooks:
      - id: betterleaks
        name: betterleaks (local)
        language: system
        entry: ${BETTERLEAKS_PATH} git --pre-commit --redact --staged --verbose --config=.betterleaks.toml
        stages: [pre-commit]
        pass_filenames: false
        always_run: true

  # -------------------------------------------------------
  # Trufflehog — verification-based secret detection
  # Uses a LOCAL hook calling the already-installed binary.
  # This avoids the known issue where the repo-based hook
  # tries to 'go install' from source and fails.
  # The .trufflehog-exclude-paths.txt handles exclusions.
  # -------------------------------------------------------
  - repo: local
    hooks:
      - id: trufflehog
        name: trufflehog (local)
        language: system
        entry: bash -c '${TRUFFLEHOG_PATH} git file://. --since-commit HEAD --results=verified,unknown --exclude-paths=.trufflehog-exclude-paths.txt --fail'
        stages: [pre-commit]
        pass_filenames: false
        always_run: true
YAML

echo -e "${GREEN}✓${NC} Pre-commit config written: $CONFIG_FILE"

if [ $PRE_COMMIT_INSTALLED -eq 1 ]; then
    echo "Installing pre-commit hooks into .git/hooks/..."
    pre-commit install
    echo -e "${GREEN}✓${NC} Pre-commit hooks installed."

    echo "Validating config..."
    pre-commit validate-config "$CONFIG_FILE" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Config is valid."
    fi
else
    echo -e "${YELLOW}Skipping hook installation (pre-commit not installed).${NC}"
fi

# ==========================================
# 7. GITIGNORE ADDITIONS
# ==========================================
echo -e "\n${YELLOW}--- Phase 4: Ensuring .gitignore entries ---${NC}"

GITIGNORE_FILE=".gitignore"

if [ ! -f "$GITIGNORE_FILE" ]; then
    touch "$GITIGNORE_FILE"
fi

GITIGNORE_ENTRIES=(
    "# Secret scanning reports"
    "betterleaks-report.json"
    "trufflehog-report.json"
)

ENTRIES_ADDED=0
for entry in "${GITIGNORE_ENTRIES[@]}"; do
    if ! grep -qxF "$entry" "$GITIGNORE_FILE" 2>/dev/null; then
        echo "$entry" >> "$GITIGNORE_FILE"
        ENTRIES_ADDED=1
    fi
done

if [ $ENTRIES_ADDED -eq 1 ]; then
    echo -e "${GREEN}✓${NC} Added report files to .gitignore"
else
    echo -e "${GREEN}✓${NC} .gitignore already up to date."
fi

# ==========================================
# 8. SUMMARY
# ==========================================
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}           SETUP COMPLETE               ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  Files created/updated:"
echo "    • $BETTERLEAKS_CONFIG                (Betterleaks exclusions)"
echo "    • $TRUFFLEHOG_EXCLUDE  (Trufflehog exclusions)"
echo "    • $WORKFLOW_FILE   (GitHub Actions)"
echo "    • $CONFIG_FILE                  (Pre-commit hooks)"
echo "    • $GITIGNORE_FILE                       (.gitignore)"
echo ""
echo "  Excluded from scanning:"
echo "    • .build/  .swiftpm/  Pods/  Carthage/Checkouts/"
echo "    • vendor/  node_modules/  DerivedData/  build/  dist/"
echo "    • Lock files (Package.resolved, etc.)"
echo ""
echo "  To add more exclusions:"
echo "    • Betterleaks: edit $BETTERLEAKS_CONFIG (paths allowlist)"
echo "    • Trufflehog: edit $TRUFFLEHOG_EXCLUDE (one path per line)"
echo ""

if [ $AUDIT_FAILED -eq 1 ]; then
    echo -e "${RED}  ⚠  IMPORTANT: Secrets were found in your history.${NC}"
    echo "     1. Verify they are real secrets (not test fixtures)"
    echo "     2. Rotate any real exposed credentials immediately"
    echo "     3. If they are false positives, add to:"
    echo "        • .betterleaksignore (fingerprint-based, for Betterleaks)"
    echo "        • $TRUFFLEHOG_EXCLUDE (path-based, for trufflehog)"
    echo ""
fi

echo "  Next steps:"
echo "    • Review and commit the generated files:"
echo "      git add .betterleaks.toml .trufflehog-exclude-paths.txt \\"
echo "             .pre-commit-config.yaml .github/workflows/secret-scan.yml \\"
echo "             .gitignore"
echo "    • Run 'pre-commit run --all-files' to test the hooks"
echo ""
