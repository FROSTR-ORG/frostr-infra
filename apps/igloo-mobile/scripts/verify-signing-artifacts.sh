#!/usr/bin/env bash
# Verifier helper for VAL-SIGN signature and ECDH artifact correlation.
# Reads captured values from the signing flow app UI and correlates them
# with demo harness relay logs. This does NOT handle secrets - it only
# correlates public values (request IDs, digests, signatures, pubkeys).
#
# Usage:
#   # After running signing-ios.yaml or signing-android.yaml, capture values:
#   # - Copy request id, digest, signature from Test Sign Result rows
#   # - Copy request id, target pubkey, shared secret from Test ECDH Result rows
#
#   # Then run verification:
#   ./scripts/verify-signing-artifacts.sh sign <request_id> <digest> <signature> <group_pubkey>
#   ./scripts/verify-signing-artifacts.sh ecdh <request_id> <target_pubkey> <shared_secret>
#
#   # Or use clipboard values:
#   ./scripts/verify-signing-artifacts.sh sign-clipboard
#   ./scripts/verify-signing-artifacts.sh ecdh-clipboard
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HARNESS_DIR="$REPO_ROOT/.tmp/test-harness"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate hex string format
validate_hex() {
    local hex="$1"
    local min_len="${2:-32}"
    local name="${3:-value}"
    
    if [[ ! "$hex" =~ ^[a-f0-9]+$ ]]; then
        log_error "$name is not valid lowercase hex: $hex"
        return 1
    fi
    
    if [ ${#hex} -lt $min_len ]; then
        log_error "$name is too short (${#hex} < $min_len chars): $hex"
        return 1
    fi
    
    return 0
}

# Verify signature artifact correlation
verify_sign() {
    local request_id="$1"
    local digest="$2"
    local signature="$3"
    local group_pubkey="${4:-}"
    
    log_info "=== Signature Verification ==="
    echo ""
    
    # Validate request_id (should be 64-char hex - hash)
    if validate_hex "$request_id" 32 "request_id"; then
        echo "  request_id: ${request_id:0:32}... (${#request_id} chars)"
    fi
    echo ""
    
    # Validate digest (should be 64-char hex - hash)
    if validate_hex "$digest" 64 "digest"; then
        echo "  digest: ${digest:0:32}... (${#digest} chars)"
    fi
    echo ""
    
    # Validate signature (BIP340 signature is 64-char compact format)
    if validate_hex "$signature" 64 "signature"; then
        echo "  signature: ${signature:0:32}... (${#signature} chars)"
    fi
    echo ""
    
    # If group_pubkey provided, validate it
    if [ -n "$group_pubkey" ]; then
        if validate_hex "$group_pubkey" 64 "group_pubkey"; then
            echo "  group_pubkey: ${group_pubkey:0:32}... (${#group_pubkey} chars)"
        fi
    else
        # Try to read from demo harness
        if [ -d "$HARNESS_DIR/demo-2of3" ]; then
            local group_pk_file="$HARNESS_DIR/demo-2of3/group_pubkey.txt"
            if [ -f "$group_pk_file" ]; then
                local known_group_pk="$(cat "$group_pk_file" | tr -d '\r\n ')"
                log_info "Known group_pubkey from demo harness: ${known_group_pk:0:32}..."
            fi
        fi
    fi
    echo ""
    
    log_info "Correlation check complete. To verify the signature cryptographically:"
    log_info "  cargo run -p frostr-utils --example sign_verify <signature> <digest> <group_pubkey>"
    log_info ""
    log_info "Or correlate with demo relay logs for non-cryptographic verification."
}

# Verify ECDH artifact correlation
verify_ecdh() {
    local request_id="$1"
    local target_pubkey="$2"
    local shared_secret="$3"
    
    log_info "=== ECDH Verification ==="
    echo ""
    
    # Validate request_id
    if validate_hex "$request_id" 32 "request_id"; then
        echo "  request_id: ${request_id:0:32}... (${#request_id} chars)"
    fi
    echo ""
    
    # Validate target_pubkey (should be 64-char hex - x-only pubkey)
    if validate_hex "$target_pubkey" 64 "target_pubkey"; then
        echo "  target_pubkey: ${target_pubkey:0:32}... (${#target_pubkey} chars)"
    fi
    echo ""
    
    # Validate shared_secret (should be 64-char hex - ECDH result)
    if validate_hex "$shared_secret" 64 "shared_secret"; then
        echo "  shared_secret: ${shared_secret:0:32}... (${#shared_secret} chars)"
    fi
    echo ""
    
    log_info "ECDH correlation check complete. The shared_secret should be:"
    log_info "  - Derived from local share * target_pubkey using ECDH"
    log_info "  - 64 chars of lowercase hex (x-only representation)"
    log_info ""
    log_info "To verify cryptographically, re-derive ECDH locally and compare."
}

# Read from clipboard (macOS pbpaste)
read_clipboard() {
    if command -v pbpaste >/dev/null 2>&1; then
        pbpaste | tr -d '\r\n ' | xargs echo -n
    else
        log_error "pbpaste not available"
        return 1
    fi
}

# Main command handler
case "${1:-}" in
    sign)
        if [ $# -lt 4 ]; then
            echo "Usage: $0 sign <request_id> <digest> <signature> [group_pubkey]"
            exit 1
        fi
        verify_sign "$2" "$3" "$4" "${5:-}"
        ;;
    ecdh)
        if [ $# -lt 4 ]; then
            echo "Usage: $0 ecdh <request_id> <target_pubkey> <shared_secret>"
            exit 1
        fi
        verify_ecdh "$2" "$3" "$4"
        ;;
    sign-clipboard)
        log_info "Reading sign values from clipboard..."
        local values="$(read_clipboard)"
        # Clipboard format: request_id,digest,signature,group_pubkey
        IFS=',' read -r request_id digest signature group_pubkey <<< "$values"
        verify_sign "$request_id" "$digest" "$signature" "${group_pubkey:-}"
        ;;
    ecdh-clipboard)
        log_info "Reading ECDH values from clipboard..."
        local values="$(read_clipboard)"
        # Clipboard format: request_id,target_pubkey,shared_secret
        IFS=',' read -r request_id target_pubkey shared_secret <<< "$values"
        verify_ecdh "$request_id" "$target_pubkey" "$shared_secret"
        ;;
    *)
        echo "VAL-SIGN Signature and ECDH Verifier Helper"
        echo ""
        echo "Usage:"
        echo "  $0 sign <request_id> <digest> <signature> [group_pubkey]"
        echo "  $0 ecdh <request_id> <target_pubkey> <shared_secret>"
        echo "  $0 sign-clipboard"
        echo "  $0 ecdh-clipboard"
        echo ""
        echo "This verifier correlates captured signing artifacts without handling secrets."
        echo "It validates hex format and provides guidance for cryptographic verification."
        exit 0
        ;;
esac