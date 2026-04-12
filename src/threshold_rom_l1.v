// Auto-generated from weights.json
// All thresholds zero: True
module threshold_rom_l1 (
    input  wire [5:0] neuron_idx,
    output wire signed [10:0] threshold
);
    // All thresholds are 0 — comparison reduces to sign check
    assign threshold = 11'sd0;
endmodule
