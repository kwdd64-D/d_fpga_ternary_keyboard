// rune_draw.v — glyph renderer with NO memory of its own
// It computes the ROM address for the next pixel and turns the 2-bit ROM
// data (supplied by glyph_rom) into a colour.
// SCALE=8 → 256x256 preview (8x upscale of the 32x32 art)
// SCALE=1 → 16x16 glyph (32x32 art sampled every 2nd pixel), fits inside a key
module rune_draw #(
    parameter SCALE = 8
) (
    input  wire        clk,
    input  wire [9:0]  code,        // glyph number, 0..725
    input  wire [10:0] px,
    input  wire [10:0] py,
    input  wire [10:0] origin_x,
    input  wire [10:0] origin_y,
    input  wire [23:0] bg_rgb,

    // connection to glyph_rom
    output wire [19:0] rom_addr,
    input  wire [1:0]  rom_data,

    output wire        in_view,
    output wire [7:0]  out_r,
    output wire [7:0]  out_g,
    output wire [7:0]  out_b
);
    localparam VIEW = (SCALE == 8) ? 256 : 16;

    // Look up the NEXT pixel so the registered ROM data lines up with the
    // current pixel.
    wire [10:0] nx    = px + 11'd1;
    wire [10:0] rel_x = nx - origin_x;
    wire [10:0] rel_y = py - origin_y;

    wire in_view_next = (nx >= origin_x) && (nx < origin_x + VIEW) &&
                        (py >= origin_y) && (py < origin_y + VIEW);

    wire [4:0] src_x = (SCALE == 8) ? rel_x[7:3] : {rel_x[3:0], 1'b0};
    wire [4:0] src_y = (SCALE == 8) ? rel_y[7:3] : {rel_y[3:0], 1'b0};

    assign rom_addr = {code, src_y, src_x};

    reg in_view_r = 0;
    always @(posedge clk) in_view_r <= in_view_next;
    assign in_view = in_view_r;

    // 2-bit level -> 8-bit coverage (0, 85, 170, 255). 85 = 64 + 16 + 4 + 1.
    wire [7:0] cov_full  = {rom_data, 6'b0} + {2'b0, rom_data, 4'b0} +
                           {4'b0, rom_data, 2'b0} + {6'b0, rom_data};
    wire [7:0] coverage  = in_view_r ? cov_full : 8'd0;
    wire [7:0] glyph     = 8'd255 - coverage;
    wire       use_glyph = (coverage > 8'd16);

    assign out_r = use_glyph ? glyph : bg_rgb[23:16];
    assign out_g = use_glyph ? glyph : bg_rgb[15:8];
    assign out_b = use_glyph ? glyph : bg_rgb[7:0];
endmodule
