This needs to be updated soon.

# Balanced Ternary Rune Keyboard (ULX3S / ECP5)

An on-screen keyboard rendered over HDMI (DVI/TMDS) from an FPGA, navigated with
buttons, with a large preview of the selected rune. The long-term goal is to type
with a ternary-indexed set of "runes" instead of ordinary text, and stitch them
together into lines of rune text.

Everything is generated in hardware, pixel by pixel. There is no framebuffer: for
each pixel the design works out which key (if any) the beam is on, and which glyph
to show there.

## Files

| File | Purpose |
|------|---------|
| `top.v` | Video timing, button handling, keyboard layout, glyph instances, TMDS output |
| `rune_digits.v` | Glyph renderer: ROM lookup, scaling, bounds check, colour output |
| `digits.hex` | Glyph art, 8-bit coverage per pixel, 32x32 per digit, 10 digits |
| `pll`, `tmds_encoder` | Clock generation and TMDS encoding (from the original HDMI path, unchanged) |

## What works now

- **Video:** 800x600 @ 60 Hz over HDMI. Pixel clock from the PLL, 5x shift clock with DDR output.
- **Keyboard layout:** six rows, all keys drawn with gaps.
  - Row 1 (function row): 20 keys
  - Row 2 (number row): 21 keys (13 standard, wide Backspace, 3 nav, 4 numpad)
  - Row 3 (Tab row): 21 keys, with a tall numpad `+`
  - Row 4 (Caps row): 16 keys of its own, with wide Caps and Enter
  - Row 5 (Shift row): 17 keys, with Up arrow and tall numpad Enter
  - Row 6 (bottom row): 13 keys, with space bar, Left/Down/Right arrows and wide `0`
- **Digit selection:** LEFT and RIGHT move the orange highlight along keys 1 to 10 of row 2. The large preview shows the matching digit.
- **Glyphs on every key:** currently placeholder counting digits (`index % 10`) to prove every key exists.
- **Glyph size:** 16x16 on keys (downsampled from the 32x32 art), 256x256 in the preview (8x upscale).

## Controls

| Button | Action |
|--------|--------|
| LEFT / RIGHT | Move the highlight (clamped to 0 to 9) |
| UP / DOWN | Change `row_t` (stored, not yet used for drawing) |
| FIRE1 | Toggle Shift (green square, top left) |
| FIRE2 | Key press (writes `last_key`, not yet a real key code) |

## How the design is organised

**Geometry.** Each row has a function `xx_x(i)` giving key `i`'s X position and
`xx_w(i)` giving its width. An `always @(*)` loop tests the current pixel against
each key and outputs `in_row` and `row_idx`. Rows are stacked from `FUNC_Y`, and
every other row's Y is computed from the one above, so changing `FUNC_Y` moves the
whole keyboard down or up. Horizontal positions are absolute constants.

**Glyphs.** Each row has one `rune_digits` instance that follows the key the beam is
on (`glyph_ox = x(idx) + 2`). The final pixel is a priority mux: preview, then glyphs, then
the selected key, then key body, then the shift indicator, then the background.

**Colour mux.** `pix_r`, `pix_g`, `pix_b` must each use their own channel
(`*_rune_r/g/b`). An earlier typo used `nr_rune_r` in all three and tinted the
glyphs.

## Lessons from the bring-up

1. **The missing keys were overdrawn, not missing.** The 256x256 preview box (x 200 to 455, y 20 to 275) covered the function row at y = 240. Because the preview paints its background over its whole box, it hid keys 7 to 17. Moving the keyboard down fixed it.
2. **Old placeholder bars fill the gaps.** `in_row2`, `in_row3`, `in_space` and `in_backspace` were solid white rectangles. Any real key row at the same height looked merged, because the bar painted white over the gaps. They are now out of `in_any_key`. Their wires can be deleted.
3. **Registered ROM output needs a registered `in_view`.** `coverage` was registered but `in_view` was not, so glyphs landed 1 px right. The fix is to look up the next pixel and register `in_view` alongside the data.
4. **Glyph box vs key size.** A 32x32 glyph in a 20 px key shows only a corner. Downsampling to 16x16 fits it.
5. **Check the colour channels.** Copy-paste errors in the three muxes are easy to miss.

## Known limitations and cleanup list

- Placeholder labels (`% 10`) are not real runes yet.
- `last_key` is `{row_t[1], sel_col[1:0], 1'b0}`, which is not a meaningful key code.
- `row_t` and `sel_row` are not used for drawing. UP and DOWN do not move the highlight between rows yet.
- `col_lo`, `col_hi`, `tinc2`, `tdec2`, `dig_x`, `in_row2`, `in_row3`, `in_space`, `in_backspace` and `sel_row` are leftovers and can be deleted.
- Selection is a plain 0 to 9 binary counter. The balanced-ternary navigation helpers are present but unused.
- Glyphs are left-aligned (`+2`). Centering means `(key_w - 16) / 2` horizontally and `+2` vertically.
- The 2x downsample skips pixels with no filtering, so thin strokes can look rough. A 2x2 average would smooth them.
- Nothing has been checked in simulation. Everything so far was verified by looking at the screen.
- The bottom of the keyboard has limited margin. If more rows are added, lower `FUNC_Y`. The preview ends at y = 275.

## Design insights for the rune system

**Encoding.** A tryte is 6 trits, which gives 3^6 = 729 values (-364 to +364 balanced).
If you reserve 3 for control codes, you get 726.

**Sheet split.**
- 3+3: 27 sheets of 27 glyphs. Each sheet is small enough to swap independently. Good for the "unload what I don't need" goal.
- 2+4: 9 sheets of 81 glyphs. Fewer, bigger sheets, such as a whole alphabet per sheet.

For a balanced 3-trit half, add 13 to get an index from 0 to 26.

**Trits in binary hardware.** Each trit uses 2 bits and wastes one of four states. 3 trits fit
in 5 bits (27 values), but 6 bits are used if stored as three 2-bit trits. Convert to a linear
index with one small add. Keep the ternary logic in input and navigation, where it
adds meaning, and treat glyph addressing as a plain index.

**Memory is the real constraint.**
- 32x32 at 8 bits is 1 KB per glyph, so 729 glyphs is about 729 KB. That does not fit in ECP5 block RAM.
- 1 bit per pixel at 32x32 is 128 bytes per glyph (about 93 KB for 729).
- 1 bit per pixel at 16x16 is 32 bytes per glyph (about 23 KB for 729).
- 2 bits per pixel keeps some anti-aliasing at a quarter of the 8-bit cost.
- If keys only show 16x16 glyphs, store a separate 16x16 set for keys instead of downsampling at runtime. The big preview can keep the 32x32 art.

**Loading and unloading sheets.**
- Build-time: one hex file per sheet, include only what you need. Simple, free at runtime, needs re-synthesis to change.
- Run-time: keep active sheets in BRAM and copy others in from SPI flash or SDRAM with a small loader state machine. SDRAM is large enough to hold everything at 8 bits.
- Start with build-time sheets and one shared address scheme so the renderer never cares where a glyph came from.

**Stitching runes into text.** The larger preview needs a cell buffer, a small RAM
holding one rune code per cell. For each pixel, work out the cell
(shifts, if cells are powers of two), read its code, then look up the glyph. This is the same
work as a normal text renderer, so runes cost no more than letters.

- Pick a power-of-two cell size so the cell math is just bit slices.
- The cell buffer read adds a pipeline stage. Register `in_view` for each stage, as was needed for the glyph ROM.
- Input from outside (serial, files) needs a mapping table unless runes are just a font over standard codes.

**Making geometry easier to move.** Make all key positions relative to `KB_X`, `KB_Y`,
then add that origin when testing. Gate everything with an `in_kb` bounding box, because
unsigned subtraction wraps when the beam is left of or above the keyboard.

**Timing.** At 40 MHz pixel clock, each glyph instance does a combinational compare
chain plus a ROM read. If timing fails as more rows or runes are added, register the key-hit
signals (`in_row`, `row_idx`) one stage earlier and delay the colour mux to match.

## Suggested next steps

1. Delete the leftover wires and parameters listed above.
2. Make UP and DOWN move the highlight between rows (use `row_t` and the `*_idx` values).
3. Decide on the sheet split, then pack the first sheets with a script into hex files.
4. Replace the counting labels with a per-key lookup into real rune codes.
5. Add the cell buffer and grow the preview into a text area.
6. Make the keyboard position relative to `KB_X` and `KB_Y`.
