#!/usr/bin/env python3
"""Pre-render all TTE effects to compact binary .tte files."""

import struct
import os
import importlib
import sys
import time

# All 37 TTE effects
EFFECTS = [
    "beams", "binarypath", "blackhole", "bouncyballs", "bubbles", "burn",
    "colorshift", "crumble", "decrypt", "errorcorrect", "expand", "fireworks",
    "highlight", "laseretch", "matrix", "middleout", "orbittingvolley",
    "overflow", "pour", "print", "rain", "random_sequence", "rings",
    "scattered", "slice", "slide", "smoke", "spotlights", "spray", "swarm",
    "sweep", "synthgrid", "thunderstorm", "unstable", "vhstape", "waves", "wipe",
]

INPUT_FILE = "screensaver.txt"
OUTPUT_DIR = "effects_data"


def get_effect_class(effect_name):
    """Dynamically import and return the effect class."""
    module_name = f"terminaltexteffects.effects.effect_{effect_name}"
    module = importlib.import_module(module_name)
    # Find the effect class: it subclasses BaseEffect and isn't BaseEffect itself
    from terminaltexteffects.engine.base_effect import BaseEffect
    for attr_name in dir(module):
        attr = getattr(module, attr_name)
        if isinstance(attr, type) and issubclass(attr, BaseEffect) and attr is not BaseEffect:
            return attr
    raise AttributeError(f"No effect class found in {module_name}")


def parse_color(color_str):
    """Parse hex color string like 'ff3344' to (r, g, b) tuple."""
    if color_str is None:
        return (255, 255, 255)  # Default white
    color_str = str(color_str).strip("#")
    if len(color_str) != 6:
        return (255, 255, 255)
    return (
        int(color_str[0:2], 16),
        int(color_str[2:4], 16),
        int(color_str[4:6], 16),
    )


def parse_ansi_frame(frame_str, canvas_w, canvas_h):
    """Parse an ANSI frame string into a list of (col, row, symbol, (r,g,b))."""
    import re
    chars = []
    # Current cursor position and color state
    col = 1
    row = 1
    fg_color = (255, 255, 255)

    i = 0
    s = frame_str
    while i < len(s):
        c = s[i]

        if c == "\033" and i + 1 < len(s) and s[i + 1] == "[":
            # Parse ANSI escape sequence
            i += 2
            seq = ""
            while i < len(s) and s[i] not in "mHJKABCDfsu":
                seq += s[i]
                i += 1
            if i < len(s):
                cmd = s[i]
                i += 1

                if cmd == "m":  # SGR - color
                    parts = seq.split(";") if seq else ["0"]
                    j = 0
                    while j < len(parts):
                        code = int(parts[j]) if parts[j].isdigit() else 0
                        if code == 0:
                            fg_color = (255, 255, 255)
                        elif code == 38 and j + 1 < len(parts) and parts[j + 1] == "2":
                            # 24-bit color: 38;2;r;g;b
                            if j + 4 < len(parts):
                                r = int(parts[j + 2])
                                g = int(parts[j + 3])
                                b = int(parts[j + 4])
                                fg_color = (r, g, b)
                                j += 4
                        j += 1
                elif cmd == "H" or cmd == "f":  # Cursor position
                    parts = seq.split(";")
                    if len(parts) >= 2 and parts[0] and parts[1]:
                        row = int(parts[0])
                        col = int(parts[1])
                    elif len(parts) == 1 and parts[0]:
                        row = int(parts[0])
                        col = 1
                    else:
                        row = 1
                        col = 1
                elif cmd == "A":  # Cursor up
                    n = int(seq) if seq else 1
                    row = max(1, row - n)
                elif cmd == "B":  # Cursor down
                    n = int(seq) if seq else 1
                    row += n
                elif cmd == "C":  # Cursor forward
                    n = int(seq) if seq else 1
                    col += n
                elif cmd == "D":  # Cursor back
                    n = int(seq) if seq else 1
                    col = max(1, col - n)
                elif cmd == "J" or cmd == "K":  # Clear - ignore
                    pass
        elif c == "\n":
            row += 1
            col = 1
            i += 1
        elif c == "\r":
            col = 1
            i += 1
        else:
            # Visible character
            if c != " " and 0 < col <= canvas_w and 0 < row <= canvas_h:
                chars.append((col, row, c, fg_color))
            col += 1
            i += 1

    return chars


def prerender_effect(effect_name, text):
    """Pre-render a single effect and return (grid_w, grid_h, frames)."""
    effect_cls = get_effect_class(effect_name)
    effect = effect_cls(text)
    # Set a large canvas so effects have room to animate beyond the text
    canvas_w = 160
    canvas_h = 40
    effect.terminal_config.canvas_width = canvas_w
    effect.terminal_config.canvas_height = canvas_h
    effect.terminal_config.ignore_terminal_dimensions = True
    effect.terminal_config.anchor_canvas = "c"
    effect.terminal_config.anchor_text = "c"
    it = iter(effect)

    frames = []

    for frame_str in it:
        chars = parse_ansi_frame(frame_str, canvas_w, canvas_h)
        frames.append(chars)

    return canvas_w, canvas_h, frames


def write_tte_file(filepath, grid_w, grid_h, frames):
    """Write frames to binary .tte format."""
    with open(filepath, "wb") as f:
        # Header: magic + grid_w + grid_h + frame_count
        f.write(b"TTE1")
        f.write(struct.pack("<HHI", grid_w, grid_h, len(frames)))

        # Frames
        for frame_chars in frames:
            f.write(struct.pack("<H", len(frame_chars)))
            for col, row, sym, (r, g, b) in frame_chars:
                sym_bytes = sym.encode("utf-8")
                sym_len = len(sym_bytes)
                f.write(struct.pack("BB", col, row))
                f.write(struct.pack("B", sym_len))
                f.write(sym_bytes)
                f.write(struct.pack("BBB", r, g, b))


def main():
    with open(INPUT_FILE) as f:
        text = f.read()

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    total_frames = 0
    total_size = 0

    for i, effect_name in enumerate(EFFECTS):
        start = time.time()
        sys.stdout.write(f"[{i+1}/{len(EFFECTS)}] {effect_name}... ")
        sys.stdout.flush()

        try:
            grid_w, grid_h, frames = prerender_effect(effect_name, text)
            filepath = os.path.join(OUTPUT_DIR, f"{effect_name}.tte")
            write_tte_file(filepath, grid_w, grid_h, frames)

            size = os.path.getsize(filepath)
            elapsed = time.time() - start
            print(f"{len(frames)} frames, {size/1024:.0f}KB, {elapsed:.1f}s")

            total_frames += len(frames)
            total_size += size
        except Exception as e:
            print(f"FAILED: {e}")

    print(f"\nDone! {len(EFFECTS)} effects, {total_frames} total frames, {total_size/1024/1024:.1f}MB")


if __name__ == "__main__":
    main()
