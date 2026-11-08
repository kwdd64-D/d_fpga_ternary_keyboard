// top.v — on-screen keyboard navigable by balanced ternary
// Buttons: LEFT/RIGHT/UP/DOWN move the highlight over every key,
//          FIRE1 = Shift toggle, FIRE2 = press the highlighted key
//          (Caps, Shift and the Win/Ins/Game locks toggle; Win/Ins/Game are one-at-a-time)
//
// LEGENDS: every key's legend comes from keymap.hex via {bank, shift, key id}
// (built by tools/build_keymap.py from keymap.csv).
//
// KEYBOARD POSITION: change KB_X and KB_Y below to move the whole keyboard.
// All key geometry is local to the keyboard (0,0 = top-left of the function row).
//
// GLYPHS: one glyph_rom holds the art (2 bits per pixel, glyphs2.hex, built by
// tools/build_glyphs.py). Port A serves ONE shared key-glyph renderer
// (whichever key is under the beam), port B serves the big preview.
// A glyph is addressed by a 10-bit rune code (0..725).

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

    // ---------- button sync + edge detect ----------
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

    // (cursor, lock and bank state live further down, after the key geometry)

    // ternary increment / decrement helpers (2-digit balanced), not used yet
    function [3:0] tinc2;  // returns {hi,lo} after +1
        input [1:0] hi, lo;
        reg signed [3:0] v;
        begin
            v = trit_val(lo) + 3*trit_val(hi) + 1;
            if (v > 4) v = 4;
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

    // =====================================================================
    //  KEYBOARD POSITION AND SIZE  — edit KB_X / KB_Y to move the keyboard
    // =====================================================================
    localparam [10:0] KB_X = 11'd45;     // left edge on screen
    localparam [10:0] KB_Y = 11'd450;   // top edge on screen
    localparam [10:0] KB_W = 11'd704;   // bounding box (keys end at x = 701)
    localparam [10:0] KB_H = 11'd144;   // bounding box (keys end at y = 141)

    wire in_kb = (h_cnt >= KB_X) && (h_cnt < KB_X + KB_W) &&
                 (v_cnt >= KB_Y) && (v_cnt < KB_Y + KB_H);

    // Keyboard-local pixel coordinates. Outside the box they are forced to
    // 2047 so no key or glyph can ever match there.
    wire [10:0] kx = in_kb ? (h_cnt - KB_X) : 11'h7FF;
    wire [10:0] ky = in_kb ? (v_cnt - KB_Y) : 11'h7FF;

    // ---------- keyboard geometry (all local to the keyboard) ----------
    localparam KEY_H = 20;
    localparam GAP   = 3;
    localparam STD_W = 28;

    localparam FUNC_Y    = 0;
    localparam NEWROW_Y  = FUNC_Y    + KEY_H + GAP + 6;
    localparam TABROW_Y  = NEWROW_Y  + KEY_H + GAP;
    localparam CAPSROW_Y = TABROW_Y  + KEY_H + GAP;
    localparam SHIFTROW_Y= CAPSROW_Y + KEY_H + GAP;
    localparam BOTROW_Y  = SHIFTROW_Y+ KEY_H + GAP;
    localparam TALL_H    = 2*KEY_H + GAP;   // tall numpad + and Enter

    localparam NR_NAV_X = 484;   // nav column (3 keys, 31 px pitch)
    localparam NR_NP_X  = 580;   // numpad column (4 keys, 31 px pitch)

    // ---------- Row 1: function row, 20 keys ----------
    localparam FUNC_W = 22;

    function [10:0] func_x;
        input [4:0] i;
        case (i)
            5'd0:  func_x = 11'd10;   // ESC
            5'd1:  func_x = 11'd40;   // F1
            5'd2:  func_x = 11'd64;
            5'd3:  func_x = 11'd88;
            5'd4:  func_x = 11'd112;
            5'd5:  func_x = 11'd136;
            5'd6:  func_x = 11'd160;
            5'd7:  func_x = 11'd184;
            5'd8:  func_x = 11'd208;
            5'd9:  func_x = 11'd232;
            5'd10: func_x = 11'd256;
            5'd11: func_x = 11'd280;
            5'd12: func_x = 11'd304;  // F12
            5'd13: func_x = 11'd336;  // PRINT
            5'd14: func_x = 11'd360;  // SCROLL
            5'd15: func_x = 11'd384;  // PAUSE
            5'd16: func_x = 11'd416;  // CAPS
            5'd17: func_x = 11'd440;  // WIN
            5'd18: func_x = 11'd464;  // INS
            5'd19: func_x = 11'd488;  // GAME
            default: func_x = 11'd0;
        endcase
    endfunction

    reg        in_func_key;
    reg [4:0]  func_idx;
    integer    fi;
    always @(*) begin
        in_func_key = 0;
        func_idx    = 0;
        for (fi = 0; fi < 20; fi = fi + 1) begin
            if (kx >= func_x(fi[4:0]) && kx < func_x(fi[4:0]) + FUNC_W &&
                ky >= FUNC_Y && ky < FUNC_Y + KEY_H) begin
                in_func_key = 1;
                func_idx    = fi[4:0];
            end
        end
    end

    // ---------- Row 2: number row, 13 std + wide BS + 3 nav + 4 numpad ----------
    function [10:0] nr_x;
        input [4:0] i;
        case (i)
            5'd0:  nr_x = 11'd16;
            5'd1:  nr_x = 11'd47;
            5'd2:  nr_x = 11'd78;
            5'd3:  nr_x = 11'd109;
            5'd4:  nr_x = 11'd140;
            5'd5:  nr_x = 11'd171;
            5'd6:  nr_x = 11'd202;
            5'd7:  nr_x = 11'd233;
            5'd8:  nr_x = 11'd264;
            5'd9:  nr_x = 11'd295;
            5'd10: nr_x = 11'd326;
            5'd11: nr_x = 11'd357;
            5'd12: nr_x = 11'd388;
            5'd13: nr_x = 11'd420;               // Backspace (wide)
            5'd14: nr_x = NR_NAV_X;
            5'd15: nr_x = NR_NAV_X + 31;
            5'd16: nr_x = NR_NAV_X + 62;
            5'd17: nr_x = NR_NP_X;
            5'd18: nr_x = NR_NP_X + 31;
            5'd19: nr_x = NR_NP_X + 62;
            5'd20: nr_x = NR_NP_X + 93;
            default: nr_x = 11'd0;
        endcase
    endfunction

    function [10:0] nr_w;
        input [4:0] i;
        case (i)
            5'd13:   nr_w = 11'd56;              // Backspace
            default: nr_w = STD_W;
        endcase
    endfunction

    reg        in_newrow;
    reg [4:0]  newrow_idx;
    integer    ni;
    always @(*) begin
        in_newrow  = 0;
        newrow_idx = 0;
        for (ni = 0; ni < 21; ni = ni + 1) begin
            if (kx >= nr_x(ni[4:0]) && kx < nr_x(ni[4:0]) + nr_w(ni[4:0]) &&
                ky >= NEWROW_Y && ky < NEWROW_Y + KEY_H) begin
                in_newrow  = 1;
                newrow_idx = ni[4:0];
            end
        end
    end

    // ---------- Row 3: Tab + 12 std + wide backslash + 3 nav + 4 numpad (tall +) ----------
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
            5'd13: tr_w = 11'd41;                // backslash
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
            if (kx >= tr_x(ti[4:0]) && kx < tr_x(ti[4:0]) + tr_w(ti[4:0]) &&
                ky >= TABROW_Y &&
                ky <  TABROW_Y + ((ti == 20) ? TALL_H : KEY_H)) begin
                in_tabrow  = 1;
                tabrow_idx = ti[4:0];
            end
        end
    end

    // ---------- Row 4: Caps + 11 std + wide Enter, gap, 3 numpad ----------
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
            5'd12: cr_x = 11'd412;               // Enter (wide)
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
            if (kx >= cr_x(ci[4:0]) && kx < cr_x(ci[4:0]) + cr_w(ci[4:0]) &&
                ky >= CAPSROW_Y && ky < CAPSROW_Y + KEY_H) begin
                in_capsrow  = 1;
                capsrow_idx = ci[4:0];
            end
        end
    end

    // ---------- Row 5: Shift + 10 std + Shift, gap, Up, gap, 3 numpad, tall Enter ----------
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
            5'd11: sr_x = 11'd402;               // right Shift (wide)
            5'd12: sr_x = NR_NAV_X + 31;         // Up arrow
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
            if (kx >= sr_x(si[4:0]) && kx < sr_x(si[4:0]) + sr_w(si[4:0]) &&
                ky >= SHIFTROW_Y &&
                ky <  SHIFTROW_Y + ((si == 16) ? TALL_H : KEY_H)) begin
                in_shiftrow  = 1;
                shiftrow_idx = si[4:0];
            end
        end
    end

    // ---------- Row 6: Ctrl, Win, Alt, Space, Alt, Win, Menu, Ctrl, 3 arrows, wide 0, period ----------
    function [10:0] br_x;
        input [4:0] i;
        case (i)
            5'd0:  br_x = 11'd16;                // left Ctrl (wide)
            5'd1:  br_x = 11'd59;                // Win
            5'd2:  br_x = 11'd96;                // Alt
            5'd3:  br_x = 11'd133;               // Space
            5'd4:  br_x = 11'd325;               // Alt
            5'd5:  br_x = 11'd362;               // Win
            5'd6:  br_x = 11'd399;               // Menu
            5'd7:  br_x = 11'd436;               // right Ctrl (wide)
            5'd8:  br_x = NR_NAV_X;              // Left arrow
            5'd9:  br_x = NR_NAV_X + 31;         // Down arrow
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
            5'd11: br_w = 11'd59;                // 0 spans two numpad columns
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
            if (kx >= br_x(bi[4:0]) && kx < br_x(bi[4:0]) + br_w(bi[4:0]) &&
                ky >= BOTROW_Y && ky < BOTROW_Y + KEY_H) begin
                in_botrow  = 1;
                botrow_idx = bi[4:0];
            end
        end
    end

    // =====================================================================
    //  KEY IDS, CURSOR, LOCKS AND KEYMAP
    // =====================================================================
    // Every physical key has one global id = row base + index in its row.
    // The keymap ROM (keymap.hex, built by tools/build_keymap.py) turns
    // {bank, shift, key id} into a rune code, so the legend drawn on a key and
    // the rune it will type always come from the same place.
    localparam GLYPHS = 512;            // glyph slots in glyphs2.hex (match bake_runes.py --count)

    localparam [6:0] BASE_R0 = 7'd0;    // function row   20 keys
    localparam [6:0] BASE_R1 = 7'd20;   // number row     21 keys
    localparam [6:0] BASE_R2 = 7'd41;   // tab row        21 keys
    localparam [6:0] BASE_R3 = 7'd62;   // caps row       16 keys
    localparam [6:0] BASE_R4 = 7'd78;   // shift row      17 keys
    localparam [6:0] BASE_R5 = 7'd95;   // bottom row     13 keys  (108 keys total)

    localparam [6:0] KID_CAPS = BASE_R0 + 7'd16;   // function row: Caps, Win, Ins, Game locks
    localparam [6:0] KID_WIN  = BASE_R0 + 7'd17;
    localparam [6:0] KID_INS  = BASE_R0 + 7'd18;
    localparam [6:0] KID_GAME = BASE_R0 + 7'd19;
    localparam [6:0] KID_SHL  = BASE_R4 + 7'd0;    // left Shift
    localparam [6:0] KID_SHR  = BASE_R4 + 7'd11;   // right Shift
    localparam [6:0] KID_ESC  = BASE_R0 + 7'd0;
    localparam [6:0] KID_BKSP = BASE_R1 + 7'd13;
    localparam [6:0] KID_TAB  = BASE_R2 + 7'd0;
    localparam [6:0] KID_DEL  = BASE_R2 + 7'd15;
    localparam [6:0] KID_ENT  = BASE_R3 + 7'd12;
    localparam [6:0] KID_UP   = BASE_R4 + 7'd12;
    localparam [6:0] KID_NENT = BASE_R4 + 7'd16;   // numpad Enter
    localparam [6:0] KID_SPC  = BASE_R5 + 7'd3;
    localparam [6:0] KID_LEFT = BASE_R5 + 7'd8;
    localparam [6:0] KID_DOWN = BASE_R5 + 7'd9;
    localparam [6:0] KID_RGT  = BASE_R5 + 7'd10;

    // glyph slot map (must match the rune generator)
    localparam [9:0] UI_BASE  = 10'd135;   // 135..199 = legend-only symbols, never typed
    localparam [9:0] VAR_BASE = 10'd200;   // 200.. = bank variants, typeable

    function [6:0] row_base;
        input [2:0] r;
        case (r)
            3'd0:    row_base = BASE_R0;
            3'd1:    row_base = BASE_R1;
            3'd2:    row_base = BASE_R2;
            3'd3:    row_base = BASE_R3;
            3'd4:    row_base = BASE_R4;
            default: row_base = BASE_R5;
        endcase
    endfunction

    function [4:0] row_count;
        input [2:0] r;
        case (r)
            3'd0:    row_count = 5'd20;
            3'd1:    row_count = 5'd21;
            3'd2:    row_count = 5'd21;
            3'd3:    row_count = 5'd16;
            3'd4:    row_count = 5'd17;
            default: row_count = 5'd13;
        endcase
    endfunction

    // centre x of key i in row r (used to pick the nearest key on UP / DOWN)
    function [10:0] key_cx;
        input [2:0] r;
        input [4:0] i;
        case (r)
            3'd0:    key_cx = func_x(i) + (FUNC_W >> 1);
            3'd1:    key_cx = nr_x(i) + (nr_w(i) >> 1);
            3'd2:    key_cx = tr_x(i) + (tr_w(i) >> 1);
            3'd3:    key_cx = cr_x(i) + (cr_w(i) >> 1);
            3'd4:    key_cx = sr_x(i) + (sr_w(i) >> 1);
            default: key_cx = br_x(i) + (br_w(i) >> 1);
        endcase
    endfunction

    // ---------- state ----------
    reg [2:0]  cur_row   = 3'd1;         // cursor starts on the "1" key
    reg [4:0]  cur_idx   = 5'd1;
    reg        shift_on  = 1'b0;         // latched, like Caps Lock
    reg        caps_on   = 1'b0;
    reg [1:0]  bank      = 2'd0;         // 0 none, 1 Win, 2 Ins, 3 Game  (one active at a time)
    reg [6:0]  caret     = 7'd0;         // text cell that the next rune goes into (row*16 + col)

    // text buffer: 16 columns x 8 rows, one 10-bit rune per cell, 0x3FF = empty cell
    reg [9:0]  tbuf [0:127];
    integer    ti;
    initial for (ti = 0; ti < 128; ti = ti + 1) tbuf[ti] = 10'h3FF;

    // one registered write port (the cursor logic requests, this block performs)
    reg        w_en   = 1'b0;
    reg [6:0]  w_addr = 7'd0;
    reg [9:0]  w_data = 10'h3FF;
    reg        clr_req = 1'b0;          // Esc asks for a clear (one clock pulse from the cursor block)
    reg        clr_on = 1'b0;            // sweep the whole buffer to empty (owned by this block only)
    reg [6:0]  clr_i  = 7'd0;
    always @(posedge clk_pixel) begin
        if (clr_req) begin
            clr_on <= 1'b1;
            clr_i  <= 7'd0;
        end else if (clr_on) begin
            tbuf[clr_i] <= 10'h3FF;
            clr_i <= clr_i + 7'd1;
            if (clr_i == 7'd127) clr_on <= 1'b0;
        end else if (w_en) begin
            tbuf[w_addr] <= w_data;
        end
    end

    // nearest-key search for UP / DOWN: one candidate key per clock
    reg        searching = 1'b0;
    reg [2:0]  tgt_row   = 3'd0;
    reg [4:0]  sk        = 5'd0;
    reg [4:0]  best_idx  = 5'd0;
    reg [10:0] best_dist = 11'd0;
    reg [10:0] cur_cx    = 11'd0;

    // ---------- keymap ROM (asynchronous read, so legends never lag the beam) ----------
    reg [9:0] kmap    [0:1023];          // address = {bank[1:0], shift, key id[6:0]}
    reg       kletter [0:127];           // 1 = Caps Lock flips this key (letters)
    initial begin
        $readmemh("keymap.hex",   kmap);
        $readmemh("keyflags.hex", kletter);
    end

    wire [6:0]  cur_kid      = row_base(cur_row) + {2'b00, cur_idx};
    wire        cur_shift    = shift_on ^ (caps_on & kletter[cur_kid]);
    wire [9:0]  cur_code     = kmap[{bank, cur_shift, cur_kid}];
    wire        cur_code_ok  = (cur_code != 10'h3FF) && (cur_code < GLYPHS);
    // a key types a rune only if its legend is a real rune (not a UI symbol)
    wire        cur_typeable = cur_code_ok && ((cur_code < UI_BASE) || (cur_code >= VAR_BASE));

    wire [6:0]  caret_next   = (caret == 7'd127) ? 7'd127 : caret + 7'd1;
    wire [6:0]  tab_next     = (caret[6:2] == 5'd31) ? 7'd127 : {caret[6:2] + 5'd1, 2'b00};
    wire [6:0]  enter_next   = (caret[6:4] == 3'd7) ? {3'd7, 4'd0} : {caret[6:4] + 3'd1, 4'd0};

    wire [4:0]  tgt_cnt  = row_count(tgt_row);
    wire [10:0] sk_cx    = key_cx(tgt_row, sk);
    wire [10:0] sk_dist  = (sk_cx > cur_cx) ? (sk_cx - cur_cx) : (cur_cx - sk_cx);

    // ---------- cursor, locks, bank ----------
    // LEFT/RIGHT move along the row. UP/DOWN change row and land on the key
    // whose centre is nearest (takes about 20 clocks, presses are ignored meanwhile).
    // FIRE1 toggles Shift. FIRE2 presses the highlighted key.
    always @(posedge clk_pixel) begin
        w_en    <= 1'b0;                            // default: no buffer write this clock
        clr_req <= 1'b0;
        if (searching) begin
            if (sk < tgt_cnt) begin
                if (sk == 5'd0 || sk_dist < best_dist) begin
                    best_dist <= sk_dist;
                    best_idx  <= sk;
                end
                sk <= sk + 5'd1;
            end else begin
                cur_row   <= tgt_row;
                cur_idx   <= best_idx;
                searching <= 1'b0;
            end
        end else begin
            if (press_right && (cur_idx + 5'd1 < row_count(cur_row)))
                cur_idx <= cur_idx + 5'd1;
            if (press_left && cur_idx != 5'd0)
                cur_idx <= cur_idx - 5'd1;

            if (press_up && cur_row != 3'd0) begin
                tgt_row   <= cur_row - 3'd1;
                cur_cx    <= key_cx(cur_row, cur_idx);
                sk        <= 5'd0;
                searching <= 1'b1;
            end
            if (press_down && cur_row != 3'd5) begin
                tgt_row   <= cur_row + 3'd1;
                cur_cx    <= key_cx(cur_row, cur_idx);
                sk        <= 5'd0;
                searching <= 1'b1;
            end

            if (press_shift) shift_on <= ~shift_on;

            if (press_key) begin
                if      (cur_kid == KID_CAPS) caps_on <= ~caps_on;
                else if (cur_kid == KID_WIN)  bank <= (bank == 2'd1) ? 2'd0 : 2'd1;
                else if (cur_kid == KID_INS)  bank <= (bank == 2'd2) ? 2'd0 : 2'd2;
                else if (cur_kid == KID_GAME) bank <= (bank == 2'd3) ? 2'd0 : 2'd3;
                else if (cur_kid == KID_SHL || cur_kid == KID_SHR) shift_on <= ~shift_on;
                else if (cur_kid == KID_ESC) begin          // clear everything
                    clr_req <= 1'b1;
                    caret   <= 7'd0;
                end
                else if (cur_kid == KID_BKSP) begin         // erase the cell before the caret
                    if (caret != 7'd0) begin
                        caret  <= caret - 7'd1;
                        w_en   <= 1'b1;
                        w_addr <= caret - 7'd1;
                        w_data <= 10'h3FF;
                    end
                end
                else if (cur_kid == KID_DEL) begin          // erase the caret cell, stay
                    w_en   <= 1'b1;
                    w_addr <= caret;
                    w_data <= 10'h3FF;
                end
                else if (cur_kid == KID_SPC) begin          // blank cell, advance
                    w_en   <= 1'b1;
                    w_addr <= caret;
                    w_data <= 10'h3FF;
                    caret  <= caret_next;
                end
                else if (cur_kid == KID_ENT || cur_kid == KID_NENT) caret <= enter_next;
                else if (cur_kid == KID_TAB)  caret <= tab_next;
                else if (cur_kid == KID_LEFT) begin if (caret != 7'd0)   caret <= caret - 7'd1; end
                else if (cur_kid == KID_RGT)  caret <= caret_next;
                else if (cur_kid == KID_UP)   begin if (caret >= 7'd16)  caret <= caret - 7'd16; end
                else if (cur_kid == KID_DOWN) begin if (caret <  7'd112) caret <= caret + 7'd16; end
                else if (cur_typeable) begin                // type the rune
                    w_en   <= 1'b1;
                    w_addr <= caret;
                    w_data <= cur_code;
                    caret  <= caret_next;
                end
            end
        end
    end

    // ---------- key under the beam ----------
    wire in_any_key = in_func_key || in_newrow || in_tabrow ||
                      in_capsrow  || in_shiftrow || in_botrow;

    wire [2:0] beam_row = in_func_key ? 3'd0 : in_newrow  ? 3'd1 : in_tabrow ? 3'd2 :
                          in_capsrow  ? 3'd3 : in_shiftrow ? 3'd4 : 3'd5;
    wire [4:0] beam_idx = in_func_key ? func_idx   : in_newrow  ? newrow_idx   :
                          in_tabrow   ? tabrow_idx : in_capsrow ? capsrow_idx  :
                          in_shiftrow ? shiftrow_idx : botrow_idx;
    wire [6:0] beam_kid = in_func_key ? BASE_R0 + {2'b00, func_idx}     :
                          in_newrow   ? BASE_R1 + {2'b00, newrow_idx}   :
                          in_tabrow   ? BASE_R2 + {2'b00, tabrow_idx}   :
                          in_capsrow  ? BASE_R3 + {2'b00, capsrow_idx}  :
                          in_shiftrow ? BASE_R4 + {2'b00, shiftrow_idx} :
                                        BASE_R5 + {2'b00, botrow_idx};

    // left edge, top edge and width of that key (keyboard-local)
    wire [10:0] k_x = in_func_key ? func_x(func_idx)   : in_newrow  ? nr_x(newrow_idx)  :
                      in_tabrow   ? tr_x(tabrow_idx)   : in_capsrow ? cr_x(capsrow_idx) :
                      in_shiftrow ? sr_x(shiftrow_idx) : br_x(botrow_idx);
    wire [10:0] k_w = in_func_key ? FUNC_W             : in_newrow  ? nr_w(newrow_idx)  :
                      in_tabrow   ? tr_w(tabrow_idx)   : in_capsrow ? cr_w(capsrow_idx) :
                      in_shiftrow ? sr_w(shiftrow_idx) : br_w(botrow_idx);
    wire [10:0] k_y = in_func_key ? FUNC_Y    : in_newrow  ? NEWROW_Y  :
                      in_tabrow   ? TABROW_Y  : in_capsrow ? CAPSROW_Y :
                      in_shiftrow ? SHIFTROW_Y : BOTROW_Y;

    // rune for the key under the beam (same lookup as the cursor's, different key)
    wire        beam_shift   = shift_on ^ (caps_on & kletter[beam_kid]);
    wire [9:0]  beam_code    = kmap[{bank, beam_shift, beam_kid}];
    wire        beam_code_ok = (beam_code != 10'h3FF) && (beam_code < GLYPHS);

    // highlighted key = the cursor
    wire is_selected = in_any_key && (beam_row == cur_row) && (beam_idx == cur_idx);

    // lock indicator: a small bar at the bottom of Shift, Caps and the three bank locks
    wire beam_is_shift = (beam_kid == KID_SHL) || (beam_kid == KID_SHR);
    wire key_is_lock   = beam_is_shift || (beam_kid == KID_CAPS) ||
                         (beam_kid == KID_WIN) || (beam_kid == KID_INS) || (beam_kid == KID_GAME);
    wire key_lit = (beam_is_shift && shift_on) || (beam_kid == KID_CAPS && caps_on) ||
                   (beam_kid == KID_WIN  && bank == 2'd1) ||
                   (beam_kid == KID_INS  && bank == 2'd2) ||
                   (beam_kid == KID_GAME && bank == 2'd3);
    wire [10:0] led_cx  = k_x + (k_w >> 1);
    wire        led_hit = in_any_key && key_is_lock &&
                          (ky >= k_y + 17) && (ky < k_y + 19) &&
                          (kx + 5 >= led_cx) && (kx < led_cx + 5);

    // ---------- colors ----------
    localparam [23:0] COL_BG     = 24'hF2F1EE;
    localparam [23:0] COL_KEY    = 24'hFFFFFF;
    localparam [23:0] COL_HI     = 24'hD97757;
    localparam [23:0] COL_SHIFT  = 24'h4ADE80;   // lock indicator, on
    localparam [23:0] COL_LEDOFF = 24'hC9C6BF;   // lock indicator, off
    wire [23:0] led_col = key_lit ? COL_SHIFT : COL_LEDOFF;

    // =====================================================================
    //  GLYPHS — one ROM, two renderers
    // =====================================================================
    wire [19:0] rom_addr_key, rom_addr_prev;
    wire [1:0]  rom_data_key, rom_data_prev;

    glyph_rom #(.GLYPHS(GLYPHS), .FILE("glyphs2.hex")) glyph_rom_i (
        .clk    (clk_pixel),
        .addr_a (rom_addr_key),
        .data_a (rom_data_key),
        .addr_b (rom_addr_prev),
        .data_b (rom_data_prev)
    );

    // ---------- text area: 16 x 8 cells of 32x32 runes, 1:1 ----------
    localparam [10:0] TX = 11'd144;
    localparam [10:0] TY = 11'd20;

    // Everything here is computed for the NEXT pixel (nx), because the glyph ROM
    // output is registered; the flags are then registered so they line up.
    wire [10:0] t_nx   = h_cnt + 11'd1;
    wire [10:0] t_dx   = t_nx - TX;
    wire [10:0] t_dy   = v_cnt - TY;
    wire        t_in_n = (t_nx >= TX) && (t_dx < 11'd512) && (v_cnt >= TY) && (t_dy < 11'd256);
    wire [6:0]  t_cell = {t_dy[7:5], t_dx[8:5]};
    wire [10:0] t_ox   = TX + {2'b00, t_dx[8:5], 5'b0};
    wire [10:0] t_oy   = TY + {3'b000, t_dy[7:5], 5'b0};

    // the caret cell shows a ghost of the rune the highlighted key would type
    wire        t_is_caret = (t_cell == caret);
    wire [9:0]  t_code = (t_is_caret && cur_typeable) ? cur_code : tbuf[t_cell];
    wire        t_ok_n = (t_code != 10'h3FF) && (t_code < GLYPHS);

    reg t_in_r = 1'b0, t_caret_r = 1'b0, t_ok_r = 1'b0;
    always @(posedge clk_pixel) begin
        t_in_r    <= t_in_n;
        t_caret_r <= t_is_caret;
        t_ok_r    <= t_ok_n;
    end

    localparam [23:0] COL_TBG   = 24'hFFFFFF;
    localparam [23:0] COL_CARET = 24'hF6DDD2;

    wire        text_view;
    wire [7:0]  text_r, text_g, text_b;
    rune_draw #(.SCALE(2)) text_i (
        .clk      (clk_pixel),
        .code     (t_code),
        .px       (h_cnt),
        .py       (v_cnt),
        .origin_x (t_ox),
        .origin_y (t_oy),
        .bg_rgb   (t_caret_r ? COL_CARET : COL_TBG),
        .rom_addr (rom_addr_prev),
        .rom_data (rom_data_prev),
        .in_view  (text_view),
        .out_r    (text_r),
        .out_g    (text_g),
        .out_b    (text_b)
    );
    wire [23:0] text_bg  = t_caret_r ? COL_CARET : COL_TBG;
    wire [23:0] text_rgb = (text_view && t_ok_r) ? {text_r, text_g, text_b} : text_bg;

    // ---------- shared key-glyph renderer (legend comes from the keymap ROM) ----------
    // The glyph sits inside the key: 1 px in on the function row, 2 px elsewhere.
    wire [10:0] g_ox = k_x + (in_func_key ? 11'd1 : 11'd2);
    wire [10:0] g_oy = k_y;

    wire        key_rune_in;
    wire [7:0]  key_rune_r, key_rune_g, key_rune_b;
    rune_draw #(.SCALE(1)) key_rune_i (
        .clk      (clk_pixel),
        .code     (beam_code),
        .px       (kx),
        .py       (ky),
        .origin_x (g_ox),
        .origin_y (g_oy),
        .bg_rgb   (is_selected ? COL_HI : COL_KEY),
        .rom_addr (rom_addr_key),
        .rom_data (rom_data_key),
        .in_view  (key_rune_in),
        .out_r    (key_rune_r),
        .out_g    (key_rune_g),
        .out_b    (key_rune_b)
    );
    wire show_key_glyph = in_any_key && key_rune_in && beam_code_ok;

    // ---------- final pixel ----------
    wire [23:0] pix_rgb =
        t_in_r         ? text_rgb :
        show_key_glyph ? {key_rune_r, key_rune_g, key_rune_b} :
        led_hit        ? led_col :
        is_selected    ? COL_HI  :
        in_any_key     ? COL_KEY :
                         COL_BG;

    wire [7:0] pix_r = pix_rgb[23:16];
    wire [7:0] pix_g = pix_rgb[15:8];
    wire [7:0] pix_b = pix_rgb[7:0];

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