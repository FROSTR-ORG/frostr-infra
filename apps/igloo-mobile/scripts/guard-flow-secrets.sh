#!/usr/bin/env bash
# Guard script to detect hardcoded secrets in Maestro flow files.
# Scans for package-like strings, passwords, and other secret patterns.
# Called automatically before commits, or manually for validation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FLOWS_DIR="$REPO_ROOT/apps/igloo-mobile/flows"

# Pattern samples for detection - these prefixes from .tmp/test-harness demo fixtures
# should never appear in committed flow files. Use runtime env var loading instead.
# Using first 8 hex chars of demo passwords as samples (not full values).
PATTERN_SAMPLE_A="4ad39a69"
PATTERN_SAMPLE_B="6c7b4ed4"

# Flag to track if any issues found
ISSUES_FOUND=0

echo "=== Flow Secret Guard ==="
echo "Scanning: $FLOWS_DIR"
echo ""

# Pattern 1: Check for known demo password prefixes
check_known_passwords() {
    local file="$1"
    local basename="$(basename "$file")"
    
    if grep -qF "$PATTERN_SAMPLE_A" "$file" 2>/dev/null; then
        echo "FAIL: Hardcoded demo password found in $basename"
        ISSUES_FOUND=1
    fi
    
    if grep -qF "$PATTERN_SAMPLE_B" "$file" 2>/dev/null; then
        echo "FAIL: Hardcoded demo password found in $basename"
        ISSUES_FOUND=1
    fi
}

# Pattern 2: Check for bfonboard1 package strings (690-char base32-like)
# bfonboard packages start with "bfonboard1" and are ~690 chars of base32
check_package_patterns() {
    local file="$1"
    local basename="$(basename "$file")"
    
    # Pattern: "bfonboard1" followed by ~650+ chars of lowercase alphanumeric
    # This regex matches the characteristic bfonboard package format
    if grep -E 'bfonboard1[qpzry9x8gf2wcvsu678dmr6c4n5j3e]+' "$file" >/dev/null 2>&1; then
        # Check if it's a full package (not just a comment reference)
        if grep -vE '^[[:space:]]*#' "$file" | grep -E 'bfonboard1[qpzry9x8gf2wcvsu678dmr6c4n5j3e]+' >/dev/null 2>&1; then
            echo "FAIL: Potential hardcoded bfonboard package found in $basename"
            ISSUES_FOUND=1
        fi
    fi
}

# Pattern 3: Check for inline text: with 32-char hex passwords (the format used)
# This catches patterns like text: "4ad39a696510276798af27e41aa71ab9"
check_hex_passwords() {
    local file="$1"
    local basename="$(basename "$file")"
    
    # Look for 32-char lowercase hex strings that could be passwords
    # Skip comment lines and check remaining content
    local non_comment_lines
    non_comment_lines=$(grep -vE '^[[:space:]]*#' "$file" 2>/dev/null || echo "")
    
    if echo "$non_comment_lines" | grep -qE 'text:[[:space:]]*"[a-f0-9]{32}"'; then
        echo "FAIL: Potential hardcoded 32-char hex password in $basename"
        ISSUES_FOUND=1
    fi
}

# Pattern 4: Check for setClipboard with hardcoded values (not env vars)
check_hardcoded_clipboard() {
    local file="$1"
    local basename="$(basename "$file")"
    
    # Look for setClipboard with literal strings (not $VAR or ${VAR})
    local hardcoded_count=0
    hardcoded_count=$(grep -cE 'setClipboard:.*[^$][a-zA-Z0-9]{10}' "$file" 2>/dev/null || true)
    hardcoded_count="${hardcoded_count:-0}"
    
    # Filter out env var references
    local envvar_count=0
    envvar_count=$(grep -cE 'setClipboard:.*\$\{' "$file" 2>/dev/null || true)
    envvar_count="${envvar_count:-0}"
    
    if [ "$hardcoded_count" -gt "$envvar_count" ] 2>/dev/null; then
        echo "FAIL: Potential hardcoded setClipboard value in $basename"
        ISSUES_FOUND=1
    fi
}

# Scan all YAML files in the flows directory
shopt -s nullglob
for flow_file in "$FLOWS_DIR"/*.yaml "$FLOWS_DIR"/*.yml; do
    if [ -f "$flow_file" ]; then
        check_known_passwords "$flow_file"
        check_package_patterns "$flow_file"
        check_hex_passwords "$flow_file"
        check_hardcoded_clipboard "$flow_file"
    fi
done
shopt -u nullglob

echo ""
if [ $ISSUES_FOUND -eq 0 ]; then
    echo "PASS: No hardcoded secrets detected in flow files"
    exit 0
else
    echo "FAIL: Hardcoded secrets detected. Remove secrets and use runtime credential loading."
    echo ""
    echo "Runtime credential loading approach:"
    echo "  - Pass ONBOARD_PACKAGE and ONBOARD_PASSWORD via Maestro -e flags"
    echo "  - Use setClipboard: \"\${ONBOARD_PASSWORD}\" + pasteText for credential entry"
    echo "  - Example: maestro test flows/signing-ios.yaml \\"
    echo "      -e ONBOARD_PASSWORD=\"\$(cat .tmp/test-harness/onboard-bob.password.txt)\""
    exit 1
fi