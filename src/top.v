// top_keyboard.v — on-screen keyboard navigable by balanced ternary
// Buttons: LEFT/RIGHT/UP/DOWN navigate (ternary ±1)
//          FIRE1 = Shift toggle, FIRE2 = key press
// Highlighted key uses the active color; everything else is unchanged
// from the original HDMI path.

module top (
    input  wire       clk_25mhz,
    input  wire [6:0] btn,
    output wire [3:0] gpdi_dp
);
    wire clk_shift, clk_pixel, locked;
    pll pll_i (.clkin(clk_25mhz), .clkout0(clk_shift),
               .clkout1(clk_pixel), .locked(locked));

    // ---------- 800x600 @ 60 Hz (unchanged) ----------
    localparam H_ACTIVE = 800, H_FRONT = 40, H_SYNC = 128, H_BACK = 88;
    localparam V_ACTIVE = 600, V_FRONT = 1,  V_SYNC = 4,   V_BACK = 23;
    localparam H_TOTAL = 1056, V_TOTAL = 628;
    localparam H_SYNC_START = 840, H_SYNC_END = 968;
    localparam V_SYNC_START = 601, V_SYNC_END = 605;

    reg [10:0] h_cnt = 0, v_cnt = 0;
    always @(posedge clk_pixel) begin
        if (h_cnt == H_TOTAL-1) begin
            h_cnt <= 0;
            v_cnt <= (v_cnt == V_TOTAL-1) ? 0 : v_cnt + 1;
        end else h_cnt <= h_cnt + 1;
    end
    wire h_active = h_cnt < H_ACTIVE;
    wire v_active = v_cnt < V_ACTIVE;
    wire hsync = (h_cnt >= H_SYNC_START && h_cnt < H_SYNC_END);
    wire vsync = (v_cnt >= V_SYNC_START && v_cnt < V_SYNC_END);
    wire blank = ~(h_active && v_active);

    // ---------- trit encoding (same as original) ----------
    localparam [1:0] TRIT_ZERO = 2'b00;
    localparam [1:0] TRIT_POS  = 2'b01;
    localparam [1:0] TRIT_NEG  = 2'b10;

    function signed [2:0] trit_val;
        input [1:0] t;
        case (t)
            TRIT_NEG: trit_val = -1;
            TRIT_POS: trit_val =  1;
            default:  trit_val =  0;
        endcase
    endfunction

    // ---------- button sync + edge detect (unchanged domain) ----------
    reg [6:0] btn_sync0=0, btn_sync1=0, btn_prev=0;
    always @(posedge clk_pixel) begin
        btn_sync0 <= btn;
        btn_sync1 <= btn_sync0;
        btn_prev  <= btn_sync1;
    end
    wire [6:0] press = btn_sync1 & ~btn_prev;
    wire press_shift = press[1];   // FIRE1
    wire press_key   = press[2];   // FIRE2
    wire press_up    = press[3];
    wire press_down  = press[4];
    wire press_left  = press[5];
    wire press_right = press[6];

    // ---------- selection: 2 trits for col (−4..+4 → 0..8), 1 trit for row ----------
    reg [1:0] col_lo = TRIT_ZERO, col_hi = TRIT_ZERO;
    reg [1:0] row_t  = TRIT_ZERO;
    reg       shift_on = 0;
    reg [3:0] last_key = 0;   // simple feedback
	reg [3:0] sel_col_reg = 0;   // 0-9 for the ten digit keys

    // ternary increment / decrement helpers (2-digit balanced)
    function [3:0] tinc2;  // returns {hi,lo} after +1
        input [1:0] hi, lo;
        reg signed [3:0] v;
        begin
            v = trit_val(lo) + 3*trit_val(hi) + 1;
            if (v > 4) v = 4;          // clamp
            case (v)
                -4: tinc2 = {TRIT_NEG, TRIT_NEG};
                -3: tinc2 = {TRIT_NEG, TRIT_ZERO};
                -2: tinc2 = {TRIT_NEG, TRIT_POS};
                -1: tinc2 = {TRIT_ZERO, TRIT_NEG};
                 0: tinc2 = {TRIT_ZERO, TRIT_ZERO};
                 1: tinc2 = {TRIT_ZERO, TRIT_POS};
                 2: tinc2 = {TRIT_POS,  TRIT_NEG};
                 3: tinc2 = {TRIT_POS,  TRIT_ZERO};
                 4: tinc2 = {TRIT_POS,  TRIT_POS};
                default: tinc2 = {TRIT_ZERO, TRIT_ZERO};
            endcase
        end
    endfunction

    function [3:0] tdec2;
        input [1:0] hi, lo;
        reg signed [3:0] v;
        begin
            v = trit_val(lo) + 3*trit_val(hi) - 1;
            if (v < -4) v = -4;
            case (v)
                -4: tdec2 = {TRIT_NEG, TRIT_NEG};
                -3: tdec2 = {TRIT_NEG, TRIT_ZERO};
                -2: tdec2 = {TRIT_NEG, TRIT_POS};
                -1: tdec2 = {TRIT_ZERO, TRIT_NEG};
                 0: tdec2 = {TRIT_ZERO, TRIT_ZERO};
                 1: tdec2 = {TRIT_ZERO, TRIT_POS};
                 2: tdec2 = {TRIT_POS,  TRIT_NEG};
                 3: tdec2 = {TRIT_POS,  TRIT_ZERO};
                 4: tdec2 = {TRIT_POS,  TRIT_POS};
                default: tdec2 = {TRIT_ZERO, TRIT_ZERO};
            endcase
        end
    endfunction

    always @(posedge clk_pixel) begin
        if (press_right && sel_col_reg < 9)
            sel_col_reg <= sel_col_reg + 1;
        if (press_left && sel_col_reg > 0)
            sel_col_reg <= sel_col_reg - 1;

        if (press_up)    row_t <= (row_t == TRIT_POS)  ? TRIT_POS  :
                                  (row_t == TRIT_ZERO) ? TRIT_POS  : TRIT_ZERO;
        if (press_down)  row_t <= (row_t == TRIT_NEG)  ? TRIT_NEG  :
                                  (row_t == TRIT_ZERO) ? TRIT_NEG  : TRIT_ZERO;
        if (press_shift) shift_on <= ~shift_on;
        if (press_key)   last_key <= {row_t[1], sel_col_reg[1], sel_col_reg[0], 1'b0};
    end

    // map trits → 0-based indices for drawing
//    wire [3:0] sel_col = trit_val(col_lo) + 3*trit_val(col_hi) + 4; // 0..8
	wire [3:0] sel_col = sel_col_reg;   // now 0-9
    wire [1:0] sel_row = (row_t == TRIT_NEG) ? 2 : (row_t == TRIT_POS) ? 0 : 1;

    // ---------- full keyboard geometry ----------
    localparam KEY_H = 20;
    localparam GAP   = 3;
    localparam STD_W = 28;

    localparam FUNC_Y = 400;
    localparam NUM_Y  = FUNC_Y + KEY_H + GAP + 6;
    localparam ROW2_Y = NUM_Y + KEY_H + GAP + 4;
    localparam ROW3_Y = ROW2_Y + KEY_H + GAP;

    // Digit key X positions (1 2 3 4 5 6 7 8 9 0)
    wire [10:0] dig_x [0:9];
    assign dig_x[0] = 40;
    assign dig_x[1] = dig_x[0] + STD_W + GAP;
    assign dig_x[2] = dig_x[1] + STD_W + GAP;
    assign dig_x[3] = dig_x[2] + STD_W + GAP;
    assign dig_x[4] = dig_x[3] + STD_W + GAP;
    assign dig_x[5] = dig_x[4] + STD_W + GAP;
    assign dig_x[6] = dig_x[5] + STD_W + GAP;
    assign dig_x[7] = dig_x[6] + STD_W + GAP;
    assign dig_x[8] = dig_x[7] + STD_W + GAP;
    assign dig_x[9] = dig_x[8] + STD_W + GAP;

    // Wide-key constants
    localparam [10:0] BACKSPACE_X = 11'd381;
    localparam [10:0] BACKSPACE_W = 11'd56;
    localparam [10:0] SPACE_X     = 11'd160;
    localparam [10:0] SPACE_W     = 11'd168;

    // ---------- Function row: 20 explicit keys ----------
    localparam FUNC_W   = 22;
    localparam FUNC_GAP = 2;
    localparam ESC_X    = 10;
    localparam F1_X     = 40;
    localparam F2_X     = 64;
    localparam F3_X     = 88;
    localparam F4_X     = 112;
    localparam F5_X     = 136;
    localparam F6_X     = 160;
    localparam F7_X     = 184;
    localparam F8_X     = 208;
    localparam F9_X     = 232;
    localparam F10_X    = 256;
    localparam F11_X    = 280;
    localparam F12_X    = 304;
    localparam PRINT_X  = 336;
    localparam SCROLL_X = 360;
    localparam PAUSE_X  = 384;
    localparam CAPS_X   = 416;
    localparam WIN_X    = 440;
    localparam INS_X    = 464;
    localparam GAME_X   = 488;

    reg        in_func_key;
    reg [4:0]  func_idx;
    always @(*) begin
        in_func_key = 0;
        func_idx    = 0;
        if (h_cnt >= ESC_X    && h_cnt < ESC_X+FUNC_W    && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=0;  end
        if (h_cnt >= F1_X     && h_cnt < F1_X+FUNC_W     && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=1;  end
        if (h_cnt >= F2_X     && h_cnt < F2_X+FUNC_W     && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=2;  end
        if (h_cnt >= F3_X     && h_cnt < F3_X+FUNC_W     && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=3;  end
        if (h_cnt >= F4_X     && h_cnt < F4_X+FUNC_W     && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=4;  end
        if (h_cnt >= F5_X     && h_cnt < F5_X+FUNC_W     && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=5;  end
        if (h_cnt >= F6_X     && h_cnt < F6_X+FUNC_W     && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=6;  end
        if (h_cnt >= F7_X     && h_cnt < F7_X+FUNC_W     && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=7;  end
        if (h_cnt >= F8_X     && h_cnt < F8_X+FUNC_W     && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=8;  end
        if (h_cnt >= F9_X     && h_cnt < F9_X+FUNC_W     && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=9;  end
        if (h_cnt >= F10_X    && h_cnt < F10_X+FUNC_W    && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=10; end
        if (h_cnt >= F11_X    && h_cnt < F11_X+FUNC_W    && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=11; end
        if (h_cnt >= F12_X    && h_cnt < F12_X+FUNC_W    && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=12; end
        if (h_cnt >= PRINT_X  && h_cnt < PRINT_X+FUNC_W  && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=13; end
        if (h_cnt >= SCROLL_X && h_cnt < SCROLL_X+FUNC_W && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=14; end
        if (h_cnt >= PAUSE_X  && h_cnt < PAUSE_X+FUNC_W  && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=15; end
        if (h_cnt >= CAPS_X   && h_cnt < CAPS_X+FUNC_W   && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=16; end
        if (h_cnt >= WIN_X    && h_cnt < WIN_X+FUNC_W    && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=17; end
        if (h_cnt >= INS_X    && h_cnt < INS_X+FUNC_W    && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=18; end
        if (h_cnt >= GAME_X   && h_cnt < GAME_X+FUNC_W   && v_cnt >= FUNC_Y && v_cnt < FUNC_Y+KEY_H) begin in_func_key=1; func_idx=19; end
    end
    wire in_func_row = in_func_key;
	
	

    // Digit keys
    reg        in_digit_key;
    reg [3:0]  hit_digit;
    integer di;
    always @(*) begin
//        in_digit_key = 0;
//        hit_digit    = 0;
//        for (di = 0; di < 10; di = di + 1) begin
//            if (h_cnt >= dig_x[di] && h_cnt < dig_x[di] + STD_W &&
//                v_cnt >= NUM_Y && v_cnt < NUM_Y + KEY_H) begin
//                in_digit_key = 1;
//                hit_digit    = di[3:0];
//            end
//        end
    end
	
	
    // ---------- New row: explicit 13 std keys + wide BS + 3 nav + 4 numpad ----------
    localparam NEWROW_Y = FUNC_Y + KEY_H + GAP + 6;

    localparam NR0_X  = 16;
    localparam NR1_X  = 47;
    localparam NR2_X  = 78;
    localparam NR3_X  = 109;
    localparam NR4_X  = 140;
    localparam NR5_X  = 171;
    localparam NR6_X  = 202;
    localparam NR7_X  = 233;
    localparam NR8_X  = 264;
    localparam NR9_X  = 295;
    localparam NR10_X = 326;
    localparam NR11_X = 357;
    localparam NR12_X = 388;
    localparam NR_BS_X = 420;
    localparam NR_BS_W = 56;
    localparam NR_NAV_X = 484;
    localparam NR_NP_X  = 580;

    reg        in_newrow;
    reg [4:0]  newrow_idx;
    always @(*) begin
        in_newrow  = 0;
        newrow_idx = 0;
        if (h_cnt >= NR0_X  && h_cnt < NR0_X+STD_W  && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=0;  end
        if (h_cnt >= NR1_X  && h_cnt < NR1_X+STD_W  && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=1;  end
        if (h_cnt >= NR2_X  && h_cnt < NR2_X+STD_W  && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=2;  end
        if (h_cnt >= NR3_X  && h_cnt < NR3_X+STD_W  && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=3;  end
        if (h_cnt >= NR4_X  && h_cnt < NR4_X+STD_W  && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=4;  end
        if (h_cnt >= NR5_X  && h_cnt < NR5_X+STD_W  && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=5;  end
        if (h_cnt >= NR6_X  && h_cnt < NR6_X+STD_W  && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=6;  end
        if (h_cnt >= NR7_X  && h_cnt < NR7_X+STD_W  && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=7;  end
        if (h_cnt >= NR8_X  && h_cnt < NR8_X+STD_W  && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=8;  end
        if (h_cnt >= NR9_X  && h_cnt < NR9_X+STD_W  && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=9;  end
        if (h_cnt >= NR10_X && h_cnt < NR10_X+STD_W && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=10; end
        if (h_cnt >= NR11_X && h_cnt < NR11_X+STD_W && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=11; end
        if (h_cnt >= NR12_X && h_cnt < NR12_X+STD_W && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=12; end
        // wide Backspace
        if (h_cnt >= NR_BS_X && h_cnt < NR_BS_X+NR_BS_W && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=13; end
        // Insert, Home, Page Up
        if (h_cnt >= NR_NAV_X      && h_cnt < NR_NAV_X+STD_W      && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=14; end
        if (h_cnt >= NR_NAV_X+31   && h_cnt < NR_NAV_X+31+STD_W   && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=15; end
        if (h_cnt >= NR_NAV_X+62   && h_cnt < NR_NAV_X+62+STD_W   && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=16; end
        // 4 numpad
        if (h_cnt >= NR_NP_X       && h_cnt < NR_NP_X+STD_W       && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=17; end
        if (h_cnt >= NR_NP_X+31    && h_cnt < NR_NP_X+31+STD_W    && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=18; end
        if (h_cnt >= NR_NP_X+62    && h_cnt < NR_NP_X+62+STD_W    && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=19; end
        if (h_cnt >= NR_NP_X+93    && h_cnt < NR_NP_X+93+STD_W    && v_cnt >= NEWROW_Y && v_cnt < NEWROW_Y+KEY_H) begin in_newrow=1; newrow_idx=20; end
    end
	

    // Other rows and wide keys
    wire in_row2 = (v_cnt >= ROW2_Y && v_cnt < ROW2_Y + KEY_H &&
                    h_cnt >= 40 && h_cnt < 40 + 10*(STD_W+GAP));
    wire in_row3 = (v_cnt >= ROW3_Y && v_cnt < ROW3_Y + KEY_H &&
                    h_cnt >= 60 && h_cnt < 60 + 9*(STD_W+GAP));
    wire in_backspace = (h_cnt >= BACKSPACE_X && h_cnt < BACKSPACE_X + BACKSPACE_W &&
                         v_cnt >= NUM_Y && v_cnt < NUM_Y + KEY_H);
    wire in_space = (h_cnt >= SPACE_X && h_cnt < SPACE_X + SPACE_W &&
                     v_cnt >= ROW3_Y + KEY_H + GAP && v_cnt < ROW3_Y + KEY_H + GAP + KEY_H);

//    wire in_any_key = in_func_row || in_digit_key || in_backspace || in_row2 || in_row3 || in_space;
//	wire in_any_key = in_func_row || in_digit_key || in_newrow || in_backspace || in_row3 || in_space;
//	wire in_any_key = in_func_row || in_digit_key || in_newrow || in_tabrow || in_backspace || in_space;
//	wire in_any_key = in_func_row || in_digit_key || in_newrow || in_tabrow || in_capsrow || in_shiftrow || in_backspace;	
//	wire in_any_key = in_func_row || in_digit_key || in_newrow || in_tabrow || in_capsrow || in_shiftrow || in_botrow || in_backspace;
//    wire is_selected = in_digit_key && (hit_digit == sel_col);

	wire in_any_key = in_func_row || in_newrow || in_tabrow || in_capsrow || in_shiftrow || in_botrow;
    wire is_selected = in_newrow && (newrow_idx >= 5'd1) && (newrow_idx <= 5'd10) && (newrow_idx == {1'b0, sel_col} + 5'd1);


    // ---------- colors ----------
    localparam [23:0] COL_BG    = 24'hF2F1EE;
    localparam [23:0] COL_KEY   = 24'hFFFFFF;
    localparam [23:0] COL_HI    = 24'hD97757;
    localparam [23:0] COL_SHIFT = 24'h4ADE80;

    // ---------- large digit preview ----------
    localparam [10:0] RUNE_OX = 11'd200;   // roughly centered over the digit row
    localparam [10:0] RUNE_OY = 11'd20;

    // Large preview follows the currently highlighted digit key
    // Large preview is driven by the stable selection, not the current pixel
    reg [3:0] digit_idx;
    reg       digit_valid;
    always @(*) begin
        digit_valid = 1;                    // always show a digit for now
        // sel_col 0-8 → digits 1-9; treat col 9 (or wrap) as 0 if you add it later
        digit_idx = (sel_col == 4'd9) ? 4'd0 : sel_col + 4'd1;
    end

    wire        rune_in;
    wire [7:0]  rune_r, rune_g, rune_b;
    rune_digits rune_i (
        .clk      (clk_pixel),
        .digit    (digit_idx),
        .px       (h_cnt),
        .py       (v_cnt),
        .origin_x (RUNE_OX),
        .origin_y (RUNE_OY),
        .bg_rgb   (COL_BG),
        .in_view  (rune_in),
        .out_r    (rune_r),
        .out_g    (rune_g),
        .out_b    (rune_b)
    );
    wire show_rune = rune_in && digit_valid;

    // ---------- small glyph on the selected digit key ----------
//    wire [10:0] key_glyph_ox = dig_x[hit_digit] + 2;
//    wire [10:0] key_glyph_oy = NUM_Y;

//    reg [3:0] key_digit;
//    reg       key_is_digit;
//    always @(*) begin
//        key_is_digit = 0;
//        key_digit    = 4'd0;
//        if (in_digit_key) begin
//            key_is_digit = 1;
//            key_digit    = (hit_digit == 4'd9) ? 4'd0 : hit_digit + 4'd1;
//        end
//    end

//    wire        key_rune_in;
//    wire [7:0]  key_rune_r, key_rune_g, key_rune_b;
//    rune_digits #(.SCALE(1)) key_rune_i (
//        .clk      (clk_pixel),
//        .digit    (key_digit),
//        .px       (h_cnt),
//        .py       (v_cnt),
//        .origin_x (key_glyph_ox),
//        .origin_y (key_glyph_oy),
//        .bg_rgb   (is_selected ? COL_HI : COL_KEY),
//        .in_view  (key_rune_in),
//        .out_r    (key_rune_r),
//        .out_g    (key_rune_g),
//        .out_b    (key_rune_b)
//    );
//    wire show_key_glyph = in_digit_key && key_is_digit && key_rune_in;
	
    // ---------- small digit glyph on function keys ----------
    wire [10:0] func_glyph_ox = (func_idx==0)  ? ESC_X+1    :
                                (func_idx==1)  ? F1_X+1     :
                                (func_idx==2)  ? F2_X+1     :
                                (func_idx==3)  ? F3_X+1     :
                                (func_idx==4)  ? F4_X+1     :
                                (func_idx==5)  ? F5_X+1     :
                                (func_idx==6)  ? F6_X+1     :
                                (func_idx==7)  ? F7_X+1     :
                                (func_idx==8)  ? F8_X+1     :
                                (func_idx==9)  ? F9_X+1     :
                                (func_idx==10) ? F10_X+1    :
                                (func_idx==11) ? F11_X+1    :
                                (func_idx==12) ? F12_X+1    :
                                (func_idx==13) ? PRINT_X+1  :
                                (func_idx==14) ? SCROLL_X+1 :
                                (func_idx==15) ? PAUSE_X+1  :
                                (func_idx==16) ? CAPS_X+1   :
                                (func_idx==17) ? WIN_X+1    :
                                (func_idx==18) ? INS_X+1    :
                                                 GAME_X+1;
    wire [10:0] func_glyph_oy = FUNC_Y;
    wire [3:0]  func_digit    = func_idx % 10;

    wire        func_rune_in;
    wire [7:0]  func_rune_r, func_rune_g, func_rune_b;
    rune_digits #(.SCALE(1)) func_rune_i (
        .clk      (clk_pixel),
        .digit    (func_digit),
        .px       (h_cnt),
        .py       (v_cnt),
        .origin_x (func_glyph_ox),
        .origin_y (func_glyph_oy),
        .bg_rgb   (COL_KEY),
        .in_view  (func_rune_in),
        .out_r    (func_rune_r),
        .out_g    (func_rune_g),
        .out_b    (func_rune_b)
    );
    wire show_func_glyph = in_func_key && func_rune_in;	
	
    // ---------- cycling digit glyphs on the new row (for counting) ----------
    wire [10:0] nr_glyph_ox = (newrow_idx==0)  ? NR0_X+2  :
                              (newrow_idx==1)  ? NR1_X+2  :
                              (newrow_idx==2)  ? NR2_X+2  :
                              (newrow_idx==3)  ? NR3_X+2  :
                              (newrow_idx==4)  ? NR4_X+2  :
                              (newrow_idx==5)  ? NR5_X+2  :
                              (newrow_idx==6)  ? NR6_X+2  :
                              (newrow_idx==7)  ? NR7_X+2  :
                              (newrow_idx==8)  ? NR8_X+2  :
                              (newrow_idx==9)  ? NR9_X+2  :
                              (newrow_idx==10) ? NR10_X+2 :
                              (newrow_idx==11) ? NR11_X+2 :
                              (newrow_idx==12) ? NR12_X+2 :
                              (newrow_idx==13) ? NR_BS_X+2 :
                              (newrow_idx==14) ? NR_NAV_X+2 :
                              (newrow_idx==15) ? NR_NAV_X+33 :
                              (newrow_idx==16) ? NR_NAV_X+64 :
                              (newrow_idx==17) ? NR_NP_X+2 :
                              (newrow_idx==18) ? NR_NP_X+33 :
                              (newrow_idx==19) ? NR_NP_X+64 :
                                                 NR_NP_X+95;

    wire [10:0] nr_glyph_oy = NEWROW_Y;
    wire [3:0]  nr_digit    = newrow_idx % 10;

    wire        nr_rune_in;
    wire [7:0]  nr_rune_r, nr_rune_g, nr_rune_b;
    rune_digits #(.SCALE(1)) nr_rune_i (
        .clk      (clk_pixel),
        .digit    (nr_digit),
        .px       (h_cnt),
        .py       (v_cnt),
        .origin_x (nr_glyph_ox),
        .origin_y (nr_glyph_oy),
        .bg_rgb   (is_selected ? COL_HI : COL_KEY),
        .in_view  (nr_rune_in),
        .out_r    (nr_rune_r),
        .out_g    (nr_rune_g),
        .out_b    (nr_rune_b)
    );
    wire show_nr_glyph = in_newrow && nr_rune_in;
	
	
    // ---------- cycling digit glyphs on the tab row ----------
    wire [10:0] tr_glyph_ox = tr_x(tabrow_idx) + 11'd2;
    wire [10:0] tr_glyph_oy = TABROW_Y;
    wire [3:0]  tr_digit    = tabrow_idx % 10;

    wire        tr_rune_in;
    wire [7:0]  tr_rune_r, tr_rune_g, tr_rune_b;
    rune_digits #(.SCALE(1)) tr_rune_i (
        .clk      (clk_pixel),
        .digit    (tr_digit),
        .px       (h_cnt),
        .py       (v_cnt),
        .origin_x (tr_glyph_ox),
        .origin_y (tr_glyph_oy),
        .bg_rgb   (COL_KEY),
        .in_view  (tr_rune_in),
        .out_r    (tr_rune_r),
        .out_g    (tr_rune_g),
        .out_b    (tr_rune_b)
    );
    wire show_tr_glyph = in_tabrow && tr_rune_in;	
	
	
	
    // ---------- cycling digit glyphs on the caps row ----------
    wire [10:0] cr_glyph_ox = cr_x(capsrow_idx) + 11'd2;
    wire [10:0] cr_glyph_oy = CAPSROW_Y;
    wire [3:0]  cr_digit    = capsrow_idx % 10;

    wire        cr_rune_in;
    wire [7:0]  cr_rune_r, cr_rune_g, cr_rune_b;
    rune_digits #(.SCALE(1)) cr_rune_i (
        .clk      (clk_pixel),
        .digit    (cr_digit),
        .px       (h_cnt),
        .py       (v_cnt),
        .origin_x (cr_glyph_ox),
        .origin_y (cr_glyph_oy),
        .bg_rgb   (COL_KEY),
        .in_view  (cr_rune_in),
        .out_r    (cr_rune_r),
        .out_g    (cr_rune_g),
        .out_b    (cr_rune_b)
    );
    wire show_cr_glyph = in_capsrow && cr_rune_in;	
	
	
	
    // ---------- cycling digit glyphs on the shift row ----------
    wire [10:0] sr_glyph_ox = sr_x(shiftrow_idx) + 11'd2;
    wire [10:0] sr_glyph_oy = SHIFTROW_Y;
    wire [3:0]  sr_digit    = shiftrow_idx % 10;

    wire        sr_rune_in;
    wire [7:0]  sr_rune_r, sr_rune_g, sr_rune_b;
    rune_digits #(.SCALE(1)) sr_rune_i (
        .clk      (clk_pixel),
        .digit    (sr_digit),
        .px       (h_cnt),
        .py       (v_cnt),
        .origin_x (sr_glyph_ox),
        .origin_y (sr_glyph_oy),
        .bg_rgb   (COL_KEY),
        .in_view  (sr_rune_in),
        .out_r    (sr_rune_r),
        .out_g    (sr_rune_g),
        .out_b    (sr_rune_b)
    );
    wire show_sr_glyph = in_shiftrow && sr_rune_in;	
	


    // ---------- cycling digit glyphs on the bottom row ----------
    wire [10:0] br_glyph_ox = br_x(botrow_idx) + 11'd2;
    wire [10:0] br_glyph_oy = BOTROW_Y;
    wire [3:0]  br_digit    = botrow_idx % 10;

    wire        br_rune_in;
    wire [7:0]  br_rune_r, br_rune_g, br_rune_b;
    rune_digits #(.SCALE(1)) br_rune_i (
        .clk      (clk_pixel),
        .digit    (br_digit),
        .px       (h_cnt),
        .py       (v_cnt),
        .origin_x (br_glyph_ox),
        .origin_y (br_glyph_oy),
        .bg_rgb   (COL_KEY),
        .in_view  (br_rune_in),
        .out_r    (br_rune_r),
        .out_g    (br_rune_g),
        .out_b    (br_rune_b)
    );
    wire show_br_glyph = in_botrow && br_rune_in;
	
	
    // ---------- Tab row: Tab + 12 std + wide backslash + 3 nav + 4 numpad (tall +) ----------
    localparam TABROW_Y  = NEWROW_Y + KEY_H + GAP;
    localparam TR_TALL_H = 2*KEY_H + GAP;        // numpad + spans this row and the next

    function [10:0] tr_x;
        input [4:0] i;
        case (i)
            5'd0:  tr_x = 11'd16;                // Tab (wide)
            5'd1:  tr_x = 11'd63;
            5'd2:  tr_x = 11'd94;
            5'd3:  tr_x = 11'd125;
            5'd4:  tr_x = 11'd156;
            5'd5:  tr_x = 11'd187;
            5'd6:  tr_x = 11'd218;
            5'd7:  tr_x = 11'd249;
            5'd8:  tr_x = 11'd280;
            5'd9:  tr_x = 11'd311;
            5'd10: tr_x = 11'd342;
            5'd11: tr_x = 11'd373;
            5'd12: tr_x = 11'd404;
            5'd13: tr_x = 11'd435;               // backslash (wide)
            5'd14: tr_x = NR_NAV_X;
            5'd15: tr_x = NR_NAV_X + 31;
            5'd16: tr_x = NR_NAV_X + 62;
            5'd17: tr_x = NR_NP_X;
            5'd18: tr_x = NR_NP_X + 31;
            5'd19: tr_x = NR_NP_X + 62;
            5'd20: tr_x = NR_NP_X + 93;          // tall +
            default: tr_x = 11'd0;
        endcase
    endfunction

    function [10:0] tr_w;
        input [4:0] i;
        case (i)
            5'd0:  tr_w = 11'd44;                // Tab
            5'd13: tr_w = 11'd41;                // backslash, right edge lines up with Backspace above
            default: tr_w = STD_W;
        endcase
    endfunction

    reg        in_tabrow;
    reg [4:0]  tabrow_idx;
    integer    ti;
    always @(*) begin
        in_tabrow  = 0;
        tabrow_idx = 0;
        for (ti = 0; ti < 21; ti = ti + 1) begin
            if (h_cnt >= tr_x(ti[4:0]) && h_cnt < tr_x(ti[4:0]) + tr_w(ti[4:0]) &&
                v_cnt >= TABROW_Y &&
                v_cnt <  TABROW_Y + ((ti == 20) ? TR_TALL_H : KEY_H)) begin
                in_tabrow  = 1;
                tabrow_idx = ti[4:0];
            end
        end
    end	
	
	
	
    // ---------- Caps row: Caps + 11 std + wide Enter, gap, 3 numpad (+ already drawn) ----------
    localparam CAPSROW_Y = TABROW_Y + KEY_H + GAP;

    function [10:0] cr_x;
        input [4:0] i;
        case (i)
            5'd0:  cr_x = 11'd16;                // Caps (wide)
            5'd1:  cr_x = 11'd71;
            5'd2:  cr_x = 11'd102;
            5'd3:  cr_x = 11'd133;
            5'd4:  cr_x = 11'd164;
            5'd5:  cr_x = 11'd195;
            5'd6:  cr_x = 11'd226;
            5'd7:  cr_x = 11'd257;
            5'd8:  cr_x = 11'd288;
            5'd9:  cr_x = 11'd319;
            5'd10: cr_x = 11'd350;
            5'd11: cr_x = 11'd381;
            5'd12: cr_x = 11'd412;               // Enter (wide), right edge = 476
            5'd13: cr_x = NR_NP_X;               // numpad 4
            5'd14: cr_x = NR_NP_X + 31;          // numpad 5
            5'd15: cr_x = NR_NP_X + 62;          // numpad 6
            default: cr_x = 11'd0;
        endcase
    endfunction

    function [10:0] cr_w;
        input [4:0] i;
        case (i)
            5'd0:  cr_w = 11'd52;                // Caps
            5'd12: cr_w = 11'd64;                // Enter
            default: cr_w = STD_W;
        endcase
    endfunction

    reg        in_capsrow;
    reg [4:0]  capsrow_idx;
    integer    ci;
    always @(*) begin
        in_capsrow  = 0;
        capsrow_idx = 0;
        for (ci = 0; ci < 16; ci = ci + 1) begin
            if (h_cnt >= cr_x(ci[4:0]) && h_cnt < cr_x(ci[4:0]) + cr_w(ci[4:0]) &&
                v_cnt >= CAPSROW_Y && v_cnt < CAPSROW_Y + KEY_H) begin
                in_capsrow  = 1;
                capsrow_idx = ci[4:0];
            end
        end
    end	
	
	
	
    // ---------- Shift row: Shift + 10 std + Shift, gap, Up, gap, 3 numpad, tall Enter ----------
    localparam SHIFTROW_Y = CAPSROW_Y + KEY_H + GAP;
    localparam SR_TALL_H  = 2*KEY_H + GAP;       // Enter spans this row and the next

    function [10:0] sr_x;
        input [4:0] i;
        case (i)
            5'd0:  sr_x = 11'd16;                // left Shift (wide)
            5'd1:  sr_x = 11'd92;
            5'd2:  sr_x = 11'd123;
            5'd3:  sr_x = 11'd154;
            5'd4:  sr_x = 11'd185;
            5'd5:  sr_x = 11'd216;
            5'd6:  sr_x = 11'd247;
            5'd7:  sr_x = 11'd278;
            5'd8:  sr_x = 11'd309;
            5'd9:  sr_x = 11'd340;
            5'd10: sr_x = 11'd371;
            5'd11: sr_x = 11'd402;               // right Shift (wide), right edge = 476
            5'd12: sr_x = NR_NAV_X + 31;         // Up arrow (middle nav slot)
            5'd13: sr_x = NR_NP_X;               // numpad 1
            5'd14: sr_x = NR_NP_X + 31;          // numpad 2
            5'd15: sr_x = NR_NP_X + 62;          // numpad 3
            5'd16: sr_x = NR_NP_X + 93;          // tall Enter
            default: sr_x = 11'd0;
        endcase
    endfunction

    function [10:0] sr_w;
        input [4:0] i;
        case (i)
            5'd0:  sr_w = 11'd73;                // left Shift
            5'd11: sr_w = 11'd74;                // right Shift
            default: sr_w = STD_W;
        endcase
    endfunction

    reg        in_shiftrow;
    reg [4:0]  shiftrow_idx;
    integer    si;
    always @(*) begin
        in_shiftrow  = 0;
        shiftrow_idx = 0;
        for (si = 0; si < 17; si = si + 1) begin
            if (h_cnt >= sr_x(si[4:0]) && h_cnt < sr_x(si[4:0]) + sr_w(si[4:0]) &&
                v_cnt >= SHIFTROW_Y &&
                v_cnt <  SHIFTROW_Y + ((si == 16) ? SR_TALL_H : KEY_H)) begin
                in_shiftrow  = 1;
                shiftrow_idx = si[4:0];
            end
        end
    end	
	



    // ---------- Bottom row: Ctrl, Win, Alt, Space, Alt, Win, Menu, Ctrl, 3 arrows, wide 0, period ----------
    localparam BOTROW_Y = SHIFTROW_Y + KEY_H + GAP;

    function [10:0] br_x;
        input [4:0] i;
        case (i)
            5'd0:  br_x = 11'd16;                // left Ctrl (wide)
            5'd1:  br_x = 11'd59;                // Win
            5'd2:  br_x = 11'd96;                // Alt
            5'd3:  br_x = 11'd133;               // Space (very wide)
            5'd4:  br_x = 11'd325;               // Alt
            5'd5:  br_x = 11'd362;               // Win
            5'd6:  br_x = 11'd399;               // Menu
            5'd7:  br_x = 11'd436;               // right Ctrl (wide), right edge = 476
            5'd8:  br_x = NR_NAV_X;              // Left arrow
            5'd9:  br_x = NR_NAV_X + 31;         // Down arrow (under Up)
            5'd10: br_x = NR_NAV_X + 62;         // Right arrow
            5'd11: br_x = NR_NP_X;               // wide 0
            5'd12: br_x = NR_NP_X + 62;          // period
            default: br_x = 11'd0;
        endcase
    endfunction

    function [10:0] br_w;
        input [4:0] i;
        case (i)
            5'd0:  br_w = 11'd40;                // Ctrl
            5'd1:  br_w = 11'd34;                // Win
            5'd2:  br_w = 11'd34;                // Alt
            5'd3:  br_w = 11'd189;               // Space
            5'd4:  br_w = 11'd34;                // Alt
            5'd5:  br_w = 11'd34;                // Win
            5'd6:  br_w = 11'd34;                // Menu
            5'd7:  br_w = 11'd40;                // Ctrl
            5'd11: br_w = 11'd59;                // 0 spans two numpad columns (28 + 3 + 28)
            default: br_w = STD_W;
        endcase
    endfunction

    reg        in_botrow;
    reg [4:0]  botrow_idx;
    integer    bi;
    always @(*) begin
        in_botrow  = 0;
        botrow_idx = 0;
        for (bi = 0; bi < 13; bi = bi + 1) begin
            if (h_cnt >= br_x(bi[4:0]) && h_cnt < br_x(bi[4:0]) + br_w(bi[4:0]) &&
                v_cnt >= BOTROW_Y && v_cnt < BOTROW_Y + KEY_H) begin
                in_botrow  = 1;
                botrow_idx = bi[4:0];
            end
        end
    end	

    // ---------- final pixel ----------
	wire [7:0] pix_r = show_rune ? rune_r :
                       //show_key_glyph ? key_rune_r :
                       show_func_glyph ? func_rune_r :
                       show_nr_glyph ? nr_rune_r :
					   show_tr_glyph ? tr_rune_r :
					   show_cr_glyph ? cr_rune_r :
					   show_sr_glyph ? sr_rune_r :
					   show_br_glyph ? br_rune_r :
                       is_selected ? COL_HI[23:16] :
                       in_any_key ? COL_KEY[23:16] :
                       (shift_on && v_cnt < 40 && h_cnt < 80) ? COL_SHIFT[23:16] :
                       COL_BG[23:16];

    wire [7:0] pix_g = show_rune ? rune_g :
                       //show_key_glyph ? key_rune_g :
                       show_func_glyph ? func_rune_g :
					   show_nr_glyph ? nr_rune_g :
					   show_tr_glyph ? tr_rune_g :
					   show_cr_glyph ? cr_rune_g :
					   show_sr_glyph ? sr_rune_g :
					   show_br_glyph ? br_rune_g :
                       is_selected ? COL_HI[15:8] :
                       in_any_key ? COL_KEY[15:8] :
                       (shift_on && v_cnt < 40 && h_cnt < 80) ? COL_SHIFT[15:8] :
                       COL_BG[15:8];

    wire [7:0] pix_b = show_rune ? rune_b :
                       //show_key_glyph ? key_rune_b :
                       show_func_glyph ? func_rune_b :
					   show_nr_glyph ? nr_rune_b :
					   show_tr_glyph ? tr_rune_b :
					   show_cr_glyph ? cr_rune_b :
					   show_sr_glyph ? sr_rune_b :
					   show_br_glyph ? br_rune_b :
                       is_selected ? COL_HI[7:0] :
                       in_any_key ? COL_KEY[7:0] :
                       (shift_on && v_cnt < 40 && h_cnt < 80) ? COL_SHIFT[7:0] :
                       COL_BG[7:0];				   
					   

    // ---------- TMDS + serializer (identical to original) ----------
    wire [9:0] tmds_b, tmds_g, tmds_r;
    tmds_encoder enc_b (.clk(clk_pixel), .data(pix_b), .c({vsync, hsync}), .blank(blank), .encoded(tmds_b));
    tmds_encoder enc_g (.clk(clk_pixel), .data(pix_g), .c(2'b00),          .blank(blank), .encoded(tmds_g));
    tmds_encoder enc_r (.clk(clk_pixel), .data(pix_r), .c(2'b00),          .blank(blank), .encoded(tmds_r));

    reg ptog = 0;
    always @(posedge clk_pixel) ptog <= ~ptog;

    reg t1=0, t2=0;
    reg [4:0] ring = 5'b00001;
    reg [9:0] sr_b=0, sr_g=0, sr_r=0, sr_c=0;
    wire detect = (t1 != t2);
    always @(posedge clk_shift) begin
        t1 <= ptog; t2 <= t1;
        if (detect) ring <= 5'b00001;
        else        ring <= {ring[3:0], ring[4]};
        if (ring[0]) begin
            sr_b <= tmds_b; sr_g <= tmds_g; sr_r <= tmds_r; sr_c <= 10'b0000011111;
        end else begin
            sr_b <= {2'b00, sr_b[9:2]};
            sr_g <= {2'b00, sr_g[9:2]};
            sr_r <= {2'b00, sr_r[9:2]};
            sr_c <= {2'b00, sr_c[9:2]};
        end
    end

    ODDRX1F ddr_b (.SCLK(clk_shift), .RST(1'b0), .D0(sr_b[0]), .D1(sr_b[1]), .Q(gpdi_dp[0]));
    ODDRX1F ddr_g (.SCLK(clk_shift), .RST(1'b0), .D0(sr_g[0]), .D1(sr_g[1]), .Q(gpdi_dp[1]));
    ODDRX1F ddr_r (.SCLK(clk_shift), .RST(1'b0), .D0(sr_r[0]), .D1(sr_r[1]), .Q(gpdi_dp[2]));
    ODDRX1F ddr_c (.SCLK(clk_shift), .RST(1'b0), .D0(sr_c[0]), .D1(sr_c[1]), .Q(gpdi_dp[3]));
endmodule