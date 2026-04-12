// 10-way argmax — finds the class with the highest score
// Combinational: produces result in a single cycle
// Uses flat ports since Yosys doesn't support unpacked array ports
module argmax (
    input  wire signed [7:0] s0, s1, s2, s3, s4, s5, s6, s7, s8, s9,
    output reg  [3:0]        max_idx
);
    reg signed [7:0] max_val;

    always @(*) begin
        max_val = s0;
        max_idx = 4'd0;
        if (s1 > max_val) begin max_val = s1; max_idx = 4'd1; end
        if (s2 > max_val) begin max_val = s2; max_idx = 4'd2; end
        if (s3 > max_val) begin max_val = s3; max_idx = 4'd3; end
        if (s4 > max_val) begin max_val = s4; max_idx = 4'd4; end
        if (s5 > max_val) begin max_val = s5; max_idx = 4'd5; end
        if (s6 > max_val) begin max_val = s6; max_idx = 4'd6; end
        if (s7 > max_val) begin max_val = s7; max_idx = 4'd7; end
        if (s8 > max_val) begin max_val = s8; max_idx = 4'd8; end
        if (s9 > max_val) begin max_val = s9; max_idx = 4'd9; end
    end
endmodule
