// BNN Core — 1-MAC serial compute engine (minimal area)
//
// 1 neuron at a time, inputs processed serially
// ~23,400 clock cycles per inference (~2.3ms at 10 MHz)
// Minimal routing: single weight lookup per cycle
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
    reg [5:0] neuron_idx;
    reg [7:0] input_idx;
    reg [7:0] input_max;

    // ---- Pixel Storage (144 x 2-bit codes) ----
    reg [1:0] pixels [0:143];
    reg [5:0] load_ptr;

    // ---- Single pixel LUT ----
    reg [1:0] current_pixel_code;
    wire signed [2:0] current_pixel_val;
    pixel_lut px_lut (.code(current_pixel_code), .value(current_pixel_val));

    // ---- Hidden Activations (1-bit each) ----
    reg h1 [0:63];
    reg h2 [0:63];

    // ---- Single Weight ROM per layer (1 tap each) ----
    wire signed [1:0] w_l1, w_l2, w_out;

    weight_rom_l1 wrom_l1 (
        .neuron_idx(neuron_idx), .input_idx(input_idx), .weight(w_l1)
    );
    weight_rom_l2 wrom_l2 (
        .neuron_idx(neuron_idx), .input_idx(input_idx), .weight(w_l2)
    );
    weight_rom_out wrom_out (
        .neuron_idx(neuron_idx[3:0]), .input_idx(input_idx[6:0]), .weight(w_out)
    );

    // Select weight based on current layer
    wire signed [1:0] w = (state == S_LAYER1) ? w_l1 :
                          (state == S_LAYER2) ? w_l2 : w_out;

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

    // ---- Single Accumulator ----
    reg signed [10:0] acc;

    // Ternary MAC (no multiplier)
    function signed [10:0] tmac;
        input signed [10:0] a;
        input signed [1:0]  wt;
        input signed [2:0]  x;
        begin
            case (wt)
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
            neuron_idx <= 6'd0;
            input_idx <= 8'd0;
            input_max <= 8'd0;
            acc <= 11'sd0;
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
                        neuron_idx <= 6'd0;
                        input_idx <= 8'd0;
                        input_max <= 8'd143;
                        acc <= 11'sd0;
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
                            neuron_idx <= 6'd0;
                            input_idx <= 8'd0;
                            input_max <= 8'd143;
                            acc <= 11'sd0;
                        end
                    end else if (start) begin
                        state <= S_LAYER1;
                        neuron_idx <= 6'd0;
                        input_idx <= 8'd0;
                        input_max <= 8'd143;
                        acc <= 11'sd0;
                    end
                end

                S_LAYER1: begin
                    acc <= tmac(acc, w, current_input);

                    if (input_idx == input_max) begin
                        // Threshold & store (all thresholds are 0, strict >)
                        h1[neuron_idx] <= (tmac(acc, w, current_input) > 11'sd0);

                        if (neuron_idx == 6'd63) begin
                            state <= S_LAYER2;
                            neuron_idx <= 6'd0;
                            input_idx <= 8'd0;
                            input_max <= 8'd207;
                        end else begin
                            neuron_idx <= neuron_idx + 6'd1;
                            input_idx <= 8'd0;
                        end
                        acc <= 11'sd0;
                    end else begin
                        input_idx <= input_idx + 8'd1;
                    end
                end

                S_LAYER2: begin
                    acc <= tmac(acc, w, current_input);

                    if (input_idx == input_max) begin
                        h2[neuron_idx] <= (tmac(acc, w, current_input) > 11'sd0);

                        if (neuron_idx == 6'd63) begin
                            state <= S_OUTPUT;
                            neuron_idx <= 6'd0;
                            input_idx <= 8'd0;
                            input_max <= 8'd63;
                        end else begin
                            neuron_idx <= neuron_idx + 6'd1;
                            input_idx <= 8'd0;
                        end
                        acc <= 11'sd0;
                    end else begin
                        input_idx <= input_idx + 8'd1;
                    end
                end

                S_OUTPUT: begin
                    acc <= tmac(acc, w, current_input);

                    if (input_idx == input_max) begin
                        if (neuron_idx < 6'd10)
                            scores[neuron_idx[3:0]] <= clamp8(tmac(acc, w, current_input));

                        if (neuron_idx == 6'd9) begin
                            state <= S_ARGMAX;
                        end else begin
                            neuron_idx <= neuron_idx + 6'd1;
                            input_idx <= 8'd0;
                        end
                        acc <= 11'sd0;
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
