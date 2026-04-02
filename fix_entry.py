import json

ENTRIES = "/Library/Application Support/com.apple.idleassetsd/Customer/entries.json"
UUID = "0C105649-6714-4677-889D-065214891A20"

with open(ENTRIES) as f:
    data = json.load(f)

# Find a landscape category and subcategory from an existing asset
landscape_cat = None
landscape_sub = None
for asset in data['assets']:
    if asset.get('categories') and asset.get('subcategories'):
        landscape_cat = asset['categories'][0]
        landscape_sub = asset['subcategories'][0]
        break

# Update our entry
for asset in data['assets']:
    if asset['id'] == UUID:
        asset['categories'] = [landscape_cat]
        asset['subcategories'] = [landscape_sub]
        asset['url-4K-SDR-240FPS'] = "file:///Library/Application%20Support/com.apple.idleassetsd/Customer/4KSDR240FPS/" + UUID + ".mov"
        print(f"Updated entry with category={landscape_cat}, subcategory={landscape_sub}")
        print(json.dumps(asset, indent=2))
        break

with open(ENTRIES, 'w') as f:
    json.dump(data, f, indent=2)

print("Saved!")
