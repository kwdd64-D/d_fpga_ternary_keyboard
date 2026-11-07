#!/usr/bin/env python3
"""
build_keymap.py — turn keymap.csv into the two ROM files top.v reads.

  keymap.hex    1024 words (10-bit rune code, 3 hex digits)
                address = {bank[1:0], shift, key_id[6:0]}  = bank*256 + shift*128 + key_id
  keyflags.hex  128 words (0/1): 1 = Caps Lock flips this key's shift state (letters)

Banks:  0 = no bank lock   1 = Win Lock   2 = Ins Lock   3 = Game Lock
Shift:  0 = unshifted      1 = shifted (for letters, Shift XOR Caps)

keymap.csv columns:
  key,letter,b0,b0s,b1,b1s,b2,b2s,b3,b3s
Each b* cell is a rune code 0..725, or '-' / empty for "no legend".
`key` uses the browser key names from Keyboard.html (e.g. KeyQ, Digit1, ArrowUp).
Lines may be in any order, but all 108 keys must be present. '#' starts a comment.

Usage:
  python build_keymap.py --init-demo keymap.csv     write a starter file (placeholder digits)
  python build_keymap.py --init      keymap.csv     write an empty starter (no legends)
  python build_keymap.py keymap.csv                 build keymap.hex + keyflags.hex
  python build_keymap.py keymap.csv --glyphs 32     also warn about codes the ROM cannot draw
"""
import argparse
import csv
import re
import sys

MAX_RUNE = 725            # 0..725 usable; 726..728 stay reserved for the ternary mapping
BLANK = 0x3FF             # "no legend" sentinel the hardware recognises

# ---- physical keys in hardware order: (name, row, idx) ----------------------
ROWS = [
    # row 0: function row, 20 keys
    ["Escape"] + [f"F{n}" for n in range(1, 13)] +
    ["PrintScreen", "ScrollLock", "Pause", "CapsLock", "LockWin", "LockIns", "LockGame"],
    # row 1: number row, 21 keys
    ["Backquote"] + [f"Digit{d}" for d in "1234567890"] +
    ["Minus", "Equal", "Backspace", "Copy", "Paste", "NumLock",
     "NumpadEqual", "NumpadDivide", "NumpadMultiply", "NumpadSubtract"],
    # row 2: tab row, 21 keys
    ["Tab"] + [f"Key{c}" for c in "QWERTYUIOP"] +
    ["BracketLeft", "BracketRight", "Blank7", "SelectAll", "Delete", "Insert",
     "Numpad7", "Numpad8", "Numpad9", "NumpadAdd"],
    # row 3: caps row, 16 keys
    ["LockFn"] + [f"Key{c}" for c in "ASDFGHJKL"] +
    ["Semicolon", "Quote", "Enter", "Numpad4", "Numpad5", "Numpad6"],
    # row 4: shift row, 17 keys
    ["ShiftLeft"] + [f"Key{c}" for c in "ZXCVBNM"] +
    ["Comma", "Period", "Slash", "ShiftRight", "ArrowUp",
     "Numpad1", "Numpad2", "Numpad3", "NumpadEnter"],
    # row 5: bottom row, 13 keys
    ["ControlLeft", "MetaLeft", "AltLeft", "Space", "AltRight", "Fn", "Backslash",
     "ControlRight", "ArrowLeft", "ArrowDown", "ArrowRight", "Numpad0", "NumpadDecimal"],
]
ROW_COUNTS = [len(r) for r in ROWS]
BASES = [sum(ROW_COUNTS[:i]) for i in range(len(ROWS))]
KEYS = []                      # [(name, row, idx, key_id)]
for r, names in enumerate(ROWS):
    for i, n in enumerate(names):
        KEYS.append((n, r, i, BASES[r] + i))
assert len(KEYS) == 108 and ROW_COUNTS == [20, 21, 21, 16, 17, 13]
assert len({k[0] for k in KEYS}) == 108, "key names must be unique"

LETTERS = {f"Key{c}" for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ"}
COLS = ["b0", "b0s", "b1", "b1s", "b2", "b2s", "b3", "b3s"]


def write_template(path, demo):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        f.write("# key,letter,b0,b0s,b1,b1s,b2,b2s,b3,b3s  -- codes 0..725, '-' = no legend\n")
        w.writerow(["key", "letter"] + COLS)
        for name, row, idx, kid in KEYS:
            cells = []
            for bank in range(4):
                for s in range(2):
                    # placeholder: bank 0 unshifted shows idx % 10 (the old counting
                    # digits, so the number row reads 1..0); other states shift it
                    # so every lock/shift change is visible on screen.
                    cells.append((idx + 3 * bank + 5 * s) % 10 if demo else "-")
            w.writerow([name, 1 if name in LETTERS else 0] + cells)
    print(f"wrote {path} ({'placeholder digits' if demo else 'empty'}); edit it, then run build_keymap.py {path}")


def parse_cell(text, where):
    t = text.strip()
    if t in ("", "-"):
        return BLANK
    try:
        v = int(t, 0)
    except ValueError:
        raise SystemExit(f"{where}: '{text}' is not a number or '-'")
    if not 0 <= v <= MAX_RUNE:
        raise SystemExit(f"{where}: code {v} is outside 0..{MAX_RUNE}")
    return v


def build(path, glyphs):
    rows = {}
    with open(path, newline="") as f:
        lines = [ln for ln in f if ln.strip() and not ln.lstrip().startswith("#")]
    rd = csv.DictReader(lines)
    need = ["key", "letter"] + COLS
    if rd.fieldnames is None or [c.strip() for c in rd.fieldnames] != need:
        raise SystemExit(f"header must be: {','.join(need)}")
    for n, rec in enumerate(rd, start=2):
        name = rec["key"].strip()
        if name in rows:
            raise SystemExit(f"{path}: key '{name}' appears twice")
        rows[name] = rec
    known = {k[0] for k in KEYS}
    unknown = sorted(set(rows) - known)
    missing = sorted(known - set(rows))
    if unknown:
        raise SystemExit(f"unknown key names: {', '.join(unknown)}")
    if missing:
        raise SystemExit(f"missing keys: {', '.join(missing)}")

    km = [BLANK] * 1024
    flags = [0] * 128
    unreachable = []
    for name, row, idx, kid in KEYS:
        rec = rows[name]
        flags[kid] = 1 if rec["letter"].strip() in ("1", "true", "yes") else 0
        for bank in range(4):
            for s in range(2):
                col = COLS[bank * 2 + s]
                code = parse_cell(rec[col], f"{name}.{col}")
                km[bank * 256 + s * 128 + kid] = code
                if glyphs is not None and code != BLANK and code >= glyphs:
                    unreachable.append((name, col, code))

    with open("keymap.hex", "w", newline="\n") as f:
        f.write("\n".join(f"{v:03X}" for v in km) + "\n")
    with open("keyflags.hex", "w", newline="\n") as f:
        f.write("\n".join(str(v) for v in flags) + "\n")

    used = sum(1 for v in km if v != BLANK)
    print(f"wrote keymap.hex (1024 words, {used} with a legend) and keyflags.hex "
          f"({sum(flags)} letter keys)")
    if glyphs is not None and unreachable:
        print(f"warning: {len(unreachable)} entries use codes >= {glyphs} (the ROM size); "
              f"they will draw blank until glyph_rom GLYPHS is raised and art exists:")
        for name, col, code in unreachable[:10]:
            print(f"   {name}.{col} = {code}")
        if len(unreachable) > 10:
            print(f"   ... and {len(unreachable) - 10} more")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv")
    ap.add_argument("--init", action="store_true", help="write an empty starter csv")
    ap.add_argument("--init-demo", action="store_true", help="write a starter csv with placeholder digits")
    ap.add_argument("--glyphs", type=int, default=None, help="ROM glyph slots, to warn about unreachable codes")
    a = ap.parse_args()
    if a.init or a.init_demo:
        write_template(a.csv, demo=a.init_demo)
    else:
        build(a.csv, a.glyphs)


if __name__ == "__main__":
    main()
