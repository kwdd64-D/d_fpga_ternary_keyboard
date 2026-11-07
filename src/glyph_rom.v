// glyph_rom.v — the one and only copy of the glyph art, 2 bits per pixel
//
// Word = ink level 0..3. Address = {code[9:0], y[4:0], x[4:0]}, i.e. 1024
// words per 32x32 glyph. The file is built by tools/build_glyphs.py.
//
// GLYPHS must match --count given to build_glyphs.py. Raise it as you add
// sheets (up to 726 for the full tryte set = about 181 KB of block RAM).
//
// Two independent read ports (A = key glyphs, B = large preview).
// Output is registered: data appears one clock after the address.
module glyph_rom #(
    parameter GLYPHS = 32,
    parameter FILE   = "glyphs2.hex"
) (
    input  wire        clk,
    input  wire [19:0] addr_a,
    output reg  [1:0]  data_a,
    input  wire [19:0] addr_b,
    output reg  [1:0]  data_b
);
    reg [1:0] mem [0:GLYPHS*1024-1];
    initial $readmemh(FILE, mem);

    always @(posedge clk) begin
        data_a <= mem[addr_a];
        data_b <= mem[addr_b];
    end
endmodule
