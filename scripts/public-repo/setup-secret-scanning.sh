#!/bin/bash

# ==========================================
# Secret Scanning Setup & Audit Script
# Based on: Gitleaks + Trufflehog Tutorial
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

if ! command -v gitleaks &> /dev/null; then
    echo -e "${RED}✗ gitleaks is not installed.${NC}"
    echo "  Install: brew install gitleaks"
    TOOLS_MISSING=1
else
    GITLEAKS_VERSION=$(gitleaks version 2>&1)
    echo -e "${GREEN}✓${NC} gitleaks found (${GITLEAKS_VERSION})"
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
# 2. GITLEAKS CONFIG (with exclusions)
# ==========================================
echo -e "\n${BLUE}--- Setting up Gitleaks config ---${NC}"

GITLEAKS_CONFIG=".gitleaks.toml"

if [ -f "$GITLEAKS_CONFIG" ]; then
    echo "Updating existing: $GITLEAKS_CONFIG"
else
    echo "Creating new: $GITLEAKS_CONFIG"
fi

cat > "$GITLEAKS_CONFIG" <<'TOML'
# Gitleaks configuration
# https://github.com/gitleaks/gitleaks#configuration

title = "Gitleaks config"

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

echo -e "${GREEN}✓${NC} Gitleaks config written: $GITLEAKS_CONFIG"

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

echo -e "${YELLOW}[1/2] Running Gitleaks (full history, all branches)...${NC}"
gitleaks detect -v \
    --config="$GITLEAKS_CONFIG" \
    --log-opts="--all --full-history"
GITLEAKS_EXIT=$?
if [ $GITLEAKS_EXIT -ne 0 ]; then
    echo -e "${RED}  ⚠ Gitleaks found potential secrets.${NC}"
    AUDIT_FAILED=1
else
    echo -e "${GREEN}  ✓ Gitleaks: clean.${NC}"
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
  gitleaks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Gitleaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: \${{ secrets.GITHUB_TOKEN }}
          GITLEAKS_CONFIG: .gitleaks.toml

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

TRUFFLEHOG_PATH=$(command -v trufflehog)

cat > "$CONFIG_FILE" <<YAML
repos:
  # -------------------------------------------------------
  # Gitleaks — pattern-based secret detection
  # Uses the official pre-commit hook from the gitleaks repo.
  # The .gitleaks.toml config handles path exclusions.
  # -------------------------------------------------------
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.2
    hooks:
      - id: gitleaks
        args: ['--config=.gitleaks.toml']

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
    "gitleaks-report.json"
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
echo "    • $GITLEAKS_CONFIG                   (Gitleaks exclusions)"
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
echo "    • Gitleaks:   edit $GITLEAKS_CONFIG (paths allowlist)"
echo "    • Trufflehog: edit $TRUFFLEHOG_EXCLUDE (one path per line)"
echo ""

if [ $AUDIT_FAILED -eq 1 ]; then
    echo -e "${RED}  ⚠  IMPORTANT: Secrets were found in your history.${NC}"
    echo "     1. Verify they are real secrets (not test fixtures)"
    echo "     2. Rotate any real exposed credentials immediately"
    echo "     3. If they are false positives, add to:"
    echo "        • .gitleaksignore  (fingerprint-based, for gitleaks)"
    echo "        • $TRUFFLEHOG_EXCLUDE (path-based, for trufflehog)"
    echo ""
fi

echo "  Next steps:"
echo "    • Review and commit the generated files:"
echo "      git add .gitleaks.toml .trufflehog-exclude-paths.txt \\"
echo "             .pre-commit-config.yaml .github/workflows/secret-scan.yml \\"
echo "             .gitignore"
echo "    • Run 'pre-commit run --all-files' to test the hooks"
echo ""