/*
 * Copyright (c) 2026 Nicholas Fong
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Top-level Tiny Tapeout wrapper for BNN Digit Classifier
// TTSKY26a shuttle interface
//
// Pin assignments:
//   ui_in[7:0]  — pixel data input (4 pixels × 2 bits per cycle)
//   uio_in[0]   — data_valid (high when ui_in has valid pixel data)
//   uio_in[1]   — start (pulse to begin inference, if pixels pre-loaded)
//   uio_out[2]  — busy (high during computation)
//   uio_out[3]  — result_valid (high when prediction is ready)
//   uo_out[3:0] — predicted digit (0-9)
//   uo_out[4]   — result_valid (active-high)
//   uo_out[7:5] — unused (tied low)
//
// Protocol:
//   1. Assert data_valid, send 36 bytes of pixel data (4 pixels each)
//   2. After 36 cycles, computation begins automatically
//   3. Wait for result_valid to go high (~5,900 cycles)
//   4. Read prediction from uo_out[3:0]
//
module tt_um_bnn_digit_classifier (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    // Bidirectional pins: [1:0] inputs, [7:2] outputs
    assign uio_oe = 8'b11111100;

    // Input signals
    wire data_valid = uio_in[0];
    wire start      = uio_in[1];

    // BNN core signals
    wire [3:0] prediction;
    wire       busy;
    wire       result_valid;

    // BNN compute core
    bnn_core core (
        .clk        (clk),
        .rst_n      (rst_n),
        .ena        (ena),
        .pixel_data (ui_in),
        .data_valid (data_valid),
        .start      (start),
        .prediction (prediction),
        .busy       (busy),
        .result_valid(result_valid)
    );

    // Output assignments
    assign uo_out[3:0] = prediction;
    assign uo_out[4]   = result_valid;
    assign uo_out[7:5] = 3'b000;

    // Bidirectional output assignments
    assign uio_out[1:0] = 2'b00;      // input pins, drive 0
    assign uio_out[2]   = busy;
    assign uio_out[3]   = result_valid;
    assign uio_out[7:4] = 4'b0000;

endmodule
