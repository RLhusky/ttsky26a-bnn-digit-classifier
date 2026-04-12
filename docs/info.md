<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This is a binary neural network (BNN) that classifies handwritten digits (0-9) from 12x12 pixel images. It achieves 94.11% accuracy on the MNIST test set.

The network has 2 hidden layers with skip connections:
- **Layer 1**: 64 neurons, 144 pixel inputs, ternary weights {-1,0,+1}, binary activations {-1,+1}
- **Layer 2**: 64 neurons, 208 inputs (64 hidden + 144 pixel skip connection)
- **Output**: 10 class scores, argmax selects the predicted digit

All 23,168 weights are ternary ({-1,0,+1}), meaning no multipliers are needed — just conditional add/subtract. 54.8% of weights are zero, reducing area further. The design uses 4 parallel MAC units processing neurons serially, completing one inference in ~5,900 clock cycles.

## How to test

1. Assert `data_valid` (uio_in[0]) and send 36 bytes of pixel data on ui_in[7:0], one byte per clock cycle. Each byte packs 4 pixels as 2-bit codes: `{px0[1:0], px1[1:0], px2[1:0], px3[1:0]}`.
2. Pixel codes map to values: 0=-3, 1=-1, 2=+1, 3=+3 (2-bit grayscale quantization with thresholds [30, 80, 160]).
3. After all 36 bytes are sent, computation begins automatically.
4. Wait for `result_valid` (uo_out[4]) to go high (~5,900 clock cycles at 10 MHz = ~0.6ms).
5. Read the predicted digit from uo_out[3:0] (value 0-9).

## External hardware

A microcontroller (e.g. RP2040 on the TT demo board) to capture images, downsample to 12x12, quantize to 2-bit codes, and send via the serial protocol. Any camera module or pre-stored test images will work.
