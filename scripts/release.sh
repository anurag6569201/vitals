#!/bin/bash
# Builds a signed, notarized, stapled Vitals.dmg for direct download.
#
# One-time setup (see RELEASE.md):
#   1. Apple Developer Program membership + a "Developer ID Application" certificate in Keychain.
#   2. Store notarization credentials:
#        xcrun notarytool store-credentials vitals-notary \
#          --apple-id you@example.com --team-id X5H55SY52K --password <app-specific-password>
#
# Usage: scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(xcodebuild -project Vitals.xcodeproj -scheme Vitals -showBuildSettings 2>/dev/null \
  | awk '/MARKETING_VERSION/ {print $3; exit}')
OUT=".build/release/$VERSION"
rm -rf "$OUT" && mkdir -p "$OUT"

echo "▸ Archiving Vitals $VERSION"
xcodebuild -project Vitals.xcodeproj -scheme Vitals -configuration Release \
  -archivePath "$OUT/Vitals.xcarchive" archive | xcbeautify 2>/dev/null || \
xcodebuild -project Vitals.xcodeproj -scheme Vitals -configuration Release \
  -archivePath "$OUT/Vitals.xcarchive" archive -quiet

echo "▸ Exporting with Developer ID"
xcodebuild -exportArchive -archivePath "$OUT/Vitals.xcarchive" \
  -exportOptionsPlist scripts/ExportOptions.plist -exportPath "$OUT/export" -quiet

echo "▸ Building DMG"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$OUT/export/Vitals.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Vitals" -srcfolder "$STAGE" -ov -format UDZO "$OUT/Vitals-$VERSION.dmg" >/dev/null
codesign --sign "Developer ID Application" --timestamp "$OUT/Vitals-$VERSION.dmg"

echo "▸ Notarizing (a few minutes)"
xcrun notarytool submit "$OUT/Vitals-$VERSION.dmg" --keychain-profile vitals-notary --wait
xcrun stapler staple "$OUT/Vitals-$VERSION.dmg"
spctl -a -t open --context context:primary-signature -v "$OUT/Vitals-$VERSION.dmg"

cat > "$OUT/latest.json" <<JSON
{ "version": "$VERSION", "url": "https://REPLACE-WITH-YOUR-SITE/vitals/Vitals-$VERSION.dmg", "notes": "" }
JSON

echo "✓ Done: $OUT/Vitals-$VERSION.dmg"
echo "  Upload the DMG and latest.json to your site (see RELEASE.md)."
