from __future__ import annotations

import argparse
import os
from dataclasses import dataclass

import numpy as np
from PIL import Image


METAL_THRESHOLD = 230
DIELECTRIC_MAX = 229


@dataclass
class PixelReport:
    x: int
    y: int
    r_raw: int
    g_raw: int
    a_raw: int
    smoothness: float
    roughness: float
    is_metal: bool
    dielectric_f0: float | None
    emission: float


def load_rgba_image(path: str) -> np.ndarray:
    img = Image.open(path).convert("RGBA")
    return np.array(img, dtype=np.uint8)


def compute_maps(rgba: np.ndarray) -> dict[str, np.ndarray]:
    r = rgba[:, :, 0].astype(np.float32) / 255.0
    g_raw = rgba[:, :, 1].astype(np.uint8)
    a = rgba[:, :, 3].astype(np.float32) / 255.0

    smoothness = r
    roughness = (1.0 - smoothness) ** 2

    metal_mask = g_raw >= METAL_THRESHOLD
    dielectric_mask = ~metal_mask

    # Normalized dielectric F0 in [0, 1], only meaningful for non-metals
    dielectric_f0 = np.zeros_like(r, dtype=np.float32)
    dielectric_f0[dielectric_mask] = (
        g_raw[dielectric_mask].astype(np.float32) / DIELECTRIC_MAX
    )

    emission = a

    return {
        "smoothness": smoothness,
        "roughness": roughness,
        "metal_mask": metal_mask,
        "dielectric_mask": dielectric_mask,
        "dielectric_f0": dielectric_f0,
        "emission": emission,
        "g_raw": g_raw,
    }


def summarize_maps(maps: dict[str, np.ndarray]) -> None:
    roughness = maps["roughness"]
    dielectric_f0 = maps["dielectric_f0"]
    metal_mask = maps["metal_mask"]
    dielectric_mask = maps["dielectric_mask"]
    emission = maps["emission"]

    total_pixels = roughness.size
    metal_pixels = int(np.count_nonzero(metal_mask))
    dielectric_pixels = int(np.count_nonzero(dielectric_mask))

    print("\n=== Summary ===")
    print(f"Total pixels:           {total_pixels}")
    print(f"Metal pixels:           {metal_pixels} ({metal_pixels / total_pixels:.2%})")
    print(
        f"Dielectric pixels:      {dielectric_pixels} ({dielectric_pixels / total_pixels:.2%})"
    )

    print("\nRoughness:")
    print(f"  min:                  {roughness.min():.4f}")
    print(f"  max:                  {roughness.max():.4f}")
    print(f"  mean:                 {roughness.mean():.4f}")

    if dielectric_pixels > 0:
        f0_vals = dielectric_f0[dielectric_mask]
        print("\nDielectric F0:")
        print(f"  min:                  {f0_vals.min():.4f}")
        print(f"  max:                  {f0_vals.max():.4f}")
        print(f"  mean:                 {f0_vals.mean():.4f}")
    else:
        print("\nDielectric F0:          none (all metallic)")

    print("\nEmission:")
    print(f"  min:                  {emission.min():.4f}")
    print(f"  max:                  {emission.max():.4f}")
    print(f"  mean:                 {emission.mean():.4f}")


def inspect_pixel(rgba: np.ndarray, x: int, y: int) -> PixelReport:
    height, width, _ = rgba.shape
    if not (0 <= x < width and 0 <= y < height):
        raise ValueError(f"Pixel ({x}, {y}) is out of bounds for image {width}x{height}")

    r_raw = int(rgba[y, x, 0])
    g_raw = int(rgba[y, x, 1])
    a_raw = int(rgba[y, x, 3])

    smoothness = r_raw / 255.0
    roughness = (1.0 - smoothness) ** 2

    is_metal = g_raw >= METAL_THRESHOLD
    dielectric_f0 = None if is_metal else (g_raw / DIELECTRIC_MAX)
    emission = a_raw / 255.0

    return PixelReport(
        x=x,
        y=y,
        r_raw=r_raw,
        g_raw=g_raw,
        a_raw=a_raw,
        smoothness=smoothness,
        roughness=roughness,
        is_metal=is_metal,
        dielectric_f0=dielectric_f0,
        emission=emission,
    )


def save_debug_images(path: str, maps: dict[str, np.ndarray]) -> None:
    base, _ = os.path.splitext(path)

    def save_gray(array_01: np.ndarray, out_path: str) -> None:
        img = np.clip(array_01 * 255.0, 0, 255).astype(np.uint8)
        Image.fromarray(img, mode="L").save(out_path)

    save_gray(maps["roughness"], f"{base}_debug_roughness.png")
    save_gray(maps["dielectric_f0"], f"{base}_debug_f0.png")
    save_gray(maps["metal_mask"].astype(np.float32), f"{base}_debug_metalmask.png")
    save_gray(maps["emission"], f"{base}_debug_emission.png")

    print("\nSaved debug images:")
    print(f"  {base}_debug_roughness.png")
    print(f"  {base}_debug_f0.png")
    print(f"  {base}_debug_metalmask.png")
    print(f"  {base}_debug_emission.png")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", help="Path to a LabPBR specular texture PNG (*_s.png)")
    parser.add_argument("--x", type=int, help="Pixel x coordinate to inspect")
    parser.add_argument("--y", type=int, help="Pixel y coordinate to inspect")
    parser.add_argument(
        "--save-debug",
        action="store_true",
        help="Save grayscale debug maps for roughness/F0/metal/emission",
    )
    args = parser.parse_args()

    rgba = load_rgba_image(args.image)
    maps = compute_maps(rgba)

    print(f"Loaded: {args.image}")
    print(f"Image size: {rgba.shape[1]}x{rgba.shape[0]}")

    summarize_maps(maps)

    if args.x is not None or args.y is not None:
        if args.x is None or args.y is None:
            raise ValueError("Provide both --x and --y to inspect a pixel.")

        report = inspect_pixel(rgba, args.x, args.y)
        print("\n=== Pixel Inspection ===")
        print(f"Pixel:                 ({report.x}, {report.y})")
        print(f"R raw:                 {report.r_raw}")
        print(f"G raw:                 {report.g_raw}")
        print(f"A raw:                 {report.a_raw}")
        print(f"Smoothness:            {report.smoothness:.4f}")
        print(f"Roughness:             {report.roughness:.4f}")
        print(f"Metallic:              {report.is_metal}")
        if report.is_metal:
            print("Dielectric F0:         N/A (metallic pixel)")
        else:
            print(f"Dielectric F0:         {report.dielectric_f0:.4f}")
        print(f"Emission:              {report.emission:.4f}")

    if args.save_debug:
        save_debug_images(args.image, maps)


if __name__ == "__main__":
    main()