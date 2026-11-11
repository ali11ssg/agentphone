#!/usr/bin/env python3
"""Generates the AgentPhone launcher icon.

The fork must not carry the upstream app's icon or branding, so the icon is
drawn from scratch here: a rounded square with a vertical gradient and a white
terminal prompt. No third-party artwork, no PIL: the PNG is written by hand
with zlib, so the script runs anywhere Python 3 does.

    python3 tool/branding/make_icon.py [output-dir]

Writes ic_launcher.png for every density plus the adaptive-icon foreground and
a plain background colour for the adaptive icon XML.
"""
from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path

DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

TOP = (14, 20, 38)       # deep navy
BOTTOM = (18, 92, 104)   # teal
GLYPH = (240, 246, 248)  # near white


def write_png(path: Path, pixels: list[list[tuple[int, int, int, int]]]) -> None:
    height = len(pixels)
    width = len(pixels[0])
    raw = bytearray()
    for row in pixels:
        raw.append(0)  # filter type 0
        for r, g, b, a in row:
            raw += bytes((r, g, b, a))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))  # type: ignore[return-value]


def distance_to_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    dx, dy = bx - ax, by - ay
    length_squared = dx * dx + dy * dy
    if length_squared == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length_squared))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def draw(size: int, glyph_scale: float, inset: float) -> list[list[tuple[int, int, int, int]]]:
    """Rounded square with a gradient and a white '>' prompt plus a cursor bar."""
    radius = size * 0.22
    inner = size * inset
    span = size - 2 * inner
    stroke = max(1.0, span * 0.085)
    cursor_h = max(1.0, span * 0.075)

    # Glyph geometry inside the rounded square.
    gx = inner + span * 0.20
    gy = inner + span * 0.26
    g_len = span * 0.26
    g_dy = span * 0.20
    bar_x = gx + span * 0.10
    bar_y = inner + span * 0.62

    pixels: list[list[tuple[int, int, int, int]]] = []
    for y in range(size):
        row: list[tuple[int, int, int, int]] = []
        for x in range(size):
            # Rounded-rectangle coverage.
            cx = min(max(x, radius), size - radius)
            cy = min(max(y, radius), size - radius)
            inside = math.hypot(x - cx, y - cy) <= radius

            if not inside:
                row.append((0, 0, 0, 0))
                continue

            t = y / max(1, size - 1)
            r, g, b = mix(TOP, BOTTOM, t)

            # Glyph: two strokes forming '>' and a horizontal cursor bar.
            d1 = distance_to_segment(x, y, gx, gy, gx + g_len, gy + g_dy)
            d2 = distance_to_segment(x, y, gx, gy + g_dy, gx + g_len, gy)
            d3 = (
                abs(x - bar_x) - span * 0.10
            )
            in_bar = bar_y - cursor_h / 2 <= y <= bar_y + cursor_h / 2 and 0 <= d3 <= 0
            if min(d1, d2) <= stroke / 2 or in_bar:
                r, g, b = GLYPH

            row.append((r, g, b, 255))
        pixels.append(row)
    return pixels


def main() -> int:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "android/app/src/main/res")
    for density, size in DENSITIES.items():
        write_png(out / f"mipmap-{density}" / "ic_launcher.png", draw(size, 1.0, 0.0))
        write_png(
            out / f"mipmap-{density}" / "ic_launcher_foreground.png",
            draw(int(size * 1.5), 1.0, 0.22),
        )
        print(f"mipmap-{density}/ic_launcher.png ({size}px)")
    print("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
