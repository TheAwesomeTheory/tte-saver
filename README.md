# AustinSaver

A custom macOS screensaver that renders animated terminal text effects over Apple's built-in aerial videos. Powered by [TerminalTextEffects](https://chrisbuilds.github.io/terminaltexteffects/).

<video src="https://github.com/TheAwesomeTheory/tte-saver/raw/main/demo.mp4" autoplay loop muted playsinline width="100%"></video>

## Quick Start

1. Edit `screensaver.txt` with your custom ASCII art (or let Claude help you — see below)
2. Run `./install.sh`
3. Done — your screensaver is active

## Requirements

- macOS 14+ (Apple Silicon)
- Xcode Command Line Tools (`xcode-select --install`)
- Python 3 + [uv](https://docs.astral.sh/uv/) (`brew install uv`)
- [figlet](https://formulae.brew.sh/formula/figlet) for generating ASCII art (`brew install figlet`)

## Installation

```bash
# Install dependencies
brew install figlet uv

# Download the Delta Corps Priest 1 font
curl -sL "https://raw.githubusercontent.com/xero/figlet-fonts/master/Delta%20Corps%20Priest%201.flf" \
  -o "$(brew --prefix)/share/figlet/fonts/Delta Corps Priest 1.flf"

# Generate your text
figlet -f "Delta Corps Priest 1" "YOUR NAME" > screensaver.txt

# Install (pre-renders effects, compiles, activates)
./install.sh
```

Custom idle time: `./install.sh 30` (30 seconds)

## Using with Claude

Point [Claude Code](https://claude.ai/claude-code) at this repo and it will walk you through customizing the text, hand-editing the ASCII art, and installing. See `CLAUDE.md` for the full guide.

## How It Works

```
Background: AVPlayerLayer (Apple's built-in aerial videos)
Overlay:    CALayer (Core Text rendered text, CIScreenBlendMode)
Rendering:  CVDisplayLink → render CGImage on high-priority thread → CALayer.contents
Data:       Pre-rendered .tte binary files (character + position + RGB color per frame)
```

- 37 TTE effects cycle randomly
- 60fps native refresh rate via CVDisplayLink
- ~1-2ms per frame render time
- Lazy effect loading (first effect plays instantly, rest load in background)
- Text effects composited live over background — no pre-baked video files

## Development

```bash
# Quick recompile + reinstall after code changes
./deploy.sh

# Windowed test app
./test_app

# Re-render effects after changing screensaver.txt
rm -rf effects_data
./install.sh

# Check screensaver logs
/usr/bin/log show --last 2m --info --debug 2>&1 | grep "AustinSaver"
```

## Examples

See `examples/` for ASCII art inspiration. Browse fonts visually at [patorjk.com/software/taag](https://patorjk.com/software/taag/).

## License

MIT
