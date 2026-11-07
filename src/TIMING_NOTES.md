# Timing & Toolchain Notes — read before touching pll.v, top.v, or build.bat

This file exists because several settings in this project look like arbitrary
magic numbers but are actually load-bearing. If you are an AI assistant
helping with this repo: **please read this whole file before changing
anything in `src/pll.v`, `src/top.v`'s clocking/serializer section, or
`tools/build.bat`'s synthesis/PnR commands.** Several past "obvious cleanups"
here would silently break the design or reintroduce a toolchain crash. If
you're a human collaborator, same advice applies.

## 1. Why the shift clock is 5x the pixel clock

The video output is HDMI/DVI-style TMDS. Each color channel is encoded to a
10-bit TMDS symbol by `tmds_encoder.v`, and that 10-bit symbol has to be
shifted out serially, MSB-first-ish, once per pixel.

The serializer in `top.v` uses `ODDRX1F`, which is a basic DDR output
primitive: it shifts out **2 bits per shift-clock cycle** (one on each clock
edge). To get 10 bits out per pixel, you therefore need:

    shift_clock = 5 x pixel_clock

This ratio is fixed by the serializer architecture, not a tunable parameter.
Don't change `pll.v`'s CLKOP_DIV/CLKOS_DIV relationship without also
re-deriving this ratio — if you break it, the picture will not be corrupted
in an obviously-diagnosable way, it'll just show noise/rolling garbage.

## 2. Why 1024x768 is timing-marginal, and what to do about it

1024x768@60Hz needs a 65.0 MHz pixel clock (standard VESA timing, encoded in
`top.v`'s `h_cnt`/`v_cnt` constants). Via the 5x rule above, that means a
**325.1 MHz shift clock**. This sits right at the edge of what ECP5 `-6`
speed-grade fabric routing can reliably close timing at for this design —
measured runs land anywhere from ~300 MHz to ~350 MHz depending on
**placement**, not on the logic itself.

This is why `build.bat`'s place-and-route step tries multiple `--seed`
values (0/default, 1, 2, 3, 4) before giving up: nextpnr's placer is
randomized, and a different seed can be the difference between closing
timing and missing it by <1%, on the exact same source. **Do not remove the
seed sweep and replace it with a single nextpnr call** unless you've either
moved to a lower resolution (see table below, gives huge margin) or migrated
the serializer to ECP5's dedicated high-speed I/O gearing
(`ODDRX2F`/`ODDR71B` + `ECLK` clocking) instead of this fabric-routed one.

If you need to raise resolution/pixel clock further, standard VESA timings
and their resulting shift clocks (5x rule applied):

| Resolution      | Pixel clock | Shift clock | Notes                              |
|-----------------|-------------|-------------|-------------------------------------|
| 640x480@60      | 25.175 MHz  | ~125.9 MHz  | Very safe margin                    |
| 800x600@60      | 40.000 MHz  | 200 MHz     | Safe margin, recommended dev target |
| 1024x768@60     | 65.0 MHz    | 325.1 MHz   | Marginal on -6 grade (current)      |
| 1280x720@60     | 74.25 MHz   | 371.25 MHz  | Worse than 1024x768 -- don't, not with this serializer architecture |

Changing resolution requires updating **both**:
- `top.v`: the `h_cnt`/`v_cnt` limits, `hsync`/`vsync` timing windows, and
  active-area bounds, to match the new standard's front porch/sync/back
  porch numbers.
- `pll.v`: the `CLKOP_DIV`/`CLKOS_DIV`/`CLKFB_DIV`/`CLKI_DIV` parameters, to
  produce the new pixel clock and its 5x shift clock from the 25 MHz input.
  Don't hand-guess these -- regenerate them with a PLL calculator
  (`ecppll` from the OSS CAD Suite, or Project Trellis's PLL generator) for
  the exact target frequencies, then paste the resulting parameters in.

## 3. Why `synth_ecp5` is called with the `scratchpad -set abc9.xaiger 1` option

Recent yosys builds (including current OSS CAD Suite) default `synth_ecp5`
to the ABC9 synthesis flow, whose `write_xaiger2` writer is explicitly
marked experimental and has a known crash:

    ERROR: Assert `data_start == f->tellp()' failed in .../aiger2/aiger.cc:1078

This is a yosys toolchain bug, not a problem with this project's Verilog.
The `scratchpad -set abc9.xaiger 1` line is the documented upstream
workaround: it tells ABC9 to use the older, stable AIGER writer instead of
the broken experimental one. **Do not remove this scratchpad line** unless
you've confirmed (via `yosys -V`) that your yosys version no longer has this
bug.

## 4. Why the palette comes in via `` `include "../build/palette_pkg.vh" `` instead of `$readmemh`

The palette (`theme.ini` -> OKLCH -> RGB -> `build/palette_pkg.vh`) is a
**build-time constant** -- it only changes when you rerun the Python
generation step and resynthesize. It used to be loaded into a register at
elaboration time with `$readmemh`, which works, but forces yosys to
instantiate real registers + mux logic for a value that never changes at
runtime. That's wasted hardware sitting right next to the already-marginal
325 MHz shift-clock domain (see #2). The `` `include ``-based `localparam`
lets yosys fully constant-fold the palette away instead.

If you ever need the palette to change *at runtime* (e.g. selectable
palettes without a rebuild), that's a legitimate reason to reintroduce a
real register -- just know you're spending some of your timing margin to do
it, and budget accordingly (test on the lowest resolution you're using,
first).

## 5. General guidance for anyone (human or AI) extending this project

- Don't "simplify" `build.bat`'s nextpnr seed-sweep or the yosys scratchpad
  line without reading sections 2 and 3 above first.
- Don't add registers/logic near the `clk_shift`-domain serializer
  (`ring`, `sr_b`/`sr_g`/`sr_r`/`sr_c`, the `ODDRX1F` instances) without
  checking the resulting timing margin -- that domain has the least slack
  in the whole design.
- If timing starts failing again after a change, first check whether the
  change added logic in the `clk_shift` domain before assuming it's a
  placement-seed problem.
- New feature work (memory, more palette entries, additional test patterns)
  should target `clk_pixel`-domain logic where possible -- it has enormous
  timing margin by comparison (PASS margins of 65->75-90 MHz range have been
  observed against a 65 MHz requirement).
