// Auto-generated — per-neuron weight ROM (1-MAC, single output)
// 10 neurons x 64 inputs
// Non-zero: 465/640 (72.7%)
module weight_rom_out (
    input  wire [3:0] neuron_idx,
    input  wire [5:0]  input_idx,
    output wire signed [1:0] weight
);

    reg [63:0] pos, neg;

    // +1 weight patterns per neuron
    always @(*) begin
        case (neuron_idx)
            4'd0: pos = 64'h710ca3cfc91927d0;
            4'd1: pos = 64'h1f381888004d2b1e;
            4'd2: pos = 64'hfea5142820bb3019;
            4'd3: pos = 64'h2cd8156234b30d8e;
            4'd4: pos = 64'h09527b8c8ce5e348;
            4'd5: pos = 64'ha02740d569b0aee6;
            4'd6: pos = 64'hd022a0c5a9487a5b;
            4'd7: pos = 64'h29504fcad50bc5a3;
            4'd8: pos = 64'h3834014de1e1ebbe;
            4'd9: pos = 64'h07cd2b6c4d2542e2;
            default: pos = 64'd0;
        endcase
    end

    // -1 weight patterns per neuron
    always @(*) begin
        case (neuron_idx)
            4'd0: neg = 64'h8a62502014e08026;
            4'd1: neg = 64'h60048320e9104400;
            4'd2: neg = 64'h011aa384580080c2;
            4'd3: neg = 64'h43024a8cc8482201;
            4'd4: neg = 64'h56a8044353020894;
            4'd5: neg = 64'h5d401d2880415118;
            4'd6: neg = 64'h0cd8122a10a701a0;
            4'd7: neg = 64'h5025b00428202a4c;
            4'd8: neg = 64'hc7c20680160a1040;
            4'd9: neg = 64'h40001083901a3c15;
            default: neg = 64'd0;
        endcase
    end

    assign weight = pos[input_idx] ? 2'sd1 : neg[input_idx] ? -2'sd1 : 2'sd0;

endmodule
