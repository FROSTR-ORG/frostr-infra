#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IOS_FILE="${ROOT}/ios/Sources/ContentView.swift"
ANDROID_FILE="${ROOT}/android/app/src/main/java/com/frostr/igloo/ui/MainApp.kt"

missing=0

require_pattern() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if ! grep -Fq "$pattern" "$file"; then
    printf 'missing: %s (%s)\n' "$label" "$pattern" >&2
    missing=1
  fi
}

require_pattern "$IOS_FILE" 'create_keyset_create_icon' 'iOS create keyset entry icon'
require_pattern "$IOS_FILE" 'create_keyset_rotate_icon' 'iOS rotate keyset entry icon'
require_pattern "$ANDROID_FILE" 'create_keyset_create_icon' 'Android create keyset entry icon'
require_pattern "$ANDROID_FILE" 'create_keyset_rotate_icon' 'Android rotate keyset entry icon'

require_pattern "$IOS_FILE" 'create_mode_create_icon' 'iOS create mode icon'
require_pattern "$IOS_FILE" 'create_mode_rotate_icon' 'iOS rotate mode icon'
require_pattern "$ANDROID_FILE" 'create_mode_create_icon' 'Android create mode icon'
require_pattern "$ANDROID_FILE" 'create_mode_rotate_icon' 'Android rotate mode icon'

require_pattern "$IOS_FILE" 'create_review_profile_icon' 'iOS review profile icon'
require_pattern "$IOS_FILE" 'create_review_share_key_icon' 'iOS review share key icon'
require_pattern "$IOS_FILE" 'create_review_group_key_icon' 'iOS review group key icon'
require_pattern "$IOS_FILE" 'create_review_relays_icon' 'iOS review relays icon'
require_pattern "$ANDROID_FILE" 'create_review_profile_icon' 'Android review profile icon'
require_pattern "$ANDROID_FILE" 'create_review_share_key_icon' 'Android review share key icon'
require_pattern "$ANDROID_FILE" 'create_review_group_key_icon' 'Android review group key icon'
require_pattern "$ANDROID_FILE" 'create_review_relays_icon' 'Android review relays icon'

require_pattern "$IOS_FILE" 'distribute_copy_icon_' 'iOS distribute copy icon'
require_pattern "$IOS_FILE" 'distribute_qr_icon_' 'iOS distribute QR icon'
require_pattern "$IOS_FILE" 'distribute_save_icon_' 'iOS distribute save icon'
require_pattern "$ANDROID_FILE" 'distribute_copy_icon_' 'Android distribute copy icon'
require_pattern "$ANDROID_FILE" 'distribute_qr_icon_' 'Android distribute QR icon'
require_pattern "$ANDROID_FILE" 'distribute_save_icon_' 'Android distribute save icon'

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

printf 'create-keyset UI parity affordance contract: ok\n'
