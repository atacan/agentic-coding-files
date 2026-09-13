#!/usr/bin/env bash
# check-secrets-before-public.sh
# Scans a git repository's entire history for accidentally committed secrets.
# Usage: ./check-secrets-before-public.sh [path-to-repo]
# Exit code 0 = clean, 1 = findings that need review.

set -euo pipefail

REPO_DIR="${1:-.}"
cd "$REPO_DIR"

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "ERROR: Not a git repository: $REPO_DIR"
  exit 1
fi

FOUND=0
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

section() { echo -e "\n${YELLOW}==> $1${NC}"; }

# ---------------------------------------------------------------------------
# 1. Check for sensitive filenames ever committed
# ---------------------------------------------------------------------------
section "Checking for sensitive files in git history..."

SENSITIVE_PATTERNS='\.env$|\.env\.|\.env\.local|\.env\.prod|\.env\.dev|\.env\.staging|credentials\.json|service.account\.json|\.key$|\.pem$|\.p12$|\.pfx$|\.keystore$|id_rsa|id_ed25519|\.secret|htpasswd|\.npmrc$|\.pypirc$|\.netrc$|\.pgpass$'

SENSITIVE_FILES=$(git log --all --diff-filter=A --name-only --pretty=format: | sort -u | grep -iE "$SENSITIVE_PATTERNS" || true)

if [[ -n "$SENSITIVE_FILES" ]]; then
  echo -e "${RED}FOUND sensitive filenames in history:${NC}"
  echo "$SENSITIVE_FILES"
  FOUND=1
else
  echo -e "${GREEN}No sensitive filenames found.${NC}"
fi

# ---------------------------------------------------------------------------
# 2. Scan committed content and full git history with Betterleaks
# ---------------------------------------------------------------------------
section "Scanning git history with Betterleaks..."

if ! command -v betterleaks &>/dev/null; then
  echo -e "${RED}ERROR: betterleaks is not installed.${NC}"
  echo "Install it with: brew install betterleaks"
  FOUND=1
elif [[ -f .betterleaks.toml ]]; then
  if betterleaks git . --config=.betterleaks.toml --redact --verbose --log-opts="--all --full-history"; then
    echo -e "${GREEN}Betterleaks found no secrets in git history.${NC}"
  else
    echo -e "${RED}Betterleaks found potential secrets in git history.${NC}"
    FOUND=1
  fi
else
  if betterleaks git . --redact --verbose --log-opts="--all --full-history"; then
    echo -e "${GREEN}Betterleaks found no secrets in git history.${NC}"
  else
    echo -e "${RED}Betterleaks found potential secrets in git history.${NC}"
    FOUND=1
  fi
fi

# ---------------------------------------------------------------------------
# 3. Check for .env files in tracked or untracked files (current tree)
# ---------------------------------------------------------------------------
section "Checking current working tree..."

ENV_FILES=$(find . -maxdepth 5 -name '.env*' -not -path './.build/*' -not -path './.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null || true)

if [[ -n "$ENV_FILES" ]]; then
  echo -e "${RED}Found .env files in working tree:${NC}"
  echo "$ENV_FILES"
  # Check if any are tracked
  for f in $ENV_FILES; do
    if git ls-files --error-unmatch "$f" &>/dev/null; then
      echo -e "${RED}  WARNING: $f is tracked by git!${NC}"
      FOUND=1
    else
      echo -e "${YELLOW}  OK: $f is not tracked (in .gitignore or untracked).${NC}"
    fi
  done
else
  echo -e "${GREEN}No .env files in working tree.${NC}"
fi

# ---------------------------------------------------------------------------
# 4. Check .gitignore covers common sensitive patterns
# ---------------------------------------------------------------------------
section "Checking .gitignore coverage..."

GITIGNORE_FILE=".gitignore"
SHOULD_IGNORE=('.env' '.env.*' '*.key' '*.pem' '*.p12' 'credentials.json')

if [[ -f "$GITIGNORE_FILE" ]]; then
  for pat in "${SHOULD_IGNORE[@]}"; do
    if grep -qF "$pat" "$GITIGNORE_FILE" 2>/dev/null; then
      echo -e "${GREEN}  .gitignore covers: $pat${NC}"
    else
      echo -e "${YELLOW}  MISSING from .gitignore: $pat${NC}"
    fi
  done
else
  echo -e "${YELLOW}  No .gitignore file found.${NC}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
if [[ $FOUND -eq 0 ]]; then
  echo -e "${GREEN}All clear -- no secrets detected. Safe to make public.${NC}"
  exit 0
else
  echo -e "${RED}Review the findings above before making this repo public.${NC}"
  echo "If a secret was committed, consider:"
  echo "  1. Rotating the secret immediately"
  echo "  2. Using 'git filter-repo' or BFG to rewrite history"
  echo "  3. Force-pushing the cleaned history"
  exit 1
fi
