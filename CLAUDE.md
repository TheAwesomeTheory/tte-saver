# AustinSaver — Terminal Text Effects Screensaver

A macOS screensaver that renders animated ASCII art text effects over Apple's built-in aerial videos.

## How it works

1. `screensaver.txt` contains the ASCII art to animate
2. `prerender_effects.py` pre-renders all 37 TTE effects into binary `.tte` files
3. The Swift `.saver` bundle renders those frames in real-time with Core Text over background video
4. Effects cycle randomly with screen-blend compositing (black = transparent)

## Customizing the text

Edit `screensaver.txt` with any ASCII art. The recommended font is **Delta Corps Priest 1** via figlet:

```bash
# Install figlet if needed
brew install figlet

# Download the Delta Corps Priest 1 font
curl -sL "https://raw.githubusercontent.com/xero/figlet-fonts/master/Delta%20Corps%20Priest%201.flf" \
  -o /opt/homebrew/share/figlet/fonts/"Delta Corps Priest 1.flf"

# Generate text
figlet -f "Delta Corps Priest 1" "YOUR NAME" > screensaver.txt
```

Then hand-edit `screensaver.txt` to add flair — see `examples/` for inspiration.

You can also use https://patorjk.com/software/taag/ to browse 400+ fonts in your browser.

## Install

```bash
# One command — pre-renders, compiles, installs, activates
./install.sh

# With custom idle time (seconds)
./install.sh 30
```

Requires: Python 3, Swift (Xcode Command Line Tools), `terminaltexteffects` (`uv tool install terminaltexteffects`)

## Project structure

- `screensaver.txt` — Your ASCII art (edit this!)
- `prerender_effects.py` — Converts TTE effects to binary frame data
- `AustinSaver/AustinSaverView.swift` — The screensaver (Core Text renderer + AVPlayer background)
- `AustinSaver/Info.plist` — Bundle metadata
- `AustinSaver/test.swift` — Standalone test app (`./test_app`)
- `install.sh` — Build + install script
- `examples/` — Example ASCII art files

## Adding/removing effects

Effects are pre-rendered from `screensaver.txt`. To re-render after changing the text:

```bash
rm -rf effects_data
./install.sh
```

## Architecture

```
AVPlayerLayer (Apple aerial video, z=0)
    ↑ CIScreenBlendMode composite
CALayer (Core Text rendered frame, z=1)
    ↑ reads from pre-rendered .tte binary
effects_data/*.tte (pre-rendered by Python)
    ↑ generated from
screensaver.txt (your ASCII art)
```
