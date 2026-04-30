#!/usr/bin/env python3
"""
GlassWall Icon Generator
Converts Icon.svg → all required macOS AppIcon PNG sizes using cairosvg or
Inkscape as a fallback. Run this script if Xcode can't process the SVG
(Xcode < 14 or CI environment without SVG support).

Usage:
    pip install cairosvg pillow
    python3 Scripts/generate_icons.py
"""

import subprocess
import sys
from pathlib import Path

ICON_SVG    = Path("GlassWall/Assets.xcassets/AppIcon.appiconset/Icon.svg")
ICON_SET    = Path("GlassWall/Assets.xcassets/AppIcon.appiconset")

# macOS required icon sizes: (points, scale)
SIZES = [
    (16,  1), (16,  2),
    (32,  1), (32,  2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]


def export_with_cairosvg(svg_path: Path, out_path: Path, pixels: int) -> bool:
    try:
        import cairosvg
        cairosvg.svg2png(url=str(svg_path), write_to=str(out_path),
                         output_width=pixels, output_height=pixels)
        return True
    except ImportError:
        return False


def export_with_inkscape(svg_path: Path, out_path: Path, pixels: int) -> bool:
    try:
        subprocess.run(
            ["inkscape", "--export-type=png",
             f"--export-filename={out_path}",
             f"--export-width={pixels}",
             f"--export-height={pixels}",
             str(svg_path)],
            check=True, capture_output=True
        )
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def export_with_rsvg(svg_path: Path, out_path: Path, pixels: int) -> bool:
    try:
        subprocess.run(
            ["rsvg-convert", "-w", str(pixels), "-h", str(pixels),
             "-o", str(out_path), str(svg_path)],
            check=True, capture_output=True
        )
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def main():
    if not ICON_SVG.exists():
        print(f"ERROR: {ICON_SVG} not found. Run from repository root.")
        sys.exit(1)

    contents_images = []
    generated = 0

    for points, scale in SIZES:
        pixels   = points * scale
        scale_str = f"@{scale}x" if scale > 1 else ""
        filename  = f"icon_{points}x{points}{scale_str}.png"
        out_path  = ICON_SET / filename

        ok = (export_with_cairosvg(ICON_SVG, out_path, pixels) or
              export_with_inkscape(ICON_SVG, out_path, pixels) or
              export_with_rsvg(ICON_SVG, out_path, pixels))

        if ok:
            print(f"  ✓ {filename} ({pixels}×{pixels}px)")
            generated += 1
        else:
            print(f"  ✗ {filename} — no SVG renderer found")

        contents_images.append({
            "filename": filename,
            "idiom": "mac",
            "scale": f"{scale}x",
            "size": f"{points}x{points}",
        })

    if generated == 0:
        print("\nNo icons generated. Install one of:")
        print("  pip install cairosvg")
        print("  brew install inkscape")
        print("  brew install librsvg")
        sys.exit(1)

    # Write Contents.json referencing individual PNGs
    import json
    contents = {
        "images": contents_images,
        "info": {"author": "xcode", "version": 1}
    }
    contents_path = ICON_SET / "Contents.json"
    with open(contents_path, "w") as f:
        json.dump(contents, f, indent=2)
    print(f"\nUpdated {contents_path}")
    print(f"Generated {generated}/{len(SIZES)} icon sizes.")


if __name__ == "__main__":
    main()
