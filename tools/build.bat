@echo off
REM *** Read ..\docs\TIMING_NOTES.md before changing the synth_ecp5 command
REM *** below (the "scratchpad -set abc9.xaiger 1" bit works around a real
REM *** yosys crash bug, see notes #3) or the nextpnr-ecp5 seed sweep (this
REM *** design is timing-marginal by design at 1024x768, see notes #2 --
REM *** the seed sweep is not decorative, it's load-bearing).
setlocal
echo BUILD STARTED
pause
REM --- define project name ---
set PROJ=video

REM --- find repo root (this script lives in tools/) ---
cd /d "%~dp0.."

REM --- generate palette from OKLCH data ---
REM echo Generating palette from OKLCH...
REM python tools\fpga_conversion_scripts\oklch_to_rgb.py || exit /b 1
REM python tools\fpga_conversion_scripts\gen_color_bin.py || exit /b 1

echo Skipping palette generation (using existing build\palette_pkg.vh)
if not exist build\palette_pkg.vh (
    echo ERROR: build\palette_pkg.vh is missing
    exit /b 1
)


REM --- move into src directory for synthesis ---
cd src

REM --- run synthesis (NO -q so errors show) ---
REM Recent yosys builds default synth_ecp5 to the ABC9 flow, whose
REM experimental write_xaiger2 writer can crash with an internal assert on
REM some designs (unrelated to your Verilog). The scratchpad setting below
REM is documented upstream as the "chicken bit" that forces ABC9 to use the
REM older, stable AIGER writer instead of the buggy experimental one.
REM yosys -q -p "scratchpad -set abc9.xaiger 1; read_verilog top.v tmds_encoder.v pll.v; synth_ecp5 -top top -json video.json" || exit /b 1

yosys -q -p "scratchpad -set abc9.xaiger 1; read_verilog top.v tmds_encoder.v pll.v rune_digits.v; synth_ecp5 -top top -json video.json" || exit /b 1

REM --- place & route ---
REM This design's 325.1 MHz shift-clock requirement is right on the edge of
REM what ECP5 -6 can close (recent runs landed at 320-324 MHz vs the 325.1
REM MHz target -- within ~0.2-1.5%). nextpnr's placer is randomized, so a
REM different --seed can be the difference between pass and fail on the
REM exact same source. Try a few seeds and keep the first one that closes;
REM only fall back to --timing-allow-fail if none of them do.
echo Running nextpnr-ecp5 (default seed)...
nextpnr-ecp5 --85k --package CABGA381 --speed 6 --json %PROJ%.json --lpf ulx3s.lpf --textcfg %PROJ%.config
if not errorlevel 1 goto pnr_ok

echo Default seed missed timing, trying seed 1...
nextpnr-ecp5 --85k --package CABGA381 --speed 6 --seed 1 --json %PROJ%.json --lpf ulx3s.lpf --textcfg %PROJ%.config
if not errorlevel 1 goto pnr_ok

echo Seed 1 missed timing, trying seed 2...
nextpnr-ecp5 --85k --package CABGA381 --speed 6 --seed 2 --json %PROJ%.json --lpf ulx3s.lpf --textcfg %PROJ%.config
if not errorlevel 1 goto pnr_ok

echo Seed 2 missed timing, trying seed 3...
nextpnr-ecp5 --85k --package CABGA381 --speed 6 --seed 3 --json %PROJ%.json --lpf ulx3s.lpf --textcfg %PROJ%.config
if not errorlevel 1 goto pnr_ok

echo Seed 3 missed timing, trying seed 4...
nextpnr-ecp5 --85k --package CABGA381 --speed 6 --seed 4 --json %PROJ%.json --lpf ulx3s.lpf --textcfg %PROJ%.config
if not errorlevel 1 goto pnr_ok

echo All seed attempts missed the 325.1 MHz target.
echo Falling back to --timing-allow-fail so you still get a bitstream to test with --
echo this is fine for visual bring-up, but don't treat it as production-ready
echo until a run actually closes timing without this flag.
nextpnr-ecp5 --85k --package CABGA381 --speed 6 --timing-allow-fail --json %PROJ%.json --lpf ulx3s.lpf --textcfg %PROJ%.config || exit /b 1

:pnr_ok

REM --- pack bitstream ---
ecppack %PROJ%.config %PROJ%.bit || exit /b 1

REM --- flash or load ---
if /i "%1"=="flash" (
    openFPGALoader -b ulx3s -f --unprotect-flash %PROJ%.bit
) else (
    openFPGALoader -b ulx3s %PROJ%.bit
)

echo BUILD COMPLETE
pause
