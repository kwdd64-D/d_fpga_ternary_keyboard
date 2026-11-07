#!/usr/bin/env python3
"""
build_glyphs.py — pack glyph art into the 2-bit ROM file read by glyph_rom.v

Output (glyphs2.hex): one hex digit (0-3) per line, one line per pixel.
Glyph `code` occupies lines code*1024 .. code*1024+1023, row-major, 32x32.
So the hardware address is {code[9:0], y[4:0], x[4:0]}.

Pixel value = ink level: 0 none, 1 light, 2 medium, 3 full ink.

Sources (combine freely; later sources override earlier ones for a code):
  --from-hex FILE            old 8-bit digits.hex (glyph index = code)
  --png-dir DIR              files named <code>.png, e.g. 0.png, 17.png, 725.png
  --atlas FILE:BASE:COLS     a sheet image made of 32x32 cells, read left to
                             right, top to bottom; cell i becomes code BASE+i.
                             COLS = number of cells per row.

PNG rule: dark ink on a light background by default. If the image has real
transparency (alpha), alpha is used as the ink instead. Use --invert for
light-on-dark art. Images must be 32x32 (or pass --resize).

Examples:
  python build_glyphs.py --from-hex digits.hex --count 32 -o glyphs2.hex
  python build_glyphs.py --atlas sheet_lower.png:100:27 --count 726 -o glyphs2.hex
  python build_glyphs.py --from-hex digits.hex --show 3 --count 32 -o glyphs2.hex
"""
import argparse
import os
import re
import sys

import numpy as np
from PIL import Image

PX = 32                      # glyph is PX x PX
WORDS = PX * PX              # 1024 pixels per glyph
MAX_CODE = 1023              # the hardware code field is 10 bits


def quantize(cov):
    """8-bit coverage -> 2-bit level, keeping the same ink footprint as the
    hardware's old rule (coverage > 16 counts as ink)."""
    cov = np.asarray(cov, dtype=np.int32)
    q = np.clip(np.rint(cov / 85.0), 0, 3).astype(np.int32)
    q = np.where(cov > 16, np.maximum(q, 1), 0)
    return q.astype(np.uint8)


def read_old_hex(path):
    """Read an old 8-bit digits.hex (readmemh format) -> {code: 32x32 coverage}."""
    vals = []
    with open(path, "r") as f:
        for line in f:
            line = line.split("//")[0].strip()
            if not line or line.startswith("@"):
                continue
            for tok in line.split():
                vals.append(int(tok, 16))
    if len(vals) % WORDS:
        print(f"warning: {path} has {len(vals)} values, not a multiple of {WORDS}; "
              f"ignoring the last {len(vals) % WORDS}", file=sys.stderr)
    n = len(vals) // WORDS
    arr = np.array(vals[: n * WORDS], dtype=np.uint8).reshape(n, PX, PX)
    return {i: arr[i] for i in range(n)}


def image_to_coverage(img, invert, resize):
    if img.size != (PX, PX):
        if not resize:
            raise SystemExit(f"image is {img.size}, expected {PX}x{PX} (use --resize)")
        img = img.resize((PX, PX), Image.LANCZOS)
    has_alpha = img.mode in ("RGBA", "LA") or "transparency" in img.info
    if has_alpha:
        rgba = img.convert("RGBA")
        alpha = np.array(rgba.getchannel("A"), dtype=np.uint8)
        if alpha.min() < 255:
            cov = alpha
            return (255 - cov) if invert else cov
    lum = np.array(img.convert("L"), dtype=np.uint8)
    cov = lum if invert else (255 - lum)
    return cov.astype(np.uint8)


def read_png_dir(path, invert, resize):
    out = {}
    for name in sorted(os.listdir(path)):
        m = re.fullmatch(r"(\d+)\.png", name, re.IGNORECASE)
        if not m:
            continue
        code = int(m.group(1))
        out[code] = image_to_coverage(Image.open(os.path.join(path, name)), invert, resize)
    if not out:
        raise SystemExit(f"no <code>.png files found in {path}")
    return out


def read_atlas(spec, invert):
    parts = spec.rsplit(":", 2)
    if len(parts) != 3:
        raise SystemExit("--atlas needs FILE:BASE:COLS")
    path, base, cols = parts[0], int(parts[1]), int(parts[2])
    img = Image.open(path)
    w, h = img.size
    if w % PX or h % PX:
        raise SystemExit(f"{path} is {w}x{h}; atlas size must be a multiple of {PX}")
    if w // PX < cols:
        raise SystemExit(f"{path} is only {w // PX} cells wide but COLS={cols}")
    rows = h // PX
    out = {}
    i = 0
    for r in range(rows):
        for c in range(cols):
            cell = img.crop((c * PX, r * PX, (c + 1) * PX, (r + 1) * PX))
            cov = image_to_coverage(cell, invert, False)
            if cov.max() > 16:               # skip completely empty cells
                out[base + i] = cov
            i += 1
    return out


def show(code, levels):
    chars = " .+#"
    print(f"--- code {code} ---")
    for y in range(PX):
        print("".join(chars[v] * 2 for v in levels[y]))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--from-hex", action="append", default=[], metavar="FILE")
    ap.add_argument("--png-dir", action="append", default=[], metavar="DIR")
    ap.add_argument("--atlas", action="append", default=[], metavar="FILE:BASE:COLS")
    ap.add_argument("--count", type=int, default=32,
                    help="number of glyph slots in the ROM (must match GLYPHS in glyph_rom.v)")
    ap.add_argument("--invert", action="store_true", help="light ink on dark background")
    ap.add_argument("--resize", action="store_true", help="resize PNGs that are not 32x32")
    ap.add_argument("--show", type=int, action="append", default=[], metavar="CODE",
                    help="print an ASCII preview of a glyph")
    ap.add_argument("-o", "--output", default="glyphs2.hex")
    args = ap.parse_args()

    if not (args.from_hex or args.png_dir or args.atlas):
        ap.error("give at least one source")
    if not 1 <= args.count <= MAX_CODE + 1:
        ap.error(f"--count must be 1..{MAX_CODE + 1}")

    glyphs = {}

    def merge(src, label):
        for code, cov in src.items():
            if code in glyphs:
                print(f"note: code {code} from {label} replaces an earlier glyph", file=sys.stderr)
            glyphs[code] = cov

    for p in args.from_hex:
        merge(read_old_hex(p), p)
    for p in args.png_dir:
        merge(read_png_dir(p, args.invert, args.resize), p)
    for spec in args.atlas:
        merge(read_atlas(spec, args.invert), spec)

    too_big = [c for c in glyphs if c >= args.count]
    if too_big:
        raise SystemExit(f"codes {sorted(too_big)[:8]}... are >= --count {args.count}; raise --count")

    rom = np.zeros((args.count, PX, PX), dtype=np.uint8)
    for code, cov in glyphs.items():
        rom[code] = quantize(cov)

    with open(args.output, "w", newline="\n") as f:
        f.write("\n".join(f"{v:X}" for v in rom.reshape(-1)))
        f.write("\n")

    for c in args.show:
        if c < args.count:
            show(c, rom[c])

    used = sorted(glyphs)
    print(f"wrote {args.output}: {args.count} slots x {WORDS} words, "
          f"{len(used)} glyphs filled ({args.count * WORDS * 2 // 8 // 1024} KB at 2 bits/pixel)")
    print(f"codes filled: {used[0]}..{used[-1]}" if used else "no glyphs")


if __name__ == "__main__":
    main()
