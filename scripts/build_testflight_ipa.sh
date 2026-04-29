#!/usr/bin/env bash
set -euo pipefail

APP_VERSION="${1:-}"

if [[ -z "$APP_VERSION" ]]; then
  echo "Usage: $0 <marketing-version>" >&2
  exit 64
fi

if [[ -z "${IOS_BUILD_NUMBER:-}" ]]; then
  if [[ -n "${GITHUB_RUN_NUMBER:-}" ]]; then
    IOS_BUILD_NUMBER="${GITHUB_RUN_NUMBER}.${GITHUB_RUN_ATTEMPT:-1}"
  else
    IOS_BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"
  fi
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/TestFlight"
ARCHIVE_PATH="$BUILD_DIR/Onpa.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/ExportOptions.plist"
PROFILE_PLIST="$BUILD_DIR/profile.plist"
PROFILES_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
BUNDLE_IDENTIFIER="${IOS_BUNDLE_IDENTIFIER:-org.odinseye.onpa}"
WIDGET_BUNDLE_IDENTIFIER="${IOS_WIDGET_BUNDLE_IDENTIFIER:-org.odinseye.onpa.OnpaWidget}"
IPA_PATH="$EXPORT_PATH/Onpa.ipa"

# Resolves the installed App Store provisioning profile for the given bundle id
# and prints "PROFILE_NAME|TEAM_ID" on stdout.
find_profile_for_bundle() {
  local target_bundle="$1"
  local profile
  local app_identifier
  local profile_name
  local team_id

  if [[ ! -d "$PROFILES_DIR" ]]; then
    return 1
  fi

  while IFS= read -r profile; do
    if ! security cms -D -i "$profile" >"$PROFILE_PLIST" 2>/dev/null; then
      continue
    fi

    app_identifier="$(/usr/libexec/PlistBuddy -c 'Print Entitlements:application-identifier' "$PROFILE_PLIST" 2>/dev/null || true)"

    if [[ "$app_identifier" == *."$target_bundle" ]]; then
      profile_name="$(/usr/libexec/PlistBuddy -c 'Print Name' "$PROFILE_PLIST")"
      team_id="$(/usr/libexec/PlistBuddy -c 'Print TeamIdentifier:0' "$PROFILE_PLIST")"
      echo "$profile_name|$team_id"
      return 0
    fi
  done < <(find "$PROFILES_DIR" -name '*.mobileprovision' -print)

  return 1
}

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_PATH"

# Inject the semantic-release-generated changelog into the app bundle so the
# in-app Settings > Changelog screen shows real release notes for this build.
#
# `@semantic-release/changelog` only writes the *new* release into CHANGELOG.md
# (and the file is not committed back to the repo), so the file passed in via
# semantic-release contains a single section. Regenerate the full release
# history from git tags using conventional-changelog so users can see every
# previous release in the in-app changelog screen, then fall back to the
# semantic-release output if the regeneration fails.
ROOT_CHANGELOG="$ROOT_DIR/CHANGELOG.md"
BUNDLED_CHANGELOG="$ROOT_DIR/src/Onpa/Resources/CHANGELOG.md"
BUNDLED_CHANGELOG_BACKUP="$BUILD_DIR/CHANGELOG.md.dev-backup"
FULL_CHANGELOG="$BUILD_DIR/CHANGELOG.full.md"

if [[ -f "$BUNDLED_CHANGELOG" ]]; then
  cp "$BUNDLED_CHANGELOG" "$BUNDLED_CHANGELOG_BACKUP"
  trap 'if [[ -f "$BUNDLED_CHANGELOG_BACKUP" ]]; then cp "$BUNDLED_CHANGELOG_BACKUP" "$BUNDLED_CHANGELOG"; fi' EXIT
fi

CHANGELOG_TITLE="# Changelog"$'\n\n'"All notable changes to Onpa are documented here."$'\n'

if (
  cd "$ROOT_DIR" &&
  printf '%s' "$CHANGELOG_TITLE" >"$FULL_CHANGELOG" &&
  npx --yes -p conventional-changelog-cli@^5 conventional-changelog \
    -p angular \
    -r 0 \
    >>"$FULL_CHANGELOG"
) && [[ -s "$FULL_CHANGELOG" ]]; then
  # `conventional-changelog` labels the unreleased section with whatever is in
  # `package.json` (currently the `0.0.0-development` placeholder). Rewrite it
  # to the real release version so the in-app changelog shows the right name
  # for the build that's shipping.
  python3 - "$FULL_CHANGELOG" "$APP_VERSION" <<'PY'
import re
import sys

path, version = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as fh:
    text = fh.read()
text = re.sub(
    r"^# \[?0\.0\.0-development\]?(?:\([^)]*\))?(\s*\([^)]+\))?",
    f"# {version}\\1",
    text,
    count=1,
    flags=re.MULTILINE,
)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(text)
PY

  echo "Embedding full-history CHANGELOG.md (generated from git tags) into app resources..."
  cp "$FULL_CHANGELOG" "$BUNDLED_CHANGELOG"
elif [[ -f "$ROOT_CHANGELOG" ]]; then
  echo "Falling back to semantic-release CHANGELOG.md (single release)..."
  cp "$ROOT_CHANGELOG" "$BUNDLED_CHANGELOG"
else
  echo "No CHANGELOG.md available; keeping bundled dev changelog placeholder."
fi

if ! app_profile_info="$(find_profile_for_bundle "$BUNDLE_IDENTIFIER")"; then
  echo "No installed App Store provisioning profile found for $BUNDLE_IDENTIFIER." >&2
  echo "Run apple-actions/download-provisioning-profiles before this script." >&2
  exit 65
fi

if ! widget_profile_info="$(find_profile_for_bundle "$WIDGET_BUNDLE_IDENTIFIER")"; then
  echo "No installed App Store provisioning profile found for $WIDGET_BUNDLE_IDENTIFIER." >&2
  echo "Run apple-actions/download-provisioning-profiles before this script." >&2
  exit 65
fi

PROFILE_NAME="${app_profile_info%%|*}"
TEAM_ID="${app_profile_info##*|}"
WIDGET_PROFILE_NAME="${widget_profile_info%%|*}"

cat >"$EXPORT_OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>app-store-connect</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>$BUNDLE_IDENTIFIER</key>
    <string>$PROFILE_NAME</string>
    <key>$WIDGET_BUNDLE_IDENTIFIER</key>
    <string>$WIDGET_PROFILE_NAME</string>
  </dict>
  <key>signingCertificate</key>
  <string>Apple Distribution</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>$TEAM_ID</string>
</dict>
</plist>
PLIST

echo "Archiving Onpa $APP_VERSION ($IOS_BUILD_NUMBER) for App Store Connect..."
echo "  App profile:    $PROFILE_NAME"
echo "  Widget profile: $WIDGET_PROFILE_NAME"
xcodebuild \
  -project "$ROOT_DIR/src/Onpa.xcodeproj" \
  -scheme Onpa \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$ROOT_DIR/build/DerivedData" \
  MARKETING_VERSION="$APP_VERSION" \
  CURRENT_PROJECT_VERSION="$IOS_BUILD_NUMBER" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  archive

echo "Exporting signed IPA..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

exported_ipa="$(find "$EXPORT_PATH" -name '*.ipa' -print -quit)"

if [[ -z "$exported_ipa" ]]; then
  echo "No IPA was produced in $EXPORT_PATH" >&2
  exit 66
fi

if [[ "$exported_ipa" != "$IPA_PATH" ]]; then
  mv "$exported_ipa" "$IPA_PATH"
fi

echo "Exported $IPA_PATH."
