#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# == 1 && -d "$1" ]] || { echo 'Usage: scripts/package-macos.sh APP' >&2; exit 2; }
APP="$(cd "$1" && pwd)"
PLIST="$APP/Contents/Info.plist"
IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
[[ "$IDENTIFIER" == com.ashrocket.LokiDotZoomies ]] || { echo 'The standard installer requires the standard Zoomies app.' >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
ARCH="$(uname -m)"
codesign --verify --strict "$APP"
STAGE="$(mktemp -d "$(dirname "$APP")/installer.XXXXXX")"
mkdir -p "$STAGE/root/Applications" "$ROOT/dist"
ditto "$APP" "$STAGE/root/Applications/LokiDot Zoomies.app"
pkgbuild --analyze --root "$STAGE/root" "$STAGE/components.plist"
# Never relocate to another app copy, including a copy in Trash.
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$STAGE/components.plist"
/usr/libexec/PlistBuddy -c 'Set :0:BundleHasStrictIdentifier true' "$STAGE/components.plist"
pkgbuild --root "$STAGE/root" --component-plist "$STAGE/components.plist" \
  --identifier "$IDENTIFIER.pkg" --version "$VERSION" --install-location / \
  "$STAGE/ZoomiesComponent.pkg"
cat > "$STAGE/Distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>LokiDot Zoomies</title>
  <options customize="never" require-scripts="false" hostArchitectures="$ARCH"/>
  <domains enable_currentUserHome="true" enable_localSystem="false" enable_anywhere="false"/>
  <volume-check script="true"><allowed-os-versions><os-version min="13.0"/></allowed-os-versions></volume-check>
  <choices-outline><line choice="zoomies"/></choices-outline>
  <choice id="zoomies" visible="false" title="LokiDot Zoomies" description="LokiDot Zoomies app"><pkg-ref id="$IDENTIFIER.pkg"/></choice>
  <pkg-ref id="$IDENTIFIER.pkg" version="$VERSION" onConclusion="None">ZoomiesComponent.pkg</pkg-ref>
  <pkg-ref id="$IDENTIFIER.pkg"><must-close><app id="$IDENTIFIER"/></must-close></pkg-ref>
</installer-gui-script>
EOF
OUTPUT="$ROOT/dist/LokiDot-Zoomies-$VERSION-macos-$ARCH.pkg"
productbuild --distribution "$STAGE/Distribution.xml" --package-path "$STAGE" "$OUTPUT"
printf 'Installer: %s\nInstalls for the current user in ~/Applications.\n' "$OUTPUT"
