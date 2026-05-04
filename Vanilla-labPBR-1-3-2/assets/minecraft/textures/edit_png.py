#!/usr/bin/env python3
"""
_s texture editor for LabPBR shader packs.

Per-channel modes (mix freely across channels):
  --r/g/b/a VALUE           Proportional scale: max pixel maps to VALUE
  --set-r/g/b/a VALUE       Hard set every pixel to VALUE
  --scale-r/g/b/a FLOAT     Multiply every pixel by FLOAT
  --mirror-g-from-r MIN MAX  Remap R's pattern into G, scaled to [MIN, MAX]
  --mirror-b-from-r MIN MAX  Remap R's pattern into B, scaled to [MIN, MAX]
  --mirror-b-from-g MIN MAX  Remap G's pattern into B, scaled to [MIN, MAX]
  (any src/dst channel combo works: --mirror-{dst}-from-{src})

Examples:
  # Log: R has ring pattern (50-100), mirror into G (80-150) and B (0-50)
  python edit_s.py oak_log_s.png dest/oak_log_s.png --mirror-g-from-r 80 150 --mirror-b-from-r 0 50

  # Cobblestone: uniform hard set
  python edit_s.py cobblestone_s.png dest/cobblestone_s.png --set-r 0 --set-g 180 --set-b 200

  # Iron block: full metal
  python edit_s.py iron_block_s.png dest/iron_block_s.png --set-r 240 --set-g 230 --set-b 200

  # Boost existing red by 10%, mirror boosted result into blue range 0-80
  python edit_s.py oak_log_s.png dest/oak_log_s.png --scale-r 1.1 --mirror-b-from-r 0 80
"""

import argparse
import sys
from pathlib import Path
import numpy as np
from PIL import Image

CHANNELS = {"r": 0, "g": 1, "b": 2, "a": 3}


def parse_args():
    p = argparse.ArgumentParser(description="Edit _s LabPBR specular texture channels.")
    p.add_argument("input",  help="Input _s PNG path")
    p.add_argument("output", help="Output PNG path")

    for ch in ("r", "g", "b", "a"):
        p.add_argument(f"--{ch}",       type=float, default=None,
                       help=f"Scale {ch.upper()} so max pixel → VALUE, preserves variation")
        p.add_argument(f"--set-{ch}",   type=float, default=None,
                       help=f"Hard-set every {ch.upper()} pixel to VALUE (0-255)")
        p.add_argument(f"--scale-{ch}", type=float, default=None,
                       help=f"Multiply every {ch.upper()} pixel by FLOAT")

    # Mirror args: --mirror-{dst}-from-{src} MIN MAX
    for dst in ("r", "g", "b", "a"):
        for src in ("r", "g", "b", "a"):
            if src != dst:
                p.add_argument(f"--mirror-{dst}-from-{src}", nargs=2, type=float,
                               metavar=("MIN", "MAX"), default=None,
                               help=f"Remap {src.upper()} pattern into {dst.upper()} range [MIN, MAX]")

    return p.parse_args()


def process_channel(data: np.ndarray, target=None, hard_set=None, scale=None) -> np.ndarray:
    if hard_set is not None:
        return np.full_like(data, hard_set, dtype=np.float32)
    if scale is not None:
        return np.clip(data * scale, 0, 255)
    if target is not None:
        mx = data.max()
        if mx < 1e-6:
            return np.full_like(data, target, dtype=np.float32)
        return np.clip(data * (target / mx), 0, 255)
    return data


def mirror_channel(src_data: np.ndarray, out_min: float, out_max: float) -> np.ndarray:
    """
    Remap src_data's value range linearly into [out_min, out_max].

    The src pattern's relative structure is fully preserved:
      - darkest pixel in src  → out_min
      - brightest pixel in src → out_max
      - everything in between → linearly interpolated

    Example: src has values (50, 60, 100)
      mirror to [80, 150]:
        50  → 80
        60  → 100   (10/50 of the way → 14/70 of the way)
        100 → 150
    """
    src_min = src_data.min()
    src_max = src_data.max()
    src_range = src_max - src_min

    if src_range < 1e-6:
        # Flat channel — just fill with midpoint of target range
        return np.full_like(src_data, (out_min + out_max) / 2.0, dtype=np.float32)

    # Normalize src to [0, 1] then scale to [out_min, out_max]
    normalized = (src_data - src_min) / src_range
    remapped = normalized * (out_max - out_min) + out_min
    return np.clip(remapped, 0, 255)


def main():
    args = parse_args()

    src_path = Path(args.input)
    dst_path = Path(args.output)

    if not src_path.exists():
        print(f"Error: input file not found: {src_path}", file=sys.stderr)
        sys.exit(1)

    dst_path.parent.mkdir(parents=True, exist_ok=True)

    img = Image.open(src_path).convert("RGBA")
    arr = np.array(img, dtype=np.float32)  # H x W x 4

    # --- Step 1: apply direct channel ops (set / scale / proportional) ---
    for ch, idx in CHANNELS.items():
        target   = getattr(args, ch)
        hard_set = getattr(args, f"set_{ch}")
        scale    = getattr(args, f"scale_{ch}")

        if any(v is not None for v in (target, hard_set, scale)):
            arr[:, :, idx] = process_channel(arr[:, :, idx], target, hard_set, scale)
            mode = (f"hard_set={hard_set}" if hard_set is not None
                    else f"scale={scale}" if scale is not None
                    else f"proportional→{target}")
            print(f"  {ch.upper()} channel: {mode}")

    # --- Step 2: apply mirror ops (uses post-step-1 src channels) ---
    # This means --scale-r 1.1 --mirror-b-from-r 0 80 mirrors the BOOSTED R into B
    for dst in CHANNELS:
        for src in CHANNELS:
            if src == dst:
                continue
            mirror_arg = getattr(args, f"mirror_{dst}_from_{src}", None)
            if mirror_arg is not None:
                out_min, out_max = mirror_arg
                arr[:, :, CHANNELS[dst]] = mirror_channel(
                    arr[:, :, CHANNELS[src]], out_min, out_max
                )
                print(f"  {dst.upper()} channel: mirrored from {src.upper()} → [{out_min:.0f}, {out_max:.0f}]")

    result = Image.fromarray(arr.astype(np.uint8), mode="RGBA")
    result.save(dst_path)
    print(f"\nSaved → {dst_path}")


if __name__ == "__main__":
    main()