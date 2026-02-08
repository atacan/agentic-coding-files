#!/bin/bash

# ==========================================
# Secret Scanning Setup & Audit Script (v2)
# ==========================================

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Secret Scanning Setup & Audit...${NC}"

# 1. PRE-FLIGHT CHECKS
# ==========================================
if [ ! -d ".git" ]; then
    echo -e "${RED}Error: This script must be run from the root of a Git repository.${NC}"
    exit 1
fi

TOOLS_MISSING=0
if ! command -v gitleaks &> /dev/null; then
    echo -e "${RED}Error: gitleaks is not installed.${NC} Please install it (brew install gitleaks)."
    TOOLS_MISSING=1
fi

if ! command -v trufflehog &> /dev/null; then
    echo -e "${RED}Error: trufflehog is not installed.${NC} Please install it (brew install trufflehog)."
    TOOLS_MISSING=1
fi

if [ $TOOLS_MISSING -eq 1 ]; then
    exit 1
fi

# 2. LOCAL AUDIT (Every commit, every branch)
# ==========================================
echo -e "\n${YELLOW}--- Phase 1: Running Local Full History Audit ---${NC}"

echo -e "${YELLOW}[1/2] Running Gitleaks (Full History)...${NC}"
gitleaks detect -v --log-opts="--all --full-history"
GITLEAKS_EXIT=$?

echo -e "${YELLOW}[2/2] Running Trufflehog (Verified & Unknown)...${NC}"
trufflehog git file://. --results=verified,unknown
TRUFFLEHOG_EXIT=$?

if [ $GITLEAKS_EXIT -ne 0 ] || [ $TRUFFLEHOG_EXIT -ne 0 ]; then
    echo -e "${RED}!!! WARNING: Potential secrets were found in your local history. !!!${NC}"
    echo "Check the logs above. Continuing with setup..."
    sleep 3
else
    echo -e "${GREEN}No secrets found in local history. Proceeding...${NC}"
fi

# 3. GITHUB ACTIONS SETUP
# ==========================================
echo -e "\n${YELLOW}--- Phase 2: Configuring GitHub Actions ---${NC}"

WORKFLOW_DIR=".github/workflows"
WORKFLOW_FILE="$WORKFLOW_DIR/secret-scan.yml"
mkdir -p "$WORKFLOW_DIR"

cat <<EOF > "$WORKFLOW_FILE"
name: Secret Scanning

on:
  push:
    branches: [main, master, develop]
  pull_request:

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

  trufflehog:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Trufflehog
        uses: trufflesecurity/trufflehog@main
        with:
          extra_args: --only-verified
EOF

echo -e "${GREEN}GitHub Action configured successfully.${NC}"

# 4. PRE-COMMIT SETUP
# ==========================================
echo -e "\n${YELLOW}--- Phase 3: Configuring Pre-commit Hooks ---${NC}"

if ! command -v pre-commit &> /dev/null; then
    echo -e "${RED}Warning: 'pre-commit' framework is not installed.${NC}"
    echo "Run: brew install pre-commit"
    exit 1
fi

# CLEANUP: Fix the corrupted cache from the previous failed run
echo "Cleaning pre-commit cache..."
pre-commit clean

CONFIG_FILE=".pre-commit-config.yaml"

echo "Creating robust pre-commit config (using system binaries)..."

# Changes made here:
# 1. Trufflehog now uses 'repo: local' and 'language: system'.
#    This prevents compiling Go code and uses the brew version you already have.
# 2. Removed deprecated 'stages: [commit]' to fix the warning.
cat <<EOF > "$CONFIG_FILE"
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.1
    hooks:
      - id: gitleaks

  - repo: local
    hooks:
      - id: trufflehog
        name: Trufflehog
        entry: trufflehog filesystem --fail .
        language: system
        types: [text]
        pass_filenames: false
EOF

echo "Installing pre-commit hooks..."
pre-commit install
echo -e "${GREEN}Pre-commit hooks installed and configured.${NC}"

# 5. SUMMARY
# ==========================================
echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}              SETUP COMPLETE              ${NC}"
echo -e "${GREEN}==========================================${NC}"
echo "1. CI/CD:      $WORKFLOW_FILE created."
echo "2. Pre-commit: $CONFIG_FILE updated to use system trufflehog."
echo -e "   ${YELLOW}Note:${NC} We cleared the pre-commit cache to fix the previous Go error."