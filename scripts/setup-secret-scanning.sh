#!/bin/bash

# ==========================================
# Secret Scanning Setup & Audit Script
# Based on: Gitleaks + Trufflehog Tutorial
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
# We allow this to fail (exit code 1) if secrets are found, so we don't use 'set -e'
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

# Create directory if it doesn't exist
mkdir -p "$WORKFLOW_DIR"

if [ -f "$WORKFLOW_FILE" ]; then
    echo "Updating existing GitHub Action: $WORKFLOW_FILE"
else
    echo "Creating new GitHub Action: $WORKFLOW_FILE"
fi

# Write (or overwrite) the file content
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

# Check if pre-commit is installed
if ! command -v pre-commit &> /dev/null; then
    echo -e "${RED}Warning: 'pre-commit' framework is not installed.${NC}"
    echo "To use the hooks generated below, run: pip install pre-commit (or brew install pre-commit)"
    PRE_COMMIT_INSTALLED=0
else
    PRE_COMMIT_INSTALLED=1
fi

CONFIG_FILE=".pre-commit-config.yaml"

if [ -f "$CONFIG_FILE" ]; then
    echo "Updating existing pre-commit config: $CONFIG_FILE"
else
    echo "Creating new pre-commit config: $CONFIG_FILE"
fi

# Write (or overwrite) the file content
# Note: We are using the "Framework" approach (Option 2) as it is much more robust/maintainable than Option 1
cat <<EOF > "$CONFIG_FILE"
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks

  - repo: https://github.com/trufflesecurity/trufflehog
    rev: v3.63.0
    hooks:
      - id: trufflehog
        entry: trufflehog filesystem --fail .
        stages: [commit]
EOF

# Install the hooks if the tool is present
if [ $PRE_COMMIT_INSTALLED -eq 1 ]; then
    echo "Installing pre-commit hooks into .git/hooks/..."
    pre-commit install
    echo -e "${GREEN}Pre-commit hooks installed and configured.${NC}"
else
    echo -e "${YELLOW}Skipping 'pre-commit install' because the tool is missing.${NC}"
fi

# 5. SUMMARY
# ==========================================
echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}              SETUP COMPLETE              ${NC}"
echo -e "${GREEN}==========================================${NC}"
echo "1. Local Scan: Completed (Check logs above for findings)."
echo "2. CI/CD:      $WORKFLOW_FILE created/updated."
echo "3. Pre-commit: $CONFIG_FILE created/updated."

if [ $GITLEAKS_EXIT -ne 0 ] || [ $TRUFFLEHOG_EXIT -ne 0 ]; then
    echo -e "\n${RED}REMINDER: Secrets were detected in your history during the initial scan.${NC}"
    echo "Please rotate those credentials and consider using git-filter-repo to clean your history."
fi