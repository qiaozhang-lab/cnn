'''
 @Author: Qiao Zhang & NPU Team
 @Description: Quantize LeNet weights and input, export Hardware-Ready HEX
               - Weights: Packed 6 channels per line (48-bit), 25 lines total.
               - Image: 8-bit per line, 784 lines.
               - VCS-Safe: No trailing newlines.
'''
import torch
import torch.nn as nn
import os
import numpy as np
from LeNet5 import LeNet5

#==================== Configuration ==============
# 1. Quantization Setup (Q1.7 fixed point)
SCALE_BITS = 7
SCALE_FACTOR = 128.0 # 2^7

# 2. Output Paths
OUTPUT_DIR = "../../../hardware/rtl/init_files"
if not os.path.exists(OUTPUT_DIR):
    os.makedirs(OUTPUT_DIR)

# ================= Helper Functions =================
def to_fixed(value, scale):
    '''
    Convert float to int8 with scaling: (clamp to -128 ~ 127)
    '''
    # 1. Scale
    scaled_val = value * scale
    # 2. Round
    int_val = int(round(scaled_val))
    # 3. Clamp
    int_val = max(min(int_val, 127), -128)
    return int_val

def to_hex(val, width=8):
    '''
    Convert Integer to Hex string (Handle 2's complement)
    '''
    mask = (1 << width) - 1
    # Format: 2 hex chars for 8-bit, 8 hex chars for 32-bit
    return f"{(val & mask):0{width//4}x}"

def write_hex_file(filename, data_list):
    '''
    Helper to write list of hex strings to file without trailing newline
    '''
    path = os.path.join(OUTPUT_DIR, filename)
    with open(path, 'w') as f:
        for i, hex_str in enumerate(data_list):
            # Write newline only if it's NOT the last line
            if i < len(data_list) - 1:
                f.write(hex_str + "\n")
            else:
                f.write(hex_str) # Last line, no newline
    print(f"Exported {filename}: {len(data_list)} lines.")

# ================= Main Process =================
def main():
    # 1. Load Trained Model
    print("Loading model ...")
    device = torch.device("cpu")
    net = LeNet5()

    try:
        net.load_state_dict(torch.load("lenet_weights.pth", map_location=device))
    except FileNotFoundError:
        print("Error: lenet_weights.pth not found! Please run train.py first")
        # Fallback for debugging without trained weights
        print("WARNING: Using random weights for test structure generation.")

    net.eval()

    # ---------------------------------------------------------
    # 2. Export Weights (Layer 1: Conv2d(1, 6, 5))
    #    Hardware Requirement: Wide ROM (48-bit width, 25 depth)
    # ---------------------------------------------------------
    print("Exporting Conv1 Weights...")
    # Shape: [Out_Ch=6, In_Ch=1, R=5, S=5]
    w_tensor = net.features[0].weight.data

    K, C, R, S = w_tensor.shape # 6, 1, 5, 5

    hex_lines = []

    # Iterate Spatial Dimensions (0..24)
    # The ROM address corresponds to spatial position r,s
    for r in range(R):
        for s in range(S):
            # For each spatial position, pack 6 output channels (K=0..5)
            # Order: MSB -> Ch5 ... Ch0 -> LSB
            line_hex = ""
            for k in range(K-1, -1, -1): # 5 down to 0
                val_float = w_tensor[k, 0, r, s].item()
                val_int = to_fixed(val_float, SCALE_FACTOR)
                line_hex += to_hex(val_int, 8)

            hex_lines.append(line_hex)

    write_hex_file("conv1_weights.hex", hex_lines)

    # Export Bias (Optional, for Acc Init)
    # Bias is usually 32-bit (Accumulator width)
    b_tensor = net.features[0].bias.data
    bias_lines = []
    for k in range(K):
        val_float = b_tensor[k].item()
        # Bias Scale = Scale_In * Scale_W = 128 * 128 = 16384 (Q14)
        val_int = int(round(val_float * (SCALE_FACTOR * SCALE_FACTOR)))
        bias_lines.append(to_hex(val_int, 32))

    write_hex_file("conv1_bias.hex", bias_lines)


    # ---------------------------------------------------------
    # 3. Export Input Image
    # ---------------------------------------------------------
    print("Exporting Input Image...")

    # Generate a simple deterministic pattern for Hardware Verification
    # (Easier to debug than random numbers)
    # Pattern: Incrementing 0, 1, 2... wrap around 255
    img_tensor = torch.zeros(1, 28, 28)
    for y in range(28):
        for x in range(28):
            # Normalized 0.0 ~ 1.0 approx
            val = ((y * 28 + x) % 255) / 255.0
            img_tensor[0, y, x] = val

    img_lines = []
    # Raster Scan Order
    for y in range(28):
        for x in range(28):
            val_float = img_tensor[0, y, x].item()
            val_int = to_fixed(val_float, SCALE_FACTOR)
            img_lines.append(to_hex(val_int, 8))

    write_hex_file("input_image.hex", img_lines)

    print(f"All files exported to: {os.path.abspath(OUTPUT_DIR)}")

if __name__ == "__main__":
    main()
