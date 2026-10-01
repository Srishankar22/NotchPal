#!/bin/bash
# Builds NotchPal.app — a normal double-clickable Mac app.
#
#   ./build-app.sh            → build/NotchPal.app
#   ./build-app.sh --install  → also copies it to /Applications and opens it
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="NotchPal"
BUNDLE_ID="com.notchpal.NotchPal"
VERSION="1.0"
APP="build/$APP_NAME.app"
WORK="build/.work"

echo "→ Compiling (release)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "→ Drawing the icon…"
mkdir -p "$WORK"
if [ ! -f "$WORK/AppIcon.icns" ] || [ scripts/make-icon.swift -nt "$WORK/AppIcon.icns" ] \
   || [ Sources/NotchPal/PipView.swift -nt "$WORK/AppIcon.icns" ]; then
    swiftc -O -parse-as-library -o "$WORK/make-icon" \
        scripts/make-icon.swift \
        Sources/NotchPal/PipView.swift Sources/NotchPal/PipMotion.swift Sources/NotchPal/PipSkins.swift \
        Sources/NotchPal/PalModel.swift Sources/NotchPal/Reminders.swift Sources/NotchPal/Settings.swift \
        Sources/NotchPal/Shelf.swift Sources/NotchPal/Clipboard.swift Sources/NotchPal/NowPlaying.swift
    "$WORK/make-icon" "$WORK/icon-1024.png"

    ICONSET="$WORK/AppIcon.iconset"
    rm -rf "$ICONSET" && mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z $double $double "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$WORK/AppIcon.icns"
fi

echo "→ Building the music helper (mediaremote-adapter)…"
ADAPTER_BIN="$WORK/MediaRemoteAdapter.framework/MediaRemoteAdapter"
if [ ! -e "$ADAPTER_BIN" ] || [ -n "$(find Vendor/mediaremote-adapter scripts/build-mediaremote-adapter.sh -newer "$ADAPTER_BIN" -type f | head -1)" ]; then
    scripts/build-mediaremote-adapter.sh "$WORK"
fi

echo "→ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$WORK/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Dancing Pip: the adapter's Perl script and helper framework (BSD 3-Clause, license included).
mkdir -p "$APP/Contents/Frameworks"
cp -R "$WORK/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/"
cp Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl "$APP/Contents/Resources/"
cp Vendor/mediaremote-adapter/LICENSE "$APP/Contents/Resources/mediaremote-adapter-LICENSE.txt"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>          <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>           <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>           <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>$VERSION</string>
    <key>CFBundleVersion</key>              <string>1</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <!-- Menu bar app: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key>                  <true/>
    <key>NSHighResolutionCapable</key>      <true/>
</dict>
</plist>
PLIST

# Local ("ad-hoc") signature so macOS treats it as one consistent app.
codesign --force --sign - "$APP"

echo "✓ Built $APP"

if [ "${1:-}" = "--install" ]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    echo "✓ Installed to /Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
fi
