"""
cocotb testbench for BNN Digit Classifier
Tests bit-exact match between Verilog RTL and Python reference model.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import json
import numpy as np
import os

# ============================================================
# Python reference model — MUST match Verilog exactly
# ============================================================

def hw_reference(pixels_2bit_codes, weights):
    """
    Bit-exact integer reference model.
    pixels_2bit_codes: (144,) array of 2-bit codes (0-3)
    weights: dict from weights.json
    Returns: predicted digit (int)
    """
    Wi = np.array(weights["input_layer"], dtype=np.int32)
    Wr = np.array(weights["recurrent_layer"], dtype=np.int32)
    Wo = np.array(weights["output_layer"], dtype=np.int32)
    ti = np.array(weights["threshold_input"], dtype=np.int32)
    tr = np.array(weights["threshold_recurrent"], dtype=np.int32)

    lut = np.array([-3, -1, 1, 3], dtype=np.int32)
    px_vals = lut[pixels_2bit_codes]  # (144,)

    # Layer 1: 64 neurons
    acc1 = px_vals @ Wi.T  # (64,)
    acc1 = np.clip(acc1, -511, 511)
    h1 = np.where(acc1 > ti, 1, -1).astype(np.int32)

    # Layer 2: skip connection [h1, pixels]
    cat = np.concatenate([h1, px_vals])  # (208,)
    acc2 = cat @ Wr.T  # (64,)
    acc2 = np.clip(acc2, -511, 511)
    h2 = np.where(acc2 > tr, 1, -1).astype(np.int32)

    # Output
    scores = h2 @ Wo.T  # (10,)
    scores = np.clip(scores, -127, 127)
    return int(np.argmax(scores))


def load_weights():
    """Load weights.json from various possible locations."""
    for path in ["weights_BEST/weights.json", "../weights_BEST/weights.json",
                 "weights.json", "../weights.json"]:
        if os.path.exists(path):
            with open(path) as f:
                return json.load(f)
    raise FileNotFoundError("Could not find weights.json")


def prepare_test_data():
    """Load MNIST test data and prepare quantized inputs."""
    from torchvision import datasets
    import torch
    import torch.nn.functional as F

    test_ds = datasets.MNIST(root='./data', train=False, download=True)
    images = test_ds.data.numpy()  # (10000, 28, 28)
    labels = test_ds.targets.numpy()

    # Downsample to 12x12
    t = torch.from_numpy(images).float().unsqueeze(1)
    pooled = F.adaptive_avg_pool2d(t, (12, 12)).view(-1, 144).numpy()

    # Quantize to 2-bit codes
    codes = np.zeros_like(pooled, dtype=np.int32)
    codes[pooled <= 30] = 0
    codes[(pooled > 30) & (pooled <= 80)] = 1
    codes[(pooled > 80) & (pooled <= 160)] = 2
    codes[pooled > 160] = 3

    return codes, labels


# ============================================================
# Helper: Pack pixels into bytes for the I/O protocol
# ============================================================

def pack_pixels(pixel_codes):
    """Pack 144 2-bit pixel codes into 36 bytes (4 pixels per byte, MSB first)."""
    assert len(pixel_codes) == 144
    bytes_out = []
    for i in range(0, 144, 4):
        b = ((int(pixel_codes[i]) & 0x3) << 6) | \
            ((int(pixel_codes[i+1]) & 0x3) << 4) | \
            ((int(pixel_codes[i+2]) & 0x3) << 2) | \
            (int(pixel_codes[i+3]) & 0x3)
        bytes_out.append(b)
    return bytes_out


# ============================================================
# cocotb Tests
# ============================================================

async def reset_dut(dut):
    """Apply reset and wait."""
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def run_inference(dut, pixel_codes):
    """Load pixels and run one inference. Returns predicted digit."""
    packed = pack_pixels(pixel_codes)

    # Load pixels: assert data_valid, send 36 bytes
    for byte_val in packed:
        dut.ui_in.value = byte_val
        dut.uio_in.value = 0x01  # data_valid = 1
        await RisingEdge(dut.clk)

    dut.uio_in.value = 0x00  # deassert data_valid
    dut.ui_in.value = 0

    # Wait for result_valid
    timeout = 25000
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if int(dut.uo_out.value) & 0x10:  # bit 4 = result_valid
            break
    else:
        raise TimeoutError(f"Inference did not complete within {timeout} cycles")

    prediction = int(dut.uo_out.value) & 0x0F
    return prediction


@cocotb.test()
async def test_basic_inference(dut):
    """Test that the design produces a valid prediction (0-9)."""
    clock = Clock(dut.clk, 100, unit="ns")  # 10 MHz
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # Create a simple test pattern (all zeros → code 0 → value -3)
    test_pixels = [0] * 144  # all code 0
    pred = await run_inference(dut, test_pixels)

    dut._log.info(f"All-zero input → prediction: {pred}")
    assert 0 <= pred <= 9, f"Prediction {pred} out of range"


@cocotb.test()
async def test_reference_match(dut):
    """Test 100 MNIST images against Python reference model."""
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    weights = load_weights()
    codes, labels = prepare_test_data()

    n_test = 100
    matches = 0
    correct = 0

    for i in range(n_test):
        # Python reference
        ref_pred = hw_reference(codes[i], weights)
        # Verilog DUT
        await reset_dut(dut)  # reset between inferences
        rtl_pred = await run_inference(dut, codes[i])

        if rtl_pred == ref_pred:
            matches += 1
        else:
            dut._log.warning(f"MISMATCH sample {i}: RTL={rtl_pred} ref={ref_pred} label={labels[i]}")

        if rtl_pred == labels[i]:
            correct += 1

    accuracy = correct / n_test * 100
    match_rate = matches / n_test * 100

    dut._log.info(f"Results: {correct}/{n_test} correct ({accuracy:.1f}%), "
                  f"{matches}/{n_test} RTL/ref matches ({match_rate:.1f}%)")

    assert matches == n_test, \
        f"RTL/reference mismatch: {n_test - matches} out of {n_test} samples disagree"


@cocotb.test()
async def test_full_mnist(dut):
    """Full 10K MNIST test — verify accuracy matches training report."""
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    weights = load_weights()
    codes, labels = prepare_test_data()

    n_test = len(labels)  # 10000
    correct = 0
    mismatches = 0

    for i in range(n_test):
        ref_pred = hw_reference(codes[i], weights)
        await reset_dut(dut)
        rtl_pred = await run_inference(dut, codes[i])

        if rtl_pred != ref_pred:
            mismatches += 1
        if rtl_pred == labels[i]:
            correct += 1

        if (i + 1) % 1000 == 0:
            dut._log.info(f"  Progress: {i+1}/{n_test}, accuracy so far: {correct/(i+1)*100:.2f}%")

    accuracy = correct / n_test * 100
    dut._log.info(f"Final: {correct}/{n_test} ({accuracy:.2f}%), mismatches: {mismatches}")

    assert mismatches == 0, f"{mismatches} RTL/reference mismatches"
    assert accuracy > 93.0, f"Accuracy {accuracy:.2f}% below expected ~94%"
