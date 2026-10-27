#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

PROJECT="Yuedu-Reader.xcodeproj"
SCHEME="Yuedu-Reader"
VERSION="${1:-1.0.0}"
# Build number derived from the last segment of VERSION (e.g. "1.0.16" -> 16)
BUILD_NUMBER="${VERSION##*.}"

echo "Building $SCHEME (unsigned) for iOS device, version $VERSION ..."
mkdir -p build

# GoogleService-Info.plist is required by the Xcode project but is gitignored
# (contains Firebase secrets). Generate a well-formed placeholder so the build
# can proceed; runtime Firebase features degrade gracefully when keys are absent.
if [ ! -f "GoogleService-Info.plist" ]; then
  cat > GoogleService-Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CLIENT_ID</key>
	<string>placeholder-client-id</string>
	<key>REVERSED_CLIENT_ID</key>
	<string>com.googleusercontent.apps.placeholder</string>
	<key>API_KEY</key>
	<string>placeholder-api-key</string>
	<key>GCM_SENDER_ID</key>
	<string>0</string>
	<key>PLIST_VERSION</key>
	<string>1</string>
	<key>BUNDLE_ID</key>
	<string>com.zhong228.shuyue</string>
	<key>PROJECT_ID</key>
	<string>shuyue-placeholder</string>
	<key>STORAGE_BUCKET</key>
	<string>shuyue-placeholder.appspot.com</string>
	<key>IS_ADS_ENABLED</key>
	<false/>
	<key>IS_ANALYTICS_ENABLED</key>
	<false/>
	<key>IS_APPINVITE_ENABLED</key>
	<true/>
	<key>IS_GCM_ENABLED</key>
	<true/>
	<key>GOOGLE_APP_ID</key>
	<string>1:0:ios:placeholder</string>
</dict>
</plist>
PLIST
  echo "Generated placeholder GoogleService-Info.plist (gitignored, not committed)"
fi

# 1. Release build without code signing (device generic destination)
# MARKETING_VERSION is injected from $VERSION so the in-app version always
# matches the tag/release name passed to this script (root cause of
# ShuYue 1.0.14 showing 1.0.13 in-app: the tag bumped but xcconfig did not).
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_COMPILATION_MODE=incremental \
  build > build/xcodebuild.log 2>&1 || {
    echo "xcodebuild FAILED (error lines):"
    grep -n "error:" build/xcodebuild.log | head -40 || true
    echo "--- last 30 lines ---"
    tail -30 build/xcodebuild.log
    exit 1
  }

# 2. Locate built .app
APP="$(find build/DerivedData/Build/Products/Release-iphoneos -maxdepth 1 -name '*.app' -type d | head -1)"
if [ -z "$APP" ]; then
  echo "ERROR: .app not found in build products"
  exit 1
fi
echo "App bundle: $APP"

# 3. Assemble unsigned IPA (standard Payload layout)
rm -rf build/unsigned build/ShuYue-*.ipa
mkdir -p build/unsigned/Payload
cp -R "$APP" build/unsigned/Payload/

# 3b. Strip restricted entitlements so the UNSIGNED IPA launches under
#     TrollStore / self-signing.
#
#     Root cause of Issue #1 (TrollStore and self-sign both crash on launch):
#     the app's default entitlements request App Groups, CloudKit, and
#     Sign-in-with-Apple. An unsigned IPA has NO provisioning profile to
#     authorize those capabilities, so iOS rejects the launch at
#     entitlements-validation time and the app exits immediately.
#
#     Removing the embedded entitlements lets TrollStore re-sign and run the
#     app. In this sideloaded build, iCloud sync / App Group sharing / SiWA
#     are unavailable — acceptable for a sideloaded build. If a fully
#     featured signed build is needed later, supply a provisioning profile
#     that authorizes these capabilities and sign the IPA instead.
APP_IN_PAYLOAD="build/unsigned/Payload/$(basename "$APP")"
if [ -f "$APP_IN_PAYLOAD/archived-expanded-entitlements.xcent" ]; then
  rm -f "$APP_IN_PAYLOAD/archived-expanded-entitlements.xcent"
  echo "Removed embedded restricted entitlements (archived-expanded-entitlements.xcent)"
fi
rm -f "$APP_IN_PAYLOAD/Entitlements.plist"

cd build/unsigned
zip -qry "../ShuYue-v${VERSION}.ipa" Payload
cd "$PROJECT_DIR"

echo "IPA created: $(pwd)/build/ShuYue-v${VERSION}.ipa"
ls -lh "build/ShuYue-v${VERSION}.ipa"
