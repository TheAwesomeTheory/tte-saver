import json

ENTRIES = "/Library/Application Support/com.apple.idleassetsd/Customer/entries.json"
UUID = "0C105649-6714-4677-889D-065214891A20"
CAT_UUID = "AAAA0000-0000-0000-0000-000000000001"
SUB_UUID = "AAAA0000-0000-0000-0000-000000000002"

with open(ENTRIES) as f:
    data = json.load(f)

# Remove our old entry if it exists
data['assets'] = [a for a in data['assets'] if a['id'] != UUID]

# Add our asset entry
new_asset = {
    "id": UUID,
    "shotID": "CUSTOM_AUSTIN_TTE",
    "accessibilityLabel": "Austin TTE Screensaver",
    "localizedNameKey": "Austin TTE Screensaver",
    "showInTopLevel": True,
    "includeInShuffle": True,
    "previewImage": "",
    "url-4K-SDR-240FPS": "file:///Library/Application%20Support/com.apple.idleassetsd/Customer/4KSDR240FPS/" + UUID + ".mov",
    "categories": [CAT_UUID],
    "subcategories": [SUB_UUID],
    "preferredOrder": 0,
    "pointsOfInterest": {"0": "custom"}
}
data['assets'].append(new_asset)

# Remove our old category if it exists
data['categories'] = [c for c in data['categories'] if c['id'] != CAT_UUID]

# Add our custom category
new_category = {
    "id": CAT_UUID,
    "preferredOrder": -1,
    "representativeAssetID": UUID,
    "localizedNameKey": "Custom",
    "localizedDescriptionKey": "Custom screensavers",
    "previewImage": "",
    "subcategories": [
        {
            "id": SUB_UUID,
            "preferredOrder": 0,
            "representativeAssetID": UUID,
            "localizedNameKey": "Austin",
            "localizedDescriptionKey": "Austin TTE Effects",
            "previewImage": ""
        }
    ]
}
data['categories'].insert(0, new_category)

with open(ENTRIES, 'w') as f:
    json.dump(data, f, indent=2)

print("Added custom category + asset. Total assets:", len(data['assets']), "Total categories:", len(data['categories']))
