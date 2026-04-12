// BNN Core — 4-MAC serialized compute engine
// Processes the full 2-layer BNN with skip connection:
//   Layer 1: 64 neurons, 144 pixel inputs → 64 binary hidden activations
//   Layer 2: 64 neurons, 208 inputs (64 hidden + 144 pixels) → 64 binary activations
//   Output:  10 neurons, 64 inputs → 10 class scores → argmax → prediction
//
// Architecture: 4 neurons computed in parallel, inputs processed serially
// All thresholds are 0 → activation = (acc > 0) ? +1 : -1
module bnn_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ena,
    // Pixel loading
    input  wire [7:0]  pixel_data,    // 4 packed 2-bit pixels per cycle
    input  wire        data_valid,    // high when pixel_data is valid
    // Control
    input  wire        start,         // pulse to begin inference
    // Output
    output reg  [3:0]  prediction,    // predicted digit 0-9
    output reg         busy,
    output reg         result_valid
);

    // ========================================================
    // State Machine
    // ========================================================
    localparam S_IDLE    = 3'd0;
    localparam S_LOAD    = 3'd1;
    localparam S_LAYER1  = 3'd2;
    localparam S_LAYER2  = 3'd3;
    localparam S_OUTPUT  = 3'd4;
    localparam S_ARGMAX  = 3'd5;
    localparam S_DONE    = 3'd6;

    reg [2:0] state;

    // ========================================================
    // Counters
    // ========================================================
    reg [5:0] neuron_base;    // base neuron index (0, 4, 8, ..., 60 for L1/L2; 0,4,8 for output)
    reg [7:0] input_idx;      // current input index (0-143 for L1, 0-207 for L2, 0-63 for output)
    reg [7:0] input_max;      // max input index for current layer

    // ========================================================
    // Input Buffer — 144 pixels × 2 bits
    // ========================================================
    reg [1:0] pixels [0:143];
    reg [5:0] load_ptr;

    // Pixel value LUT (combinational)
    wire signed [2:0] pixel_values [0:143];
    genvar gi;
    generate
        for (gi = 0; gi < 144; gi = gi + 1) begin : px_lut
            pixel_lut lut_inst (
                .code(pixels[gi]),
                .value(pixel_values[gi])
            );
        end
    endgenerate

    // ========================================================
    // Hidden Activations Storage
    // ========================================================
    reg h1 [0:63];     // layer 1 binary outputs: 1=positive, 0=negative
    reg h2 [0:63];     // layer 2 binary outputs

    // ========================================================
    // Weight ROM Access
    // ========================================================
    // 4 parallel weight lookups (one per MAC)
    wire signed [1:0] w0, w1, w2, w3;

    // Neuron indices for the 4 parallel MACs
    wire [5:0] n0 = neuron_base;
    wire [5:0] n1 = neuron_base + 6'd1;
    wire [5:0] n2 = neuron_base + 6'd2;
    wire [5:0] n3 = neuron_base + 6'd3;

    // Layer 1 weight ROMs
    wire signed [1:0] w_l1_0, w_l1_1, w_l1_2, w_l1_3;
    weight_rom_l1 wrom_l1_0 (.neuron_idx(n0), .input_idx(input_idx), .weight(w_l1_0));
    weight_rom_l1 wrom_l1_1 (.neuron_idx(n1), .input_idx(input_idx), .weight(w_l1_1));
    weight_rom_l1 wrom_l1_2 (.neuron_idx(n2), .input_idx(input_idx), .weight(w_l1_2));
    weight_rom_l1 wrom_l1_3 (.neuron_idx(n3), .input_idx(input_idx), .weight(w_l1_3));

    // Layer 2 weight ROMs
    wire signed [1:0] w_l2_0, w_l2_1, w_l2_2, w_l2_3;
    weight_rom_l2 wrom_l2_0 (.neuron_idx(n0), .input_idx(input_idx), .weight(w_l2_0));
    weight_rom_l2 wrom_l2_1 (.neuron_idx(n1), .input_idx(input_idx), .weight(w_l2_1));
    weight_rom_l2 wrom_l2_2 (.neuron_idx(n2), .input_idx(input_idx), .weight(w_l2_2));
    weight_rom_l2 wrom_l2_3 (.neuron_idx(n3), .input_idx(input_idx), .weight(w_l2_3));

    // Output weight ROMs
    wire signed [1:0] w_out_0, w_out_1, w_out_2, w_out_3;
    wire [3:0] n0_out = neuron_base[3:0];
    wire [3:0] n1_out = neuron_base[3:0] + 4'd1;
    wire [3:0] n2_out = neuron_base[3:0] + 4'd2;
    wire [3:0] n3_out = neuron_base[3:0] + 4'd3;
    weight_rom_out wrom_out_0 (.neuron_idx(n0_out), .input_idx(input_idx[6:0]), .weight(w_out_0));
    weight_rom_out wrom_out_1 (.neuron_idx(n1_out), .input_idx(input_idx[6:0]), .weight(w_out_1));
    weight_rom_out wrom_out_2 (.neuron_idx(n2_out), .input_idx(input_idx[6:0]), .weight(w_out_2));
    weight_rom_out wrom_out_3 (.neuron_idx(n3_out), .input_idx(input_idx[6:0]), .weight(w_out_3));

    // Select weights based on current layer
    assign w0 = (state == S_LAYER1) ? w_l1_0 : (state == S_LAYER2) ? w_l2_0 : w_out_0;
    assign w1 = (state == S_LAYER1) ? w_l1_1 : (state == S_LAYER2) ? w_l2_1 : w_out_1;
    assign w2 = (state == S_LAYER1) ? w_l1_2 : (state == S_LAYER2) ? w_l2_2 : w_out_2;
    assign w3 = (state == S_LAYER1) ? w_l1_3 : (state == S_LAYER2) ? w_l2_3 : w_out_3;

    // ========================================================
    // Input Value Mux — select current input value
    // ========================================================
    // For Layer 1: input is pixel value (3-bit signed, -3 to +3)
    // For Layer 2: input 0-63 is h1 (±1), input 64-207 is pixel (±3)
    // For Output:  input is h2 (±1)
    reg signed [2:0] current_input;

    always @(*) begin
        current_input = 3'sd0;
        case (state)
            S_LAYER1: begin
                current_input = pixel_values[input_idx];
            end
            S_LAYER2: begin
                if (input_idx < 8'd64) begin
                    // Hidden activation from layer 1: +1 or -1
                    current_input = h1[input_idx[5:0]] ? 3'sd1 : -3'sd1;
                end else begin
                    // Pixel value (skip connection)
                    current_input = pixel_values[input_idx - 8'd64];
                end
            end
            S_OUTPUT: begin
                // Hidden activation from layer 2: +1 or -1
                current_input = h2[input_idx[5:0]] ? 3'sd1 : -3'sd1;
            end
            default: current_input = 3'sd0;
        endcase
    end

    // ========================================================
    // 4 Accumulators (11-bit signed for ±511 range)
    // ========================================================
    reg signed [10:0] acc [0:3];

    // Ternary MAC: weight × input (no multiplier, just conditional add/sub)
    function signed [10:0] ternary_mac;
        input signed [10:0] accumulator;
        input signed [1:0]  weight;
        input signed [2:0]  inp;
        begin
            case (weight)
                2'sd1:  ternary_mac = accumulator + {{8{inp[2]}}, inp};
                -2'sd1: ternary_mac = accumulator - {{8{inp[2]}}, inp};
                default: ternary_mac = accumulator;
            endcase
        end
    endfunction

    // ========================================================
    // Output Score Storage
    // ========================================================
    reg signed [7:0] scores [0:9];

    // Argmax
    wire [3:0] argmax_result;
    argmax argmax_inst (
        .s0(scores[0]), .s1(scores[1]), .s2(scores[2]), .s3(scores[3]), .s4(scores[4]),
        .s5(scores[5]), .s6(scores[6]), .s7(scores[7]), .s8(scores[8]), .s9(scores[9]),
        .max_idx(argmax_result)
    );

    // ========================================================
    // Main State Machine & Datapath
    // ========================================================
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            busy <= 1'b0;
            result_valid <= 1'b0;
            prediction <= 4'd0;
            load_ptr <= 6'd0;
            neuron_base <= 6'd0;
            input_idx <= 8'd0;
            input_max <= 8'd0;
            for (i = 0; i < 4; i = i + 1) acc[i] <= 11'sd0;
            for (i = 0; i < 64; i = i + 1) begin h1[i] <= 1'b0; h2[i] <= 1'b0; end
            for (i = 0; i < 10; i = i + 1) scores[i] <= 8'sd0;
        end else if (ena) begin
            case (state)

                // ---- IDLE: Wait for data or start ----
                S_IDLE: begin
                    result_valid <= 1'b0;
                    if (data_valid) begin
                        state <= S_LOAD;
                        busy <= 1'b1;
                        load_ptr <= 6'd0;
                        // Load first batch of pixels
                        pixels[0] <= pixel_data[7:6];
                        pixels[1] <= pixel_data[5:4];
                        pixels[2] <= pixel_data[3:2];
                        pixels[3] <= pixel_data[1:0];
                        load_ptr <= 6'd1;
                    end else if (start) begin
                        // Start computation (pixels already loaded)
                        state <= S_LAYER1;
                        busy <= 1'b1;
                        neuron_base <= 6'd0;
                        input_idx <= 8'd0;
                        input_max <= 8'd143;
                        for (i = 0; i < 4; i = i + 1) acc[i] <= 11'sd0;
                    end
                end

                // ---- LOAD: Receive pixels serially ----
                S_LOAD: begin
                    if (data_valid) begin
                        pixels[{load_ptr, 2'b00}] <= pixel_data[7:6];
                        pixels[{load_ptr, 2'b01}] <= pixel_data[5:4];
                        pixels[{load_ptr, 2'b10}] <= pixel_data[3:2];
                        pixels[{load_ptr, 2'b11}] <= pixel_data[1:0];
                        load_ptr <= load_ptr + 1;
                        if (load_ptr == 6'd35) begin
                            // All 144 pixels loaded, start computing
                            state <= S_LAYER1;
                            neuron_base <= 6'd0;
                            input_idx <= 8'd0;
                            input_max <= 8'd143;
                            for (i = 0; i < 4; i = i + 1) acc[i] <= 11'sd0;
                        end
                    end else begin
                        // data_valid dropped — wait or allow start
                        if (start) begin
                            state <= S_LAYER1;
                            neuron_base <= 6'd0;
                            input_idx <= 8'd0;
                            input_max <= 8'd143;
                            for (i = 0; i < 4; i = i + 1) acc[i] <= 11'sd0;
                        end
                    end
                end

                // ---- LAYER 1: 64 neurons × 144 inputs ----
                S_LAYER1: begin
                    // Accumulate: 4 MACs in parallel
                    acc[0] <= ternary_mac(acc[0], w0, current_input);
                    acc[1] <= ternary_mac(acc[1], w1, current_input);
                    acc[2] <= ternary_mac(acc[2], w2, current_input);
                    acc[3] <= ternary_mac(acc[3], w3, current_input);

                    if (input_idx == input_max) begin
                        // Done with this batch of 4 neurons
                        // Apply activation: h = (acc > 0) ? 1 : 0
                        // (all thresholds are 0, strict >)
                        // Note: we store 1 for positive, 0 for non-positive
                        // acc values are available NEXT cycle, so we use current acc + last MAC
                        h1[neuron_base]     <= (ternary_mac(acc[0], w0, current_input) > 11'sd0);
                        h1[neuron_base + 1] <= (ternary_mac(acc[1], w1, current_input) > 11'sd0);
                        h1[neuron_base + 2] <= (ternary_mac(acc[2], w2, current_input) > 11'sd0);
                        h1[neuron_base + 3] <= (ternary_mac(acc[3], w3, current_input) > 11'sd0);

                        if (neuron_base == 6'd60) begin
                            // All 64 neurons done → move to layer 2
                            state <= S_LAYER2;
                            neuron_base <= 6'd0;
                            input_idx <= 8'd0;
                            input_max <= 8'd207;
                        end else begin
                            neuron_base <= neuron_base + 6'd4;
                            input_idx <= 8'd0;
                        end
                        // Clear accumulators for next batch
                        for (i = 0; i < 4; i = i + 1) acc[i] <= 11'sd0;
                    end else begin
                        input_idx <= input_idx + 8'd1;
                    end
                end

                // ---- LAYER 2: 64 neurons × 208 inputs (skip connection) ----
                S_LAYER2: begin
                    acc[0] <= ternary_mac(acc[0], w0, current_input);
                    acc[1] <= ternary_mac(acc[1], w1, current_input);
                    acc[2] <= ternary_mac(acc[2], w2, current_input);
                    acc[3] <= ternary_mac(acc[3], w3, current_input);

                    if (input_idx == input_max) begin
                        h2[neuron_base]     <= (ternary_mac(acc[0], w0, current_input) > 11'sd0);
                        h2[neuron_base + 1] <= (ternary_mac(acc[1], w1, current_input) > 11'sd0);
                        h2[neuron_base + 2] <= (ternary_mac(acc[2], w2, current_input) > 11'sd0);
                        h2[neuron_base + 3] <= (ternary_mac(acc[3], w3, current_input) > 11'sd0);

                        if (neuron_base == 6'd60) begin
                            // All 64 neurons done → move to output
                            state <= S_OUTPUT;
                            neuron_base <= 6'd0;
                            input_idx <= 8'd0;
                            input_max <= 8'd63;
                        end else begin
                            neuron_base <= neuron_base + 6'd4;
                            input_idx <= 8'd0;
                        end
                        for (i = 0; i < 4; i = i + 1) acc[i] <= 11'sd0;
                    end else begin
                        input_idx <= input_idx + 8'd1;
                    end
                end

                // ---- OUTPUT: 10 neurons × 64 inputs ----
                S_OUTPUT: begin
                    acc[0] <= ternary_mac(acc[0], w0, current_input);
                    acc[1] <= ternary_mac(acc[1], w1, current_input);
                    acc[2] <= ternary_mac(acc[2], w2, current_input);
                    acc[3] <= ternary_mac(acc[3], w3, current_input);

                    if (input_idx == input_max) begin
                        // Store scores (clamp to 8-bit signed: ±127)
                        // Only store valid neurons (last batch may have <4 valid)
                        if (neuron_base < 6'd10) begin
                            scores[neuron_base[3:0]] <= clamp8(ternary_mac(acc[0], w0, current_input));
                        end
                        if (neuron_base + 1 < 6'd10) begin
                            scores[neuron_base[3:0] + 4'd1] <= clamp8(ternary_mac(acc[1], w1, current_input));
                        end
                        if (neuron_base + 2 < 6'd10) begin
                            scores[neuron_base[3:0] + 4'd2] <= clamp8(ternary_mac(acc[2], w2, current_input));
                        end
                        if (neuron_base + 3 < 6'd10) begin
                            scores[neuron_base[3:0] + 4'd3] <= clamp8(ternary_mac(acc[3], w3, current_input));
                        end

                        if (neuron_base >= 6'd8) begin
                            // All 10 output neurons done (batches: 0-3, 4-7, 8-11 with 10,11 unused)
                            state <= S_ARGMAX;
                        end else begin
                            neuron_base <= neuron_base + 6'd4;
                            input_idx <= 8'd0;
                        end
                        for (i = 0; i < 4; i = i + 1) acc[i] <= 11'sd0;
                    end else begin
                        input_idx <= input_idx + 8'd1;
                    end
                end

                // ---- ARGMAX: Read combinational argmax result ----
                S_ARGMAX: begin
                    prediction <= argmax_result;
                    state <= S_DONE;
                end

                // ---- DONE: Output result ----
                S_DONE: begin
                    result_valid <= 1'b1;
                    busy <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

    // Clamp 11-bit signed to 8-bit signed (±127)
    function signed [7:0] clamp8;
        input signed [10:0] val;
        begin
            if (val > 11'sd127)
                clamp8 = 8'sd127;
            else if (val < -11'sd127)
                clamp8 = -8'sd127;
            else
                clamp8 = val[7:0];
        end
    endfunction

endmodule
