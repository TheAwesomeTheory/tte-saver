#!/bin/bash
set -e
cd "$(dirname "$0")"

rm -rf AustinSaver/build
mkdir -p AustinSaver/build/AustinSaver.saver/Contents/MacOS
mkdir -p AustinSaver/build/AustinSaver.saver/Contents/Resources/AustinEffects

swiftc -target arm64-apple-macos14.0 \
  -framework ScreenSaver -framework AVFoundation -framework AVKit \
  -framework QuartzCore -framework AppKit -framework CoreImage -framework CoreText \
  -framework CoreVideo \
  -module-name AustinSaver -emit-library \
  -o AustinSaver/build/AustinSaver.saver/Contents/MacOS/AustinSaver \
  AustinSaver/AustinSaverView.swift

cp AustinSaver/Info.plist AustinSaver/build/AustinSaver.saver/Contents/
cp effects_data/*.tte AustinSaver/build/AustinSaver.saver/Contents/Resources/AustinEffects/

rm -rf "$HOME/Library/Screen Savers/AustinSaver.saver"
cp -R AustinSaver/build/AustinSaver.saver "$HOME/Library/Screen Savers/"
killall legacyScreenSaver 2>/dev/null || true

# Also rebuild test app
swiftc -target arm64-apple-macos14.0 \
  -framework ScreenSaver -framework AVFoundation -framework AVKit \
  -framework QuartzCore -framework AppKit -framework CoreImage -framework CoreText \
  -framework CoreVideo \
  -module-name AustinSaver -parse-as-library \
  -o test_app AustinSaver/test.swift AustinSaver/AustinSaverView.swift

echo "Deployed + test_app rebuilt"
