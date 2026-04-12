// Auto-generated — per-neuron bitfield weight ROM
// 10 neurons x 64 inputs
// Decomposed: case(neuron) -> 64-bit constant, then constant[input_idx]
// Non-zero: 465/640 (72.7%)
module weight_rom_out (
    input  wire [3:0] neuron_base,
    input  wire [5:0]  input_idx,
    output wire signed [1:0] w0, w1, w2, w3
);

    // +1 weight patterns per neuron
    reg [63:0] pos0, pos1, pos2, pos3;

    // -1 weight patterns per neuron
    reg [63:0] neg0, neg1, neg2, neg3;

    // Tap 0: neuron_base + 0
    always @(*) begin
        case (neuron_base + 4'd0)
            4'd0: begin pos0 = 64'h710ca3cfc91927d0; neg0 = 64'h8a62502014e08026; end
            4'd1: begin pos0 = 64'h1f381888004d2b1e; neg0 = 64'h60048320e9104400; end
            4'd2: begin pos0 = 64'hfea5142820bb3019; neg0 = 64'h011aa384580080c2; end
            4'd3: begin pos0 = 64'h2cd8156234b30d8e; neg0 = 64'h43024a8cc8482201; end
            4'd4: begin pos0 = 64'h09527b8c8ce5e348; neg0 = 64'h56a8044353020894; end
            4'd5: begin pos0 = 64'ha02740d569b0aee6; neg0 = 64'h5d401d2880415118; end
            4'd6: begin pos0 = 64'hd022a0c5a9487a5b; neg0 = 64'h0cd8122a10a701a0; end
            4'd7: begin pos0 = 64'h29504fcad50bc5a3; neg0 = 64'h5025b00428202a4c; end
            4'd8: begin pos0 = 64'h3834014de1e1ebbe; neg0 = 64'hc7c20680160a1040; end
            4'd9: begin pos0 = 64'h07cd2b6c4d2542e2; neg0 = 64'h40001083901a3c15; end
            default: begin pos0 = 64'd0; neg0 = 64'd0; end
        endcase
    end

    // Tap 1: neuron_base + 1
    always @(*) begin
        case (neuron_base + 4'd1)
            4'd0: begin pos1 = 64'h710ca3cfc91927d0; neg1 = 64'h8a62502014e08026; end
            4'd1: begin pos1 = 64'h1f381888004d2b1e; neg1 = 64'h60048320e9104400; end
            4'd2: begin pos1 = 64'hfea5142820bb3019; neg1 = 64'h011aa384580080c2; end
            4'd3: begin pos1 = 64'h2cd8156234b30d8e; neg1 = 64'h43024a8cc8482201; end
            4'd4: begin pos1 = 64'h09527b8c8ce5e348; neg1 = 64'h56a8044353020894; end
            4'd5: begin pos1 = 64'ha02740d569b0aee6; neg1 = 64'h5d401d2880415118; end
            4'd6: begin pos1 = 64'hd022a0c5a9487a5b; neg1 = 64'h0cd8122a10a701a0; end
            4'd7: begin pos1 = 64'h29504fcad50bc5a3; neg1 = 64'h5025b00428202a4c; end
            4'd8: begin pos1 = 64'h3834014de1e1ebbe; neg1 = 64'hc7c20680160a1040; end
            4'd9: begin pos1 = 64'h07cd2b6c4d2542e2; neg1 = 64'h40001083901a3c15; end
            default: begin pos1 = 64'd0; neg1 = 64'd0; end
        endcase
    end

    // Tap 2: neuron_base + 2
    always @(*) begin
        case (neuron_base + 4'd2)
            4'd0: begin pos2 = 64'h710ca3cfc91927d0; neg2 = 64'h8a62502014e08026; end
            4'd1: begin pos2 = 64'h1f381888004d2b1e; neg2 = 64'h60048320e9104400; end
            4'd2: begin pos2 = 64'hfea5142820bb3019; neg2 = 64'h011aa384580080c2; end
            4'd3: begin pos2 = 64'h2cd8156234b30d8e; neg2 = 64'h43024a8cc8482201; end
            4'd4: begin pos2 = 64'h09527b8c8ce5e348; neg2 = 64'h56a8044353020894; end
            4'd5: begin pos2 = 64'ha02740d569b0aee6; neg2 = 64'h5d401d2880415118; end
            4'd6: begin pos2 = 64'hd022a0c5a9487a5b; neg2 = 64'h0cd8122a10a701a0; end
            4'd7: begin pos2 = 64'h29504fcad50bc5a3; neg2 = 64'h5025b00428202a4c; end
            4'd8: begin pos2 = 64'h3834014de1e1ebbe; neg2 = 64'hc7c20680160a1040; end
            4'd9: begin pos2 = 64'h07cd2b6c4d2542e2; neg2 = 64'h40001083901a3c15; end
            default: begin pos2 = 64'd0; neg2 = 64'd0; end
        endcase
    end

    // Tap 3: neuron_base + 3
    always @(*) begin
        case (neuron_base + 4'd3)
            4'd0: begin pos3 = 64'h710ca3cfc91927d0; neg3 = 64'h8a62502014e08026; end
            4'd1: begin pos3 = 64'h1f381888004d2b1e; neg3 = 64'h60048320e9104400; end
            4'd2: begin pos3 = 64'hfea5142820bb3019; neg3 = 64'h011aa384580080c2; end
            4'd3: begin pos3 = 64'h2cd8156234b30d8e; neg3 = 64'h43024a8cc8482201; end
            4'd4: begin pos3 = 64'h09527b8c8ce5e348; neg3 = 64'h56a8044353020894; end
            4'd5: begin pos3 = 64'ha02740d569b0aee6; neg3 = 64'h5d401d2880415118; end
            4'd6: begin pos3 = 64'hd022a0c5a9487a5b; neg3 = 64'h0cd8122a10a701a0; end
            4'd7: begin pos3 = 64'h29504fcad50bc5a3; neg3 = 64'h5025b00428202a4c; end
            4'd8: begin pos3 = 64'h3834014de1e1ebbe; neg3 = 64'hc7c20680160a1040; end
            4'd9: begin pos3 = 64'h07cd2b6c4d2542e2; neg3 = 64'h40001083901a3c15; end
            default: begin pos3 = 64'd0; neg3 = 64'd0; end
        endcase
    end

    assign w0 = pos0[input_idx] ? 2'sd1 : neg0[input_idx] ? -2'sd1 : 2'sd0;
    assign w1 = pos1[input_idx] ? 2'sd1 : neg1[input_idx] ? -2'sd1 : 2'sd0;
    assign w2 = pos2[input_idx] ? 2'sd1 : neg2[input_idx] ? -2'sd1 : 2'sd0;
    assign w3 = pos3[input_idx] ? 2'sd1 : neg3[input_idx] ? -2'sd1 : 2'sd0;

endmodule
