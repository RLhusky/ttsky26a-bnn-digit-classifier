// 10-way argmax — finds the class with the highest score
// Combinational: produces result in a single cycle
module argmax (
    input  wire signed [7:0] scores [0:9],  // 10 class scores (8-bit signed)
    output reg  [3:0]        max_idx        // winning class (0-9)
);
    reg signed [7:0] max_val;
    integer i;

    always @(*) begin
        max_val = scores[0];
        max_idx = 4'd0;
        for (i = 1; i < 10; i = i + 1) begin
            if (scores[i] > max_val) begin
                max_val = scores[i];
                max_idx = i[3:0];
            end
        end
    end
endmodule
