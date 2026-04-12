// Input buffer — stores 144 pixels as 2-bit codes
// Loaded serially: 4 pixels per clock cycle (8 bits) over 36 cycles
// Provides random access for the compute engine
module input_buffer (
    input  wire        clk,
    input  wire        rst_n,
    // Load interface
    input  wire        load_en,     // high during pixel loading
    input  wire [7:0]  load_data,   // 4 pixels packed: {px0[1:0], px1[1:0], px2[1:0], px3[1:0]}
    // Read interface
    input  wire [7:0]  read_idx,    // pixel index (0-143)
    output wire [1:0]  read_code    // 2-bit pixel code at read_idx
);
    // Storage: 144 pixels × 2 bits = 288 bits
    reg [1:0] pixels [0:143];

    // Load counter
    reg [5:0] load_ptr;  // 0-35 (36 load cycles)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_ptr <= 6'd0;
        end else if (load_en) begin
            // Unpack 4 pixels from 8-bit input, MSB first
            pixels[{load_ptr, 2'b00}]     <= load_data[7:6];
            pixels[{load_ptr, 2'b01}]     <= load_data[5:4];
            pixels[{load_ptr, 2'b10}]     <= load_data[3:2];
            pixels[{load_ptr, 2'b11}]     <= load_data[1:0];
            load_ptr <= load_ptr + 1;
        end else begin
            load_ptr <= 6'd0;
        end
    end

    // Combinational read
    assign read_code = pixels[read_idx];

endmodule
