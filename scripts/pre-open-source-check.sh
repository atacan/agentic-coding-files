#!/bin/bash

# pre-open-source-check.sh
# Checks a repository for common issues before open sourcing
# Usage: ./pre-open-source-check.sh [repository-path]
# Default: current directory

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

REPO_PATH="${1:-.}"
cd "$REPO_PATH"

echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE}Pre-Open Source Repository Check${NC}"
echo -e "${BLUE}Checking: $REPO_PATH${NC}"
echo -e "${BLUE}=======================================${NC}\n"

ISSUES_FOUND=0
WARNINGS=0

# Helper function to report issues
report_issue() {
    echo -e "${RED}❌ ISSUE: $1${NC}"
    echo -e "   $2"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
}

# Helper function to report warnings
report_warning() {
    echo -e "${YELLOW}⚠️  WARNING: $1${NC}"
    echo -e "   $2"
    WARNINGS=$((WARNINGS + 1))
}

# Helper function to report OK
report_ok() {
    echo -e "${GREEN}✓ $1${NC}"
}

# ============================================
# 1. CHECK FOR SECRETS AND CREDENTIALS FILES
# ============================================
echo -e "\n${BLUE}[1] Checking for secret/credential files...${NC}"

# Check for .env files
# Skip .env.example (committable template) and files already git-ignored
# (ignored files cannot be published, so they are warnings, not issues).
ENV_FILES=$(find . -name ".env*" -not -path "./.git/*" -not -path "./.build/*" -not -path "./node_modules/*" -not -path "./Pods/*" -not -path "./DerivedData/*" -not -path "./.swiftpm/*" 2>/dev/null || true)
TRACKED_ENV_FILES=""
IGNORED_ENV_FILES=""
while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ "$f" = "./.env.example" ]; then
        continue
    elif git check-ignore -q "$f" 2>/dev/null; then
        IGNORED_ENV_FILES="${IGNORED_ENV_FILES}${f}"$'\n'
    else
        TRACKED_ENV_FILES="${TRACKED_ENV_FILES}${f}"$'\n'
    fi
done <<< "$ENV_FILES"

if [ -n "$IGNORED_ENV_FILES" ]; then
    report_warning "Found git-ignored .env files in working tree" \
    "Not publishable via git, but verify they contain no real secrets: $(echo "$IGNORED_ENV_FILES" | head -5)"
fi

if [ -n "$TRACKED_ENV_FILES" ]; then
    report_issue "Found non-ignored .env files" "$(echo "$TRACKED_ENV_FILES" | head -5)"
else
    report_ok "No un-ignored .env files found"
fi

# Check for secret files
if find . -type f -name "*secret*" -not -path "./.git/*" -not -path "./.build/*" -not -path "./.github/*" -not -path "./node_modules/*" -not -path "./Pods/*" -not -path "./DerivedData/*" -not -path "./.swiftpm/*" 2>/dev/null | grep -q .; then
    report_issue "Found files with 'secret' in name" "$(find . -type f -name "*secret*" -not -path "./.git/*" -not -path "./.build/*" -not -path "./.github/*" -not -path "./node_modules/*" -not -path "./Pods/*" -not -path "./DerivedData/*" -not -path "./.swiftpm/*" 2>/dev/null | head -5)"
else
    report_ok "No files with 'secret' in name"
fi

# Check for credential files
if find . -type f -name "*credential*" -not -path "./.git/*" -not -path "./.build/*" -not -path "./node_modules/*" -not -path "./Pods/*" -not -path "./DerivedData/*" -not -path "./.swiftpm/*" 2>/dev/null | grep -q .; then
    report_issue "Found files with 'credential' in name" "$(find . -type f -name "*credential*" -not -path "./.git/*" -not -path "./.build/*" -not -path "./node_modules/*" -not -path "./Pods/*" -not -path "./DerivedData/*" -not -path "./.swiftpm/*" 2>/dev/null | head -5)"
else
    report_ok "No files with 'credential' in name"
fi

# Check for .pem files
if find . -type f -name "*.pem" -not -path "./.git/*" -not -path "./.build/*" -not -path "./node_modules/*" -not -path "./Pods/*" -not -path "./DerivedData/*" -not -path "./.swiftpm/*" 2>/dev/null | grep -q .; then
    report_issue "Found .pem certificate files" "$(find . -type f -name "*.pem" -not -path "./.git/*" -not -path "./.build/*" -not -path "./node_modules/*" -not -path "./Pods/*" -not -path "./DerivedData/*" -not -path "./.swiftpm/*" 2>/dev/null | head -5)"
else
    report_ok "No .pem files found"
fi

# Check for .key files
if find . -type f -name "*.key" -not -path "./.git/*" -not -path "./.build/*" -not -path "./node_modules/*" -not -path "./Pods/*" -not -path "./DerivedData/*" -not -path "./.swiftpm/*" 2>/dev/null | grep -q .; then
    report_issue "Found .key files" "$(find . -type f -name "*.key" -not -path "./.git/*" -not -path "./.build/*" -not -path "./node_modules/*" -not -path "./Pods/*" -not -path "./DerivedData/*" -not -path "./.swiftpm/*" 2>/dev/null | head -5)"
else
    report_ok "No .key files found"
fi

# Check for id_rsa and similar SSH keys
if find . -type f -name "id_rsa*" -not -path "./.git/*" -not -path "./.build/*" -not -path "./node_modules/*" -not -path "./Pods/*" -not -path "./DerivedData/*" -not -path "./.swiftpm/*" 2>/dev/null | grep -q .; then
    report_issue "Found SSH private keys" "$(find . -type f -name "id_rsa*" -not -path "./.git/*" -not -path "./.build/*" -not -path "./node_modules/*" -not -path "./Pods/*" -not -path "./DerivedData/*" -not -path "./.swiftpm/*" 2>/dev/null | head -5)"
else
    report_ok "No SSH private keys found"
fi

# ============================================
# 2. CHECK FOR SECRETS IN CODE
# ============================================
echo -e "\n${BLUE}[2] Checking for secrets in code...${NC}"

# Check for API keys in code
if grep -rn --include="*.swift" --include="*.py" --include="*.js" --include="*.ts" --include="*.java" --include="*.go" --include="*.rb" --include="*.php" --include="*.c" --include="*.cpp" --include="*.h" \
    -E "(api[_-]?key|apikey|api_secret|secret[_-]?key|access[_-]?token|auth[_-]?token|bearer[_-]?token|private[_-]?key)" . 2>/dev/null | grep -v "/.build/" | grep -v "/node_modules/" | grep -v "/Pods/" | grep -v "test" | grep -v "example" | grep -v "sample" | head -5 | grep -q .; then
    report_issue "Found potential API key/secret references in code" \
    "$(grep -rn --include="*.swift" --include="*.py" --include="*.js" --include="*.ts" --include="*.java" --include="*.go" --include="*.rb" --include="*.php" --include="*.c" --include="*.cpp" --include="*.h" \
    -E "(api[_-]?key|apikey|api_secret|secret[_-]?key|access[_-]?token|auth[_-]?token|bearer[_-]?token|private[_-]?key)" . 2>/dev/null | grep -v "/.build/" | grep -v "/node_modules/" | grep -v "/Pods/" | grep -v "test" | grep -v "example" | grep -v "sample" | head -3)"
else
    report_ok "No obvious API key references in code"
fi

# Check for password assignments
if grep -rn --include="*.swift" --include="*.py" --include="*.js" --include="*.ts" --include="*.java" --include="*.go" --include="*.rb" --include="*.php" \
    -E "(password|passwd|pwd)\s*=\s*[\"'][^\"']+[\"']" . 2>/dev/null | grep -v "/.build/" | grep -v "/node_modules/" | grep -v "/Pods/" | grep -v "test" | grep -v "example" | head -3 | grep -q .; then
    report_warning "Found potential hardcoded passwords" \
    "$(grep -rn --include="*.swift" --include="*.py" --include="*.js" --include="*.ts" --include="*.java" --include="*.go" --include="*.rb" --include="*.php" \
    -E "(password|passwd|pwd)\s*=\s*[\"'][^\"']+[\"']" . 2>/dev/null | grep -v "/.build/" | grep -v "/node_modules/" | grep -v "/Pods/" | grep -v "test" | grep -v "example" | head -3)"
else
    report_ok "No hardcoded passwords found"
fi

# ============================================
# 3. CHECK FOR HARDCODED PATHS
# ============================================
echo -e "\n${BLUE}[3] Checking for hardcoded paths...${NC}"

# Check for /Users/ paths (macOS)
if grep -rn --include="*.swift" --include="*.py" --include="*.js" --include="*.ts" --include="*.java" --include="*.go" --include="*.rb" --include="*.php" --include="*.json" --include="*.yaml" --include="*.yml" \
    "/Users/[^/]" . 2>/dev/null | grep -v ".build" | grep -v "node_modules" | grep -v "Pods" | head -5 | grep -q .; then
    report_warning "Found hardcoded /Users/ paths" \
    "$(grep -rn --include="*.swift" --include="*.py" --include="*.js" --include="*.ts" --include="*.java" --include="*.go" --include="*.rb" --include="*.php" --include="*.json" --include="*.yaml" --include="*.yml" \
    "/Users/[^/]" . 2>/dev/null | grep -v ".build" | grep -v "node_modules" | grep -v "Pods" | head -3)"
else
    report_ok "No hardcoded /Users/ paths found"
fi

# Check for /home/ paths (Linux)
if grep -rn --include="*.swift" --include="*.py" --include="*.js" --include="*.ts" --include="*.java" --include="*.go" --include="*.rb" --include="*.php" --include="*.json" --include="*.yaml" --include="*.yml" \
    "/home/[^/]" . 2>/dev/null | grep -v ".build" | grep -v "node_modules" | grep -v "Pods" | head -5 | grep -q .; then
    report_warning "Found hardcoded /home/ paths" \
    "$(grep -rn --include="*.swift" --include="*.py" --include="*.js" --include="*.ts" --include="*.java" --include="*.go" --include="*.rb" --include="*.php" --include="*.json" --include="*.yaml" --include="*.yml" \
    "/home/[^/]" . 2>/dev/null | grep -v ".build" | grep -v "node_modules" | grep -v "Pods" | head -3)"
else
    report_ok "No hardcoded /home/ paths found"
fi

# ============================================
# 4. CHECK GIT HISTORY FOR DELETED SECRETS
# ============================================
echo -e "\n${BLUE}[4] Checking git history for deleted secrets...${NC}"

if [ -d ".git" ]; then
    # Check if sensitive files were ever committed
    HISTORY_ISSUES=$(git log --all --full-history -- "*secret*" "*credential*" "*api*key*" "*password*" "*.pem" "*.key" "id_rsa*" ".env*" 2>/dev/null | head -10)
    if [ -n "$HISTORY_ISSUES" ]; then
        report_warning "Found sensitive files in git history (even if deleted now)" \
        "Run: git log --all --full-history -- '*secret*' '*credential*' '*.pem' '*.key' '.env*'"
    else
        report_ok "No sensitive files found in git history"
    fi
else
    report_warning "Not a git repository" "Cannot check git history"
fi

# ============================================
# 5. CHECK LICENSE
# ============================================
echo -e "\n${BLUE}[5] Checking license...${NC}"

if [ -f "LICENSE" ] || [ -f "LICENSE.md" ] || [ -f "LICENSE.txt" ]; then
    LICENSE_FILE=$(ls LICENSE* 2>/dev/null | head -1)
    
    # Check for OSI-approved licenses
    if grep -qiE "(mit license|apache license|gnu general public license|gpl|bsd license|mozilla public license)" "$LICENSE_FILE" 2>/dev/null; then
        LICENSE_TYPE=$(grep -iE "(MIT|Apache|GPL|BSD|Mozilla)" "$LICENSE_FILE" | head -1)
        report_ok "Found OSI-approved license: $LICENSE_TYPE"
    elif grep -qiE "copyright" "$LICENSE_FILE" 2>/dev/null; then
        report_warning "Found custom copyright license" \
        "This may not be truly 'open source'. Consider using MIT, Apache 2.0, or GPL for OSI compliance."
    else
        report_warning "Found LICENSE file but type unclear" "Review license content manually"
    fi
else
    report_issue "No LICENSE file found" "Add a license file before open sourcing (MIT is recommended)"
fi

# ============================================
# 6. CHECK README
# ============================================
echo -e "\n${BLUE}[6] Checking documentation...${NC}"

if [ -f "README.md" ] || [ -f "README" ] || [ -f "README.txt" ]; then
    report_ok "README file found"
else
    report_warning "No README file found" "Consider adding a README.md for better discoverability"
fi

# ============================================
# 7. CHECK PACKAGE MANAGER FILES FOR LOCAL PATHS
# ============================================
echo -e "\n${BLUE}[7] Checking dependency configuration files...${NC}"

# Swift Package.swift
if [ -f "Package.swift" ]; then
    if grep -n "package(path:" Package.swift 2>/dev/null | grep -q .; then
        report_warning "Package.swift contains local path dependencies" \
        "$(grep -n "package(path:" Package.swift | head -3)"
    else
        report_ok "Package.swift uses only remote dependencies"
    fi
fi

# Node.js package.json
if [ -f "package.json" ]; then
    if grep -E "file:|link:" package.json 2>/dev/null | grep -q .; then
        report_warning "package.json contains local file: or link: dependencies" \
        "$(grep -n "file:\|link:" package.json | head -3)"
    else
        report_ok "package.json uses only remote dependencies"
    fi
fi

# Python requirements.txt
if [ -f "requirements.txt" ]; then
    if grep -E "^\s*-\s*e\s+" requirements.txt 2>/dev/null | grep -q .; then
        report_warning "requirements.txt contains editable installs (-e) pointing to local paths" \
        "$(grep -n "^\s*-\s*e\s+" requirements.txt | head -3)"
    else
        report_ok "requirements.txt looks clean"
    fi
fi

# Go go.mod
if [ -f "go.mod" ]; then
    if grep "replace.*=>" go.mod 2>/dev/null | grep -v "=>" | grep -q "."; then
        report_warning "go.mod contains replace directives (check if they point to local paths)" \
        "$(grep -n "replace" go.mod | head -3)"
    else
        report_ok "go.mod looks clean"
    fi
fi

# ============================================
# 8. CHECK FOR .gitignore
# ============================================
echo -e "\n${BLUE}[8] Checking .gitignore...${NC}"

if [ -f ".gitignore" ]; then
    # Check if .gitignore covers common sensitive files
    if grep -qiE "\.env|secret|credential|\.pem|\.key|id_rsa" .gitignore 2>/dev/null; then
        report_ok ".gitignore covers sensitive files"
    else
        report_warning ".gitignore may not cover all sensitive files" \
        "Consider adding: .env, *.pem, *.key, id_rsa*, *secret*, *credential*"
    fi
else
    report_warning "No .gitignore file found" "Sensitive files might be accidentally committed"
fi

# ============================================
# 9. CHECK FOR LARGE BINARY FILES
# ============================================
echo -e "\n${BLUE}[9] Checking for large binary files...${NC}"

if [ -d ".git" ]; then
    LARGE_FILES=$(find . -type f -size +10M -not -path "./.git/*" -not -path "./.build/*" -not -path "./node_modules/*" -not -path "./Pods/*" -not -path "./DerivedData/*" 2>/dev/null | head -5)
    if [ -n "$LARGE_FILES" ]; then
        report_warning "Found large files (>10MB)" "$LARGE_FILES"
    else
        report_ok "No large files found"
    fi
fi

# ============================================
# 10. CHECK FOR PERSONAL INFO IN CODE
# ============================================
echo -e "\n${BLUE}[10] Checking for personal information in code...${NC}"

# Check for email addresses
if grep -rn --include="*.swift" --include="*.py" --include="*.js" --include="*.ts" --include="*.java" --include="*.go" --include="*.rb" --include="*.php" \
    -E "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" . 2>/dev/null | grep -v "/.build/" | grep -v "example.com" | grep -v "test.com" | grep -v "noreply" | grep -v "@users.noreply.github.com" | grep -v "package.json" | grep -v "Podfile" | head -3 | grep -q .; then
    report_warning "Found email addresses in code" \
    "$(grep -rn --include="*.swift" --include="*.py" --include="*.js" --include="*.ts" --include="*.java" --include="*.go" --include="*.rb" --include="*.php" \
    -E "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" . 2>/dev/null | grep -v "/.build/" | grep -v "example.com" | grep -v "test.com" | grep -v "noreply" | grep -v "@users.noreply.github.com" | head -3)"
else
    report_ok "No personal email addresses found in code"
fi

# ============================================
# SUMMARY
# ============================================
echo -e "\n${BLUE}=======================================${NC}"
echo -e "${BLUE}SUMMARY${NC}"
echo -e "${BLUE}=======================================${NC}"

if [ $ISSUES_FOUND -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ Repository looks ready for open sourcing!${NC}"
elif [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No critical issues found, but $WARNINGS warning(s) need attention${NC}"
else
    echo -e "${RED}❌ Found $ISSUES_FOUND critical issue(s) and $WARNINGS warning(s)${NC}"
    echo -e "${RED}   Fix these before making the repository public${NC}"
fi

echo -e "\n${BLUE}Note: This script provides basic checks. Always do a final manual review!${NC}"

# Exit with appropriate code
if [ $ISSUES_FOUND -gt 0 ]; then
    exit 1
fi

exit 0