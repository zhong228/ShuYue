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

# 3b. Fake-sign the binaries with ldid, embedding the project's entitlements,
#     so the sideloaded IPA keeps iCloud (CloudKit) and App Group capabilities.
#
#     History: Issue #1 — a build whose entitlements blob requested App Groups /
#     CloudKit / SiWA but had NO provisioning profile was rejected at launch
#     (entitlements validation) and crashed on start under every install path.
#     The old workaround stripped the entitlements blob entirely, which also
#     stripped iCloud: every install then showed 「iCloud 状态待确认」 and sync
#     stayed off.
#
#     Now: each Mach-O is fake-signed with ldid carrying its target's
#     entitlements (the same signer TrollStore uses). TrollStore's CoreTrust
#     validation accepts the fake signature and preserves the embedded
#     entitlements, so constructing CKContainer(identifier:) no longer triggers
#     the CloudKit os_crash and iCloud sync works when the device is signed
#     into iCloud. Self-signing tools (Sideloadly / AltStore) re-sign with
#     their own free profile; its embedded.mobileprovision lacks the iCloud
#     container, CloudKitAvailability keeps CloudKit off there, and the app
#     still launches — crash-free in every path (see CloudKitAvailability.swift
#     for the runtime gates).
APP_IN_PAYLOAD="build/unsigned/Payload/$(basename "$APP")"
# Xcode's archive-time expanded entitlements are meaningless in an unsigned
# build and the CI guardrail requires them gone.
if [ -f "$APP_IN_PAYLOAD/archived-expanded-entitlements.xcent" ]; then
  rm -f "$APP_IN_PAYLOAD/archived-expanded-entitlements.xcent"
  echo "Removed archive-time expanded entitlements (archived-expanded-entitlements.xcent)"
fi
rm -f "$APP_IN_PAYLOAD/Entitlements.plist"

if ! command -v ldid > /dev/null 2>&1; then
  echo "Installing ldid..."
  brew install ldid
fi

# Main app binary: App Group + iCloud (CloudKit) + SiWA entitlements.
MAIN_EXECUTABLE="$(plutil -extract CFBundleExecutable raw -o - "$APP_IN_PAYLOAD/Info.plist")"
ldid -S"$PROJECT_DIR/Resources/Yuedu-Reader.entitlements" "$APP_IN_PAYLOAD/$MAIN_EXECUTABLE"
echo "Injected entitlements into $MAIN_EXECUTABLE (iCloud + App Group)"

# Extensions: App Group entitlements so the widget / share extension keep
# reading the shared container alongside the main app.
shopt -s nullglob
for APPCX in "$APP_IN_PAYLOAD"/PlugIns/*.appex; do
  EXEC="$(plutil -extract CFBundleExecutable raw -o - "$APPCX/Info.plist")"
  case "$(basename "$APPCX")" in
    *ShareExtension*) ENT="$PROJECT_DIR/ShareExtension/Yuedu-Reader-ShareExtension.entitlements" ;;
    *Widget*)         ENT="$PROJECT_DIR/Widget/Yuedu-Reader-Widget.entitlements" ;;
    *)                ENT="$PROJECT_DIR/ShareExtension/Yuedu-Reader-ShareExtension.entitlements" ;;
  esac
  if [ -n "$ENT" ] && [ -f "$ENT" ]; then
    ldid -S"$ENT" "$APPCX/$EXEC"
    echo "Injected entitlements into $(basename "$APPCX")"
  fi
done

cd build/unsigned
zip -qry "../ShuYue-v${VERSION}.ipa" Payload
cd "$PROJECT_DIR"

echo "IPA created: $(pwd)/build/ShuYue-v${VERSION}.ipa"
ls -lh "build/ShuYue-v${VERSION}.ipa"
