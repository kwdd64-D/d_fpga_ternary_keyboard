// diamond 3.7 accepts this PLL
// diamond 3.8-3.9 is untested
// diamond 3.10 or higher is likely to abort with error about unable to use feedback signal
// cause of this could be from wrong CPHASE/FPHASE parameters
//
// *** DO NOT change CLKOP_DIV/CLKOS_DIV/CLKFB_DIV/CLKI_DIV without reading
// *** docs/TIMING_NOTES.md first. clkout0 (shift clock) MUST stay at
// *** exactly 5x clkout1 (pixel clock) -- that ratio is fixed by the
// *** ODDRX1F-based serializer in top.v, not a free parameter. Changing
// *** resolution means recomputing BOTH this PLL's dividers AND top.v's
// *** timing constants together -- see the notes for a table of safe
// *** resolution/frequency targets.
//
// Current target: 800x600 @ 60 Hz (VESA)
//   pixel clock  =  40 MHz
//   shift clock  = 200 MHz (5x pixel)
// Generated with: ecppll -i 25 --clkout0 200 --clkout1 40
//   VCO = 25 MHz / CLKI_DIV(1) * CLKFB_DIV(8) * CLKOP_DIV(3) = 600 MHz
//   (ECP5 VCO range is 400-800 MHz, so 600 is comfortably mid-range)
//   clkout0 = VCO / CLKOP_DIV(3)  = 200 MHz
//   clkout1 = VCO / CLKOS_DIV(15) =  40 MHz
//
// (Previous 1024x768 values, for reference: CLKFB_DIV 13, CLKOP_DIV 2,
//  CLKOS_DIV 10 -> 325 MHz / 65 MHz, VCO 650 MHz.)
module pll
(
    input clkin, // 25 MHz, 0 deg
    output clkout0, // 200 MHz, 0 deg
    output clkout1, // 40 MHz, 0 deg
    output locked
);
(* FREQUENCY_PIN_CLKI="25" *)
(* FREQUENCY_PIN_CLKOP="200" *)
(* FREQUENCY_PIN_CLKOS="40" *)
(* ICP_CURRENT="12" *) (* LPF_RESISTOR="8" *) (* MFG_ENABLE_FILTEROPAMP="1" *) (* MFG_GMCREF_SEL="2" *)
EHXPLLL #(
        .PLLRST_ENA("DISABLED"),
        .INTFB_WAKE("DISABLED"),
        .STDBY_ENABLE("DISABLED"),
        .DPHASE_SOURCE("DISABLED"),
        .OUTDIVIDER_MUXA("DIVA"),
        .OUTDIVIDER_MUXB("DIVB"),
        .OUTDIVIDER_MUXC("DIVC"),
        .OUTDIVIDER_MUXD("DIVD"),
        .CLKI_DIV(1),
        .CLKOP_ENABLE("ENABLED"),
        .CLKOP_DIV(3),
        .CLKOP_CPHASE(1),
        .CLKOP_FPHASE(0),
        .CLKOS_ENABLE("ENABLED"),
        .CLKOS_DIV(15),
        .CLKOS_CPHASE(1),
        .CLKOS_FPHASE(0),
        .FEEDBK_PATH("CLKOP"),
        .CLKFB_DIV(8)
    ) pll_i (
        .RST(1'b0),
        .STDBY(1'b0),
        .CLKI(clkin),
        .CLKOP(clkout0),
        .CLKOS(clkout1),
        .CLKFB(clkout0),
        .CLKINTFB(),
        .PHASESEL0(1'b0),
        .PHASESEL1(1'b0),
        .PHASEDIR(1'b1),
        .PHASESTEP(1'b1),
        .PHASELOADREG(1'b1),
        .PLLWAKESYNC(1'b0),
        .ENCLKOP(1'b0),
        .LOCK(locked)
	);
endmodule