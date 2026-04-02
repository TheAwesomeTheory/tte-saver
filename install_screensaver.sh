#!/bin/bash
# Install our custom screensaver into macOS Sequoia's built-in system

UUID="0C105649-6714-4677-889D-065214891A20"
ASSET_DIR="/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS"
ENTRIES="/Library/Application Support/com.apple.idleassetsd/Customer/entries.json"
SNAP_DIR="/Library/Application Support/com.apple.idleassetsd/snapshots"
VIDEO="/Users/austin/screensaver/clips/screensaver_final.mp4"
THUMB="/tmp/${UUID}.jpg"

echo "Backing up entries.json..."
sudo cp "$ENTRIES" "${ENTRIES}.bak"

echo "Copying video..."
sudo cp "$VIDEO" "$ASSET_DIR/$UUID.mov"

echo "Copying thumbnail..."
sudo mkdir -p "$SNAP_DIR"
sudo cp "$THUMB" "$SNAP_DIR/$UUID.jpg"

echo "Adding entry to entries.json..."
sudo python3 -c "
import json
with open('$ENTRIES') as f:
    data = json.load(f)
new_asset = {
    'id': '$UUID',
    'shotID': 'CUSTOM_${UUID}',
    'accessibilityLabel': 'Austin TTE Screensaver',
    'localizedNameKey': 'Austin TTE Screensaver',
    'showInTopLevel': True,
    'includeInShuffle': True,
    'previewImage': '',
    'url-4K-SDR-240FPS': 'file://$ASSET_DIR/$UUID.mov',
    'categories': [],
    'subcategories': [],
    'preferredOrder': 999,
    'pointsOfInterest': {'0': 'custom'}
}
data['assets'].append(new_asset)
with open('$ENTRIES', 'w') as f:
    json.dump(data, f, indent=2)
"

echo "Restarting idleassetsd..."
sudo killall idleassetsd

echo "Done! Go to System Settings > Screen Saver and select 'Austin TTE Screensaver'"
