'''
 @Author: Qiao Zhang
 @Date: 2025-12-18 21:09:26
 @LastEditTime: 2025-12-18 22:14:36
 @LastEditors: Qiao Zhang
 @Description: Quantize LeNet weights and input, export HEX for systemverilog
 @FilePath: /cnn/model/src/LeNet/export_hardware.py
'''
import torch
import torch.nn as nn
import os
import numpy as np
from   LeNet5 import LeNet5

#==================== Configuration ==============
# 1. Quantization Setup(Q7 fixed point: 1 sign bit, 7 fractional bits)
SCALE_BITS = 7
SCALE_FACTOR = 2**7

# 2. Output Paths
OUTPUT_DIR = "../../../hardware/rtl/init_files"
# Check if not exists then creates it
if not os.path.exists(OUTPUT_DIR):
    os.makedirs(OUTPUT_DIR)

# ================= Helper Functions =================
def to_fixed(value):
    '''
    Convert float point to int8:(clamp to -128 ~ 127)
    '''
    int_val = int(round(value))
    int_val = max(min(int_val, 127), -128)# int_val = min(max(int_val, -128), 127)
    return int_val

def to_hex(val, width=8):
    '''
    Convert Integer to Hex string(Handle 2's complement)
    '''
    mask = (1 << width) - 1 # 0xFF
    return f"{(val & mask):0{width//4}x}"

def software_conv1_golden(img_int, w_int, b_int):
    '''
    Simulate Hardware Convolutional to generate the golden output
    Input: Int8, Weight: Int8, Bias: Int32 -> Output: Int32(Accumulator)
    '''
    # Image shape: (1, 28, 28), w shape(1, 6, 5, 5)
    K, C, R, S = w_int.shape
    _, H, W = img_int.shape
    # activate slip windows position coordinate(top left corner)
    H_out, W_out = 24, 24 # 28-5+1=24

    # declare a output arrays
    output = np.zeros((K, H_out, W_out), dtype=np.int32)

    print("Compute Golden Result for Convolutional(Slow):")

    # (k, y, x) to define the position coordinate of slip windows
    # (r, s) to define the position coordinate of a pixel which is located in a selected slip windows
    for k in range(K):
        for y in range(W_out):
            for x in range(H_out):
                acc = b_int[k] # initialize with bias
                # Implicit Im2col Dot Product
                for r in range(R):
                    for s in range(S):
                        pixel = img_int[0, y+r, x+s]
                        weight = w_int[k, 0, r, s]
                        acc += pixel*weight
                output[k, y, x] = acc
    return output

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
        return

    net.eval()

    # 2. Export Weights (Layer 1: Conv2d(1, 6, 5))
    print("Exporting Conv1 Weights...")
    w_tensor = net.features[0].weight.data # [6, 1, 5, 5]
    b_tensor = net.features[0].bias.data   # [6]

    K, C, R, S = w_tensor.shape

    # Store Quantized Weights for Golden calculation
    w_int_cache = np.zeros((K, C, R, S), dtype=np.int32)
    b_int_cache = np.zeros((K), dtype=np.int32)

    with open(os.path.join(OUTPUT_DIR, "conv1_weights.hex"), 'w') as f:
        # Layout: Row Major (K -> C -> R -> S) -> Corresponds to GEMM Matrix A Rows
        for k in range(K):
            # For each kernel (GEMM Row)
            for c in range(C):
                for r in range(R):
                    for s in range(S):
                        val_float = w_tensor[k, c, r, s].item()
                        val_int = to_fixed(val_float)
                        w_int_cache[k, c, r, s] = val_int
                        # Write 8-bit hex
                        f.write(to_hex(val_int, 8) + "\n")
            # Note: In a real system, you might align to 32-bit or add padding here

    with open(os.path.join(OUTPUT_DIR, "conv1_bias.hex"), 'w') as f:
        for k in range(K):
            val_float = b_tensor[k].item()
            # Bias usually has higher precision. Let's align it to scale*scale (double precision)
            # or keep it simple. Here we use same scale for simplicity,
            # BUT usually bias is Scale_Input * Scale_Weight.
            # Let's assume Input is also Q7, so Bias should be Q14.
            # For simplicity in this tutorial, let's treat bias as Q7 temporarily or Q14.
            # Let's use Q14 for Bias to match Acc (Q7*Q7).
            val_int = int(round(val_float * (SCALE_FACTOR * SCALE_FACTOR)))
            b_int_cache[k] = val_int
            f.write(to_hex(val_int, 32) + "\n") # 32-bit Bias

    # 3. Export Input Image (Random or Specific)
    print("Exporting Input Image...")
    # Let's grab a real image from MNIST or generate a fixed pattern
    # Using fixed pattern for easy debugging:
    # img[y,x] = (y+x) % 16 (just to see patterns)
    img_tensor = torch.zeros(1, 28, 28)
    for y in range(28):
        for x in range(28):
            img_tensor[0, y, x] = (y + x) % 16 / 16.0 # Normalize 0~1

    img_int_cache = np.zeros((1, 28, 28), dtype=np.int32)

    with open(os.path.join(OUTPUT_DIR, "input_image.hex"), 'w') as f:
        # Raster Scan Order (Line by Line)
        for y in range(28):
            for x in range(28):
                val_float = img_tensor[0, y, x].item()
                val_int = to_fixed(val_float) # Quantize Input to Q7
                img_int_cache[0, y, x] = val_int
                f.write(to_hex(val_int, 8) + "\n")

    # 4. Generate Golden Output (Software Simulation of Hardware)
    print("Generating Golden Output Vector...")
    golden_out = software_conv1_golden(img_int_cache, w_int_cache, b_int_cache)

    with open(os.path.join(OUTPUT_DIR, "conv1_golden_out.hex"), 'w') as f:
        # Export in (K, H_out, W_out) order
        for k in range(golden_out.shape[0]):
            for y in range(golden_out.shape[1]):
                for x in range(golden_out.shape[2]):
                    val = golden_out[k, y, x]
                    f.write(to_hex(val, 32) + "\n") # Accumulator is 32-bit

    print(f"All files exported to: {os.path.abspath(OUTPUT_DIR)}")

if __name__ == "__main__":
    main()
