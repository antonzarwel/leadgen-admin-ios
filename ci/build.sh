#!/usr/bin/env bash
# Build the native Lead Gen iPhone app (SwiftUI) and upload it to TestFlight.
# Called by .github/workflows/testflight.yml. All logic lives here so it can be
# changed without editing the workflow file.
# Env: ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 APPLE_TEAM_ID RUN_NUMBER RUNNER_TEMP
set -euo pipefail
APP_DIR=ios/LeadGen
PROJECT=$APP_DIR/LeadGen.xcodeproj
SCHEME=LeadGen
for v in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 APPLE_TEAM_ID; do
  [ -n "${!v:-}" ] || { echo "::error::secret $v is not set"; exit 1; }
done
KEYDIR="$RUNNER_TEMP/keys"; mkdir -p "$KEYDIR"
KEY="$KEYDIR/AuthKey_${ASC_KEY_ID}.p8"
printf '%s\n' "$ASC_KEY_P8" > "$KEY"; chmod 600 "$KEY"
trap 'rm -rf "$KEYDIR"' EXIT
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

sudo xcode-select -s "$(ls -d /Applications/Xcode_26*.app | sort -V | tail -1)"
xcodebuild -version

# The Xcode project is generated from ios/LeadGen/project.yml (XcodeGen).
command -v xcodegen >/dev/null || HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install xcodegen
(cd "$APP_DIR" && xcodegen generate)

BUILD_NUMBER=$(( 100 + ${RUN_NUMBER:-0} ))
# Archive without signing: an Automatic-signed archive needs a development
# profile, which Apple refuses when the team has no registered devices.
# The export step below signs for App Store distribution (cloud managed).
set +e
xcodebuild archive \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$RUNNER_TEMP/App.xcarchive" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" > "$RUNNER_TEMP/archive.log" 2>&1
rc=$?
set -e
grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)" "$RUNNER_TEMP/archive.log" | sort -u | head -200 || true
[ $rc -eq 0 ] && [ -d "$RUNNER_TEMP/App.xcarchive" ] || { tail -120 "$RUNNER_TEMP/archive.log"; exit 1; }

sed "s/__TEAM_ID__/${APPLE_TEAM_ID}/" ci/ExportOptions.plist.template > "$RUNNER_TEMP/ExportOptions.plist"
xcodebuild -exportArchive \
  -archivePath "$RUNNER_TEMP/App.xcarchive" \
  -exportOptionsPlist "$RUNNER_TEMP/ExportOptions.plist" \
  -exportPath "$RUNNER_TEMP/export" "${AUTH[@]}" 2>&1 | tee "$RUNNER_TEMP/export.log"
test "${PIPESTATUS[0]}" -eq 0
echo "Uploaded build $BUILD_NUMBER to App Store Connect"
