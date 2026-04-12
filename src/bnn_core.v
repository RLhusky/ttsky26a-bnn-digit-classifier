// BNN Core — 4-MAC serialized compute engine (area-optimized)
//
// Key area optimizations vs v1:
// - 3 shared 4-way ROM modules (was 12 separate instances) → ~75% ROM area reduction
// - 1 pixel LUT instance (was 144 generate instances) → on-the-fly conversion
// - All thresholds are 0 → no threshold ROM needed, just sign check
//
// Architecture: 4 neurons in parallel, inputs processed serially
// ~5,900 clock cycles per inference at 10 MHz
module bnn_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ena,
    input  wire [7:0]  pixel_data,
    input  wire        data_valid,
    input  wire        start,
    output reg  [3:0]  prediction,
    output reg         busy,
    output reg         result_valid
);

    // ---- State Machine ----
    localparam S_IDLE    = 3'd0;
    localparam S_LOAD    = 3'd1;
    localparam S_LAYER1  = 3'd2;
    localparam S_LAYER2  = 3'd3;
    localparam S_OUTPUT  = 3'd4;
    localparam S_ARGMAX  = 3'd5;
    localparam S_DONE    = 3'd6;
    reg [2:0] state;

    // ---- Counters ----
    reg [5:0] neuron_base;
    reg [7:0] input_idx;
    reg [7:0] input_max;

    // ---- Pixel Storage (144 x 2-bit codes) ----
    reg [1:0] pixels [0:143];
    reg [5:0] load_ptr;

    // ---- Single pixel LUT (on-the-fly conversion) ----
    reg [1:0] current_pixel_code;
    wire signed [2:0] current_pixel_val;
    pixel_lut px_lut (.code(current_pixel_code), .value(current_pixel_val));

    // ---- Hidden Activations (1-bit each) ----
    reg h1 [0:63];
    reg h2 [0:63];

    // ---- Shared 4-way Weight ROMs (1 instance per layer, not 4!) ----
    wire signed [1:0] w0, w1, w2, w3;
    wire signed [1:0] w_l1_0, w_l1_1, w_l1_2, w_l1_3;
    wire signed [1:0] w_l2_0, w_l2_1, w_l2_2, w_l2_3;
    wire signed [1:0] w_out_0, w_out_1, w_out_2, w_out_3;

    weight_rom_l1 wrom_l1 (
        .neuron_base(neuron_base), .input_idx(input_idx),
        .w0(w_l1_0), .w1(w_l1_1), .w2(w_l1_2), .w3(w_l1_3)
    );
    weight_rom_l2 wrom_l2 (
        .neuron_base(neuron_base), .input_idx(input_idx),
        .w0(w_l2_0), .w1(w_l2_1), .w2(w_l2_2), .w3(w_l2_3)
    );
    weight_rom_out wrom_out (
        .neuron_base(neuron_base[3:0]), .input_idx(input_idx[6:0]),
        .w0(w_out_0), .w1(w_out_1), .w2(w_out_2), .w3(w_out_3)
    );

    // Select weights based on current layer
    assign w0 = (state == S_LAYER1) ? w_l1_0 : (state == S_LAYER2) ? w_l2_0 : w_out_0;
    assign w1 = (state == S_LAYER1) ? w_l1_1 : (state == S_LAYER2) ? w_l2_1 : w_out_1;
    assign w2 = (state == S_LAYER1) ? w_l1_2 : (state == S_LAYER2) ? w_l2_2 : w_out_2;
    assign w3 = (state == S_LAYER1) ? w_l1_3 : (state == S_LAYER2) ? w_l2_3 : w_out_3;

    // ---- Input Value Mux ----
    reg signed [2:0] current_input;

    always @(*) begin
        current_input = 3'sd0;
        current_pixel_code = 2'd0;
        case (state)
            S_LAYER1: begin
                current_pixel_code = pixels[input_idx];
                current_input = current_pixel_val;
            end
            S_LAYER2: begin
                if (input_idx < 8'd64) begin
                    current_input = h1[input_idx[5:0]] ? 3'sd1 : -3'sd1;
                end else begin
                    current_pixel_code = pixels[input_idx - 8'd64];
                    current_input = current_pixel_val;
                end
            end
            S_OUTPUT: begin
                current_input = h2[input_idx[5:0]] ? 3'sd1 : -3'sd1;
            end
            default: begin
                current_input = 3'sd0;
                current_pixel_code = 2'd0;
            end
        endcase
    end

    // ---- 4 Accumulators ----
    reg signed [10:0] acc [0:3];

    // Ternary MAC (no multiplier)
    function signed [10:0] tmac;
        input signed [10:0] a;
        input signed [1:0]  w;
        input signed [2:0]  x;
        begin
            case (w)
                2'sd1:   tmac = a + {{8{x[2]}}, x};
                -2'sd1:  tmac = a - {{8{x[2]}}, x};
                default: tmac = a;
            endcase
        end
    endfunction

    // ---- Output Scores ----
    reg signed [7:0] scores [0:9];

    // ---- Argmax ----
    wire [3:0] argmax_result;
    argmax argmax_inst (
        .s0(scores[0]), .s1(scores[1]), .s2(scores[2]), .s3(scores[3]), .s4(scores[4]),
        .s5(scores[5]), .s6(scores[6]), .s7(scores[7]), .s8(scores[8]), .s9(scores[9]),
        .max_idx(argmax_result)
    );

    // Clamp 11-bit → 8-bit signed
    function signed [7:0] clamp8;
        input signed [10:0] val;
        begin
            if (val > 11'sd127)       clamp8 = 8'sd127;
            else if (val < -11'sd127) clamp8 = -8'sd127;
            else                      clamp8 = val[7:0];
        end
    endfunction

    // ---- Main FSM + Datapath ----
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

                S_IDLE: begin
                    result_valid <= 1'b0;
                    if (data_valid) begin
                        state <= S_LOAD;
                        busy <= 1'b1;
                        pixels[0] <= pixel_data[7:6];
                        pixels[1] <= pixel_data[5:4];
                        pixels[2] <= pixel_data[3:2];
                        pixels[3] <= pixel_data[1:0];
                        load_ptr <= 6'd1;
                    end else if (start) begin
                        state <= S_LAYER1;
                        busy <= 1'b1;
                        neuron_base <= 6'd0;
                        input_idx <= 8'd0;
                        input_max <= 8'd143;
                        for (i = 0; i < 4; i = i + 1) acc[i] <= 11'sd0;
                    end
                end

                S_LOAD: begin
                    if (data_valid) begin
                        pixels[{load_ptr, 2'b00}] <= pixel_data[7:6];
                        pixels[{load_ptr, 2'b01}] <= pixel_data[5:4];
                        pixels[{load_ptr, 2'b10}] <= pixel_data[3:2];
                        pixels[{load_ptr, 2'b11}] <= pixel_data[1:0];
                        load_ptr <= load_ptr + 1;
                        if (load_ptr == 6'd35) begin
                            state <= S_LAYER1;
                            neuron_base <= 6'd0;
                            input_idx <= 8'd0;
                            input_max <= 8'd143;
                            for (i = 0; i < 4; i = i + 1) acc[i] <= 11'sd0;
                        end
                    end else if (start) begin
                        state <= S_LAYER1;
                        neuron_base <= 6'd0;
                        input_idx <= 8'd0;
                        input_max <= 8'd143;
                        for (i = 0; i < 4; i = i + 1) acc[i] <= 11'sd0;
                    end
                end

                S_LAYER1: begin
                    acc[0] <= tmac(acc[0], w0, current_input);
                    acc[1] <= tmac(acc[1], w1, current_input);
                    acc[2] <= tmac(acc[2], w2, current_input);
                    acc[3] <= tmac(acc[3], w3, current_input);

                    if (input_idx == input_max) begin
                        h1[neuron_base]     <= (tmac(acc[0], w0, current_input) > 11'sd0);
                        h1[neuron_base + 1] <= (tmac(acc[1], w1, current_input) > 11'sd0);
                        h1[neuron_base + 2] <= (tmac(acc[2], w2, current_input) > 11'sd0);
                        h1[neuron_base + 3] <= (tmac(acc[3], w3, current_input) > 11'sd0);

                        if (neuron_base == 6'd60) begin
                            state <= S_LAYER2;
                            neuron_base <= 6'd0;
                            input_idx <= 8'd0;
                            input_max <= 8'd207;
                        end else begin
                            neuron_base <= neuron_base + 6'd4;
                            input_idx <= 8'd0;
                        end
                        for (i = 0; i < 4; i = i + 1) acc[i] <= 11'sd0;
                    end else begin
                        input_idx <= input_idx + 8'd1;
                    end
                end

                S_LAYER2: begin
                    acc[0] <= tmac(acc[0], w0, current_input);
                    acc[1] <= tmac(acc[1], w1, current_input);
                    acc[2] <= tmac(acc[2], w2, current_input);
                    acc[3] <= tmac(acc[3], w3, current_input);

                    if (input_idx == input_max) begin
                        h2[neuron_base]     <= (tmac(acc[0], w0, current_input) > 11'sd0);
                        h2[neuron_base + 1] <= (tmac(acc[1], w1, current_input) > 11'sd0);
                        h2[neuron_base + 2] <= (tmac(acc[2], w2, current_input) > 11'sd0);
                        h2[neuron_base + 3] <= (tmac(acc[3], w3, current_input) > 11'sd0);

                        if (neuron_base == 6'd60) begin
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

                S_OUTPUT: begin
                    acc[0] <= tmac(acc[0], w0, current_input);
                    acc[1] <= tmac(acc[1], w1, current_input);
                    acc[2] <= tmac(acc[2], w2, current_input);
                    acc[3] <= tmac(acc[3], w3, current_input);

                    if (input_idx == input_max) begin
                        if (neuron_base < 6'd10)
                            scores[neuron_base[3:0]] <= clamp8(tmac(acc[0], w0, current_input));
                        if (neuron_base + 1 < 6'd10)
                            scores[neuron_base[3:0] + 4'd1] <= clamp8(tmac(acc[1], w1, current_input));
                        if (neuron_base + 2 < 6'd10)
                            scores[neuron_base[3:0] + 4'd2] <= clamp8(tmac(acc[2], w2, current_input));
                        if (neuron_base + 3 < 6'd10)
                            scores[neuron_base[3:0] + 4'd3] <= clamp8(tmac(acc[3], w3, current_input));

                        if (neuron_base >= 6'd8) begin
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

                S_ARGMAX: begin
                    prediction <= argmax_result;
                    state <= S_DONE;
                end

                S_DONE: begin
                    result_valid <= 1'b1;
                    busy <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
