# AustinSaver — Custom Terminal Text Effects Screensaver for macOS

You are helping a user set up their custom screensaver. Follow these steps:

## Step 1: Ask the user what text they want

Ask them what name, word, or phrase they'd like displayed. Keep it short (1-2 words work best).

## Step 2: Generate the ASCII art

Use the **Delta Corps Priest 1** figlet font. Install if needed:

```bash
brew install figlet
curl -sL "https://raw.githubusercontent.com/xero/figlet-fonts/master/Delta%20Corps%20Priest%201.flf" \
  -o "$(brew --prefix)/share/figlet/fonts/Delta Corps Priest 1.flf"
```

Generate the text:

```bash
figlet -f "Delta Corps Priest 1" "THEIR NAME" > screensaver.txt
```

Then offer to hand-edit `screensaver.txt` with the user to add flair — wider letters, decorative elements, asymmetry. See `examples/` for inspiration (especially `examples/austin.txt` which has a custom hand-crafted "A" with inner blocks and flared base).

The user can also browse fonts visually at https://patorjk.com/software/taag/ and paste the result into `screensaver.txt`.

## Step 3: Install dependencies

```bash
# Python TTE library for pre-rendering effects
uv tool install terminaltexteffects
```

## Step 4: Install the screensaver

```bash
./install.sh
```

This will:
1. Pre-render all 37 TTE effects from `screensaver.txt` into binary `.tte` files
2. Compile the Swift `.saver` bundle
3. Install it to `~/Library/Screen Savers/`
4. Set it as the active screensaver (default: 2 min idle)

Custom idle time: `./install.sh 30` (30 seconds)

## Step 5: Test it

```bash
open -a ScreenSaverEngine
```

Or build the test app for windowed testing:
```bash
./deploy.sh
./test_app
```

## How it works

- `screensaver.txt` — The ASCII art text (user edits this)
- `prerender_effects.py` — Converts TTE effects to binary frame data (ANSI parsing, 160x40 canvas, centered)
- `AustinSaver/AustinSaverView.swift` — macOS `.saver` bundle: Core Text renderer + AVPlayer background + CIScreenBlendMode compositing
- `AustinSaver/Info.plist` — Bundle metadata
- `install.sh` — Full build + install pipeline
- `deploy.sh` — Quick recompile + reinstall (for development)
- `examples/` — Example ASCII art files for inspiration

## Architecture

```
Background: AVPlayerLayer (Apple's built-in aerial videos)
Overlay:    CALayer (Core Text rendered text, CIScreenBlendMode)
Rendering:  CVDisplayLink → render CGImage on high-priority thread → CALayer.contents
Data:       Pre-rendered .tte binary files (character + position + RGB color per frame)
```

- 60fps native refresh rate via CVDisplayLink
- ~1-2ms per frame render time
- Lazy effect loading (first effect plays instantly, rest load in background)
- All 37 TTE effects cycle randomly

## Troubleshooting

Check screensaver logs:
```bash
/usr/bin/log show --last 2m --info --debug 2>&1 | grep "AustinSaver"
```

Rebuild and redeploy after code changes:
```bash
./deploy.sh
```

Re-render effects after changing `screensaver.txt`:
```bash
rm -rf effects_data
./install.sh
```
