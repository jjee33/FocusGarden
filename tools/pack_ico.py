"""Assembles packaging/windows/app_icon.ico from the rasters Godot rendered.

    python tools/pack_ico.py

Run tools/render_icons.gd first; it writes the pixels this reads. Godot can
rasterise the SVG but cannot write an .ico container, and the repo has no image
library to lean on, so the container is built here from the spec. It is a
directory header, one 16-byte entry per size, and the image data — small enough
to be worth writing directly rather than adding a dependency.

Every size is stored as an uncompressed DIB, including 256. The usual modern
choice is a PNG entry at the large sizes, which is smaller and which Explorer
reads happily -- but GDI+ does not, and System.Drawing throws outright on one.
An installer icon is worth more as universally readable than as 40 KB smaller.
"""

import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICONS = ROOT / "packaging" / "windows" / "icons"
OUTPUT = ROOT / "packaging" / "windows" / "app_icon.ico"

SIZES = [16, 32, 48, 64, 128, 256]


def dib_entry(size: int, rgba: bytes) -> bytes:
    """A 32-bit bottom-up DIB plus the AND mask the format still requires."""
    expected = size * size * 4
    if len(rgba) != expected:
        raise SystemExit(
            f"icon_{size}.rgba is {len(rgba)} bytes, expected {expected}. "
            "Re-run tools/render_icons.gd."
        )

    # Godot hands us top-down RGBA; a DIB is bottom-up BGRA.
    pixels = bytearray()
    for y in range(size - 1, -1, -1):
        row = rgba[y * size * 4:(y + 1) * size * 4]
        for x in range(0, len(row), 4):
            r, g, b, a = row[x:x + 4]
            pixels += bytes((b, g, r, a))

    # 1bpp mask, rows padded to 4 bytes. Left at zero: the alpha channel above is
    # what actually carries transparency on every Windows still in support, but
    # the mask must be present and correctly sized or the entry is rejected.
    mask_row = ((size + 31) // 32) * 4
    mask = bytes(mask_row * size)

    header = struct.pack(
        "<IiiHHIIiiII",
        40,            # biSize
        size,          # biWidth
        size * 2,      # biHeight — XOR and AND masks stacked
        1,             # biPlanes
        32,            # biBitCount
        0,             # biCompression (BI_RGB)
        len(pixels) + len(mask),
        0, 0, 0, 0,
    )
    return header + bytes(pixels) + mask


def main() -> None:
    images = []

    for size in SIZES:
        source = ICONS / f"icon_{size}.rgba"
        if not source.exists():
            raise SystemExit(f"Missing {source}. Run tools/render_icons.gd first.")
        images.append((size, dib_entry(size, source.read_bytes())))

    offset = 6 + 16 * len(images)
    directory = struct.pack("<HHH", 0, 1, len(images))
    for size, data in images:
        directory += struct.pack(
            "<BBBBHHII",
            size if size < 256 else 0,   # 0 means 256 in this field
            size if size < 256 else 0,
            0,   # colours in palette — 0 for true colour
            0,   # reserved
            1,   # planes
            32,  # bits per pixel
            len(data),
            offset,
        )
        offset += len(data)

    OUTPUT.write_bytes(directory + b"".join(data for _, data in images))
    sizes = ", ".join(str(size) for size, _ in images)
    print(f"Wrote {OUTPUT.relative_to(ROOT)} ({OUTPUT.stat().st_size:,} bytes; {sizes}px)")


if __name__ == "__main__":
    sys.exit(main())
