#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAVER_NAME="AustinSaver"
SAVER_DIR="$HOME/Library/Screen Savers/$SAVER_NAME.saver"
EFFECTS_DIR="$SCRIPT_DIR/effects_data"
BG_VIDEO="/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS/6D6834A4-2F0F-479A-B053-7D4DC5CB8EB7.mov"
BUILD_DIR="$SCRIPT_DIR/AustinSaver/build"
IDLE_TIME="${1:-120}"  # Default 2 minutes, override with first arg

echo "=== AustinSaver Installer ==="
echo ""

# Step 1: Pre-render effects if needed
if [ ! -d "$EFFECTS_DIR" ] || [ -z "$(ls "$EFFECTS_DIR"/*.tte 2>/dev/null)" ]; then
    echo "[1/5] Pre-rendering effects..."
    python3 "$SCRIPT_DIR/prerender_effects.py"
else
    echo "[1/5] Effects already pre-rendered ($(ls "$EFFECTS_DIR"/*.tte | wc -l | tr -d ' ') effects)"
fi

# Step 2: Compile
echo "[2/5] Compiling..."
mkdir -p "$BUILD_DIR/$SAVER_NAME.saver/Contents/MacOS"
mkdir -p "$BUILD_DIR/$SAVER_NAME.saver/Contents/Resources/AustinEffects"
mkdir -p "$BUILD_DIR/$SAVER_NAME.saver/Contents/Resources/AustinBackgrounds"

swiftc -emit-library -module-name "$SAVER_NAME" \
    -target arm64-apple-macos14.0 \
    -framework ScreenSaver -framework AVFoundation -framework AVKit \
    -framework QuartzCore -framework CoreImage -framework CoreText \
    -o "$BUILD_DIR/$SAVER_NAME.saver/Contents/MacOS/$SAVER_NAME" \
    "$SCRIPT_DIR/AustinSaver/AustinSaverView.swift"

cp "$SCRIPT_DIR/AustinSaver/Info.plist" "$BUILD_DIR/$SAVER_NAME.saver/Contents/"

# Step 3: Bundle resources (effects only — background uses Apple's built-in aerials)
echo "[3/5] Bundling effects..."
cp "$EFFECTS_DIR"/*.tte "$BUILD_DIR/$SAVER_NAME.saver/Contents/Resources/AustinEffects/"

# Step 4: Install
echo "[4/5] Installing..."
rm -rf "$SAVER_DIR"
cp -R "$BUILD_DIR/$SAVER_NAME.saver" "$SAVER_DIR"

# Step 5: Configure as active screensaver
echo "[5/5] Setting as active screensaver (idle: ${IDLE_TIME}s)..."
defaults -currentHost write com.apple.screensaver moduleDict -dict \
    moduleName -string "$SAVER_NAME" \
    path -string "$SAVER_DIR" \
    type -int 0
defaults -currentHost write com.apple.screensaver idleTime -int "$IDLE_TIME"

# Kill cached processes
killall System\ Settings legacyScreenSaver 2>/dev/null || true

echo ""
echo "Done! AustinSaver installed and active."
echo "  Screensaver activates after ${IDLE_TIME}s of idle."
echo "  Test it: open $SCRIPT_DIR/test_app"
echo "  Change idle time: $0 <seconds>"
