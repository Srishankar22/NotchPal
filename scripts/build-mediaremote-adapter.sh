#!/bin/bash
# Builds MediaRemoteAdapter.framework from Vendor/mediaremote-adapter with plain clang
# (the upstream project uses CMake; this mirrors its CMakeLists.txt).
#
#   scripts/build-mediaremote-adapter.sh OUT_DIR   → OUT_DIR/MediaRemoteAdapter.framework
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Vendor/mediaremote-adapter"
OUT="${1:?usage: $0 OUT_DIR}"
NAME="MediaRemoteAdapter"
FW="$OUT/$NAME.framework"

rm -rf "$FW"
mkdir -p "$FW/Versions/A/Resources" "$FW/Versions/A/Headers"

clang -dynamiclib -fobjc-arc -fvisibility=default -O2 \
    -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
    -I"$SRC/include" -I"$SRC/src" \
    "$SRC"/src/adapter/*.m "$SRC/src/private/MediaRemote.m" \
    "$SRC/src/utility/Debounce.m" "$SRC/src/utility/helpers.m" \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name "@rpath/$NAME.framework/Versions/A/$NAME" \
    -o "$FW/Versions/A/$NAME"

cp "$SRC/include/MediaRemoteAdapter.h" "$FW/Versions/A/Headers/"
cat > "$FW/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>         <string>$NAME</string>
    <key>CFBundleIdentifier</key>         <string>com.vandenbe.$NAME</string>
    <key>CFBundleName</key>               <string>$NAME</string>
    <key>CFBundlePackageType</key>        <string>FMWK</string>
    <key>CFBundleShortVersionString</key> <string>0.1</string>
    <key>CFBundleVersion</key>            <string>0.1.0</string>
</dict>
</plist>
PLIST

ln -sfn A "$FW/Versions/Current"
ln -sfn "Versions/Current/$NAME" "$FW/$NAME"
ln -sfn Versions/Current/Resources "$FW/Resources"
ln -sfn Versions/Current/Headers "$FW/Headers"

codesign --force --sign - "$FW" >/dev/null
