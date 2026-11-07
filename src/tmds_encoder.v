module tmds_encoder (
    input  wire       clk,
    input  wire [7:0] data,
    input  wire [1:0] c,
    input  wire       blank,
    output reg  [9:0] encoded
);
    // Stage 1: transition minimizing (XOR/XNOR chain)
    wire [3:0] ones_d = data[0] + data[1] + data[2] + data[3]
                      + data[4] + data[5] + data[6] + data[7];
    wire use_xnor = (ones_d > 4) || (ones_d == 4 && !data[0]);

    wire [8:0] q_m;
    assign q_m[0] = data[0];
    assign q_m[1] = use_xnor ? ~(q_m[0] ^ data[1]) : (q_m[0] ^ data[1]);
    assign q_m[2] = use_xnor ? ~(q_m[1] ^ data[2]) : (q_m[1] ^ data[2]);
    assign q_m[3] = use_xnor ? ~(q_m[2] ^ data[3]) : (q_m[2] ^ data[3]);
    assign q_m[4] = use_xnor ? ~(q_m[3] ^ data[4]) : (q_m[3] ^ data[4]);
    assign q_m[5] = use_xnor ? ~(q_m[4] ^ data[5]) : (q_m[4] ^ data[5]);
    assign q_m[6] = use_xnor ? ~(q_m[5] ^ data[6]) : (q_m[5] ^ data[6]);
    assign q_m[7] = use_xnor ? ~(q_m[6] ^ data[7]) : (q_m[6] ^ data[7]);
    assign q_m[8] = ~use_xnor;

    // Stage 2: DC balancing
    wire [3:0] ones_q = q_m[0] + q_m[1] + q_m[2] + q_m[3]
                      + q_m[4] + q_m[5] + q_m[6] + q_m[7];
    wire signed [5:0] diff = 2 * ones_q - 8;      // ones minus zeros
    reg  signed [5:0] cnt  = 0;

    always @(posedge clk) begin
        if (blank) begin
            case (c)
                2'b00: encoded <= 10'b1101010100;
                2'b01: encoded <= 10'b0010101011;
                2'b10: encoded <= 10'b0101010100;
                2'b11: encoded <= 10'b1010101011;
            endcase
            cnt <= 0;
        end else if (cnt == 0 || ones_q == 4) begin
            encoded <= {~q_m[8], q_m[8], q_m[8] ? q_m[7:0] : ~q_m[7:0]};
            cnt <= q_m[8] ? cnt + diff : cnt - diff;
        end else if ((cnt > 0 && ones_q > 4) || (cnt < 0 && ones_q < 4)) begin
            encoded <= {1'b1, q_m[8], ~q_m[7:0]};
            cnt <= cnt + (q_m[8] ? 6'sd2 : 6'sd0) - diff;
        end else begin
            encoded <= {1'b0, q_m[8], q_m[7:0]};
            cnt <= cnt - (q_m[8] ? 6'sd0 : 6'sd2) + diff;
        end
    end
endmodule