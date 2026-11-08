// rune_digits.v — scale-aware digit renderer
// SCALE=8 → 256×256 preview
// SCALE=1 → 16×16 glyph (32×32 art sampled every 2nd pixel) that fits inside a key
module rune_digits #(
    parameter SCALE = 8
) (
    input  wire        clk,
    input  wire [3:0]  digit,
    input  wire [10:0] px,
    input  wire [10:0] py,
    input  wire [10:0] origin_x,
    input  wire [10:0] origin_y,
    input  wire [23:0] bg_rgb,
    output wire        in_view,
    output wire [7:0]  out_r,
    output wire [7:0]  out_g,
    output wire [7:0]  out_b
);
    // On-screen size of the glyph box
    localparam VIEW = (SCALE == 8) ? 256 : 16;

    // Look up the NEXT pixel so the registered result lines up with the
    // current pixel (removes the 1 px shift).
    wire [10:0] nx    = px + 11'd1;
    wire [10:0] rel_x = nx - origin_x;
    wire [10:0] rel_y = py - origin_y;

    wire in_view_next = (nx >= origin_x) && (nx < origin_x + VIEW) &&
                        (py >= origin_y) && (py < origin_y + VIEW);

    // SCALE=8: 8x upscale of 32x32 art. Otherwise: 2x downsample to 16x16.
    wire [4:0] src_x = (SCALE == 8) ? rel_x[7:3] : {rel_x[3:0], 1'b0};
    wire [4:0] src_y = (SCALE == 8) ? rel_y[7:3] : {rel_y[3:0], 1'b0};

    wire [13:0] addr = {digit, src_y, src_x};

    reg [7:0] mem [0:10239];
    initial $readmemh("digits.hex", mem);

    reg [7:0] coverage   = 0;
    reg       in_view_r  = 0;
    always @(posedge clk) begin
        in_view_r <= in_view_next;
        if (in_view_next)
            coverage <= mem[addr];
        else
            coverage <= 8'd0;
    end

    assign in_view = in_view_r;

    wire [7:0] glyph     = 8'd255 - coverage;
    wire       use_glyph = (coverage > 8'd16);

    assign out_r = (in_view_r && use_glyph) ? glyph : bg_rgb[23:16];
    assign out_g = (in_view_r && use_glyph) ? glyph : bg_rgb[15:8];
    assign out_b = (in_view_r && use_glyph) ? glyph : bg_rgb[7:0];
endmodule