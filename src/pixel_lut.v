// Pixel value lookup table
// Converts 2-bit quantization codes to signed integer values
// Code: {0,1,2,3} → Value: {-3,-1,+1,+3}
module pixel_lut (
    input  wire [1:0]        code,
    output reg  signed [2:0] value  // 3-bit signed: range -3 to +3
);
    always @(*) begin
        case (code)
            2'd0: value = -3'sd3;
            2'd1: value = -3'sd1;
            2'd2: value =  3'sd1;
            2'd3: value =  3'sd3;
        endcase
    end
endmodule
