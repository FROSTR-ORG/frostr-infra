#!/usr/bin/env bash
# Verify debug diagnostics stay out of release surfaces.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_ID_RELEASE_ANDROID="com.frostr.igloo"
APP_ID_DEBUG_ANDROID="com.frostr.igloo.dev"
APP_ID_RELEASE_IOS="com.frostr.igloo"
APP_ID_DEBUG_IOS="com.frostr.igloo.dev"
EVIDENCE_ROOT="${EVIDENCE_ROOT:-$APPS/library/evidence/mobile-cross-platform-release-diagnostic-guard-$(date +%Y-%m-%d-%H%M%S)}"
mkdir -p "$EVIDENCE_ROOT"
SUMMARY="$EVIDENCE_ROOT/summary.txt"
: > "$SUMMARY"

echo "[release-guard $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"

require_absent() {
  local needle="$1"
  local file="$2"
  if grep -Fq "$needle" "$file"; then
    echo "[release-guard] unexpected '$needle' in $file" >&2
    exit 1
  fi
}

require_present() {
  local needle="$1"
  local file="$2"
  grep -Fq "$needle" "$file" || { echo "[release-guard] missing '$needle' in $file" >&2; exit 1; }
}

echo "[release-guard $(date +%H:%M:%S)] Android release manifest merge"
(
  cd "$APPS/android"
  ./gradlew :app:processReleaseMainManifest :app:assembleRelease
) > "$EVIDENCE_ROOT/android-release-build.log" 2>&1

ANDROID_MANIFEST="$APPS/android/app/build/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml"
[ -f "$ANDROID_MANIFEST" ] || { echo "[release-guard] missing merged release manifest: $ANDROID_MANIFEST" >&2; exit 1; }
cp "$ANDROID_MANIFEST" "$EVIDENCE_ROOT/android-release-AndroidManifest.xml"
require_present "package=\"$APP_ID_RELEASE_ANDROID\"" "$EVIDENCE_ROOT/android-release-AndroidManifest.xml"
require_absent "$APP_ID_DEBUG_ANDROID" "$EVIDENCE_ROOT/android-release-AndroidManifest.xml"
require_absent "DEBUG_TEST_" "$EVIDENCE_ROOT/android-release-AndroidManifest.xml"

ANDROID_RELEASE_APK="$APPS/android/app/build/outputs/apk/release/app-release-unsigned.apk"
[ -f "$ANDROID_RELEASE_APK" ] || ANDROID_RELEASE_APK="$APPS/android/app/build/outputs/apk/release/app-release.apk"
[ -f "$ANDROID_RELEASE_APK" ] || { echo "[release-guard] missing Android release APK" >&2; exit 1; }
unzip -p "$ANDROID_RELEASE_APK" AndroidManifest.xml > "$EVIDENCE_ROOT/android-release-apk-manifest.bin" 2>/dev/null || true
strings "$ANDROID_RELEASE_APK" > "$EVIDENCE_ROOT/android-release-apk-strings.txt"
require_absent "$APP_ID_DEBUG_ANDROID" "$EVIDENCE_ROOT/android-release-apk-strings.txt"

echo "[release-guard $(date +%H:%M:%S)] iOS Release simulator build"
(
  cd "$APPS"
  ./tools/xcode-run xcodebuild build \
    -project ios/IglooMobile.xcodeproj \
    -scheme IglooMobile \
    -destination "generic/platform=iOS Simulator" \
    -configuration Release \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES
) > "$EVIDENCE_ROOT/ios-release-build.log" 2>&1

IOS_RELEASE_APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Release-iphonesimulator/IglooMobile.app' -type d -print 2>/dev/null | head -1)"
[ -n "$IOS_RELEASE_APP" ] || { echo "[release-guard] missing iOS Release simulator app" >&2; exit 1; }
plutil -p "$IOS_RELEASE_APP/Info.plist" > "$EVIDENCE_ROOT/ios-release-info.plist.txt"
require_present "$APP_ID_RELEASE_IOS" "$EVIDENCE_ROOT/ios-release-info.plist.txt"
require_absent "$APP_ID_DEBUG_IOS" "$EVIDENCE_ROOT/ios-release-info.plist.txt"

strings "$IOS_RELEASE_APP/IglooMobile" > "$EVIDENCE_ROOT/ios-release-binary-strings.txt"
require_absent "test-create-keyset" "$EVIDENCE_ROOT/ios-release-binary-strings.txt"
require_absent "test-keyset-distribute" "$EVIDENCE_ROOT/ios-release-binary-strings.txt"
require_absent "test-save-settings" "$EVIDENCE_ROOT/ios-release-binary-strings.txt"
require_absent "test-inject-onboard" "$EVIDENCE_ROOT/ios-release-binary-strings.txt"

cat > "$SUMMARY" <<EOF
android_release_manifest=$ANDROID_MANIFEST
android_release_apk=$ANDROID_RELEASE_APK
ios_release_app=$IOS_RELEASE_APP
debug_surfaces_absent=true
result=pass
EOF

echo "[release-guard RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"
cat "$SUMMARY"
