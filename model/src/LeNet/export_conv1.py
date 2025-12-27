'''
 @Author: Qiao Zhang
 @Date: 2025-12-18 21:09:26
 @LastEditTime: 2025-12-28 02:01:25
 @LastEditors: Qiao Zhang
 @Description: Quantize LeNet weights and input, export Hardware-Ready HEX for Conv1
               - Weights: Packed 6 channels per line (48-bit), 25 lines total.
               - Image: 8-bit per line, 784 lines.
 @FilePath: /cnn/model/src/LeNet/export_conv1.py
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

    # ---------------------------------------------------------
    # 4. Export Conv2 Weights (Layer 3: Conv2d(6, 16, 5))
    # ---------------------------------------------------------
    print("Exporting Conv2 Weights...")
    # Conv2 Weight Shape: [Out=16, In=6, R=5, S=5]
    w2_tensor = net.features[3].weight.data # 注意索引，features[3] 是 Conv2

    # 硬件需求：Weight Buffer 是 48-bit 宽 (存 6 个输入通道)。
    # 我们需要按 "输出通道" 分组导出。
    # 文件顺序：
    # OutCh 0 的所有 5x5 (25行)
    # OutCh 1 的所有 5x5 (25行)
    # ...
    # OutCh 15 的所有 5x5 (25行)
    # 总行数 = 16 * 25 = 400 行。

    K2, C2, R2, S2 = w2_tensor.shape # 16, 6, 5, 5

    conv2_hex_lines = []

    for out_ch in range(K2):
        # 对于每个输出通道，我们需要遍历 5x5 的空间位置
        for r in range(R2):
            for s in range(S2):
                # 在每个空间位置 (r,s)，我们要一次性取出 6 个输入通道的权重
                # Pack: MSB -> InCh5 ... InCh0 -> LSB
                line_hex = ""
                for in_ch in range(C2-1, -1, -1): # 5 down to 0
                    val_float = w2_tensor[out_ch, in_ch, r, s].item()
                    val_int = to_fixed(val_float, SCALE_FACTOR)
                    line_hex += to_hex(val_int, 8)
                conv2_hex_lines.append(line_hex)

    write_hex_file("conv2_weights.hex", conv2_hex_lines)

    # Export Conv2 Bias
    b2_tensor = net.features[3].bias.data
    bias2_lines = []
    # Bias Buffer 宽度是固定的 (6*32)。
    # 但 Conv2 是 16 个输出通道。
    # 我们按照 TDM 的 Pass 来存吗？
    # Pass 0: 算 Ch 0-5. 需要 Bias 0-5.
    # Pass 1: 算 Ch 6-11. 需要 Bias 6-11.
    # Pass 2: 算 Ch 12-15. 需要 Bias 12-15 (最后两个补0).

    # 所以我们每行存 6 个 Bias。总共 3 行。
    for i in range(0, K2, 6): # 0, 6, 12
        line_hex = ""
        # 这一行里倒序放 6 个 bias (或者正序？保持正序简单点，根据之前的经验)
        # 之前的 Bias Buffer 是 [k] 对应 Ch k。
        # 这里的 [k] 对应这一个 Pass 里的第 k 个计算通道。
        for k in range(6):
            if (i + k) < K2:
                val_float = b2_tensor[i + k].item()
                val_int = int(round(val_float * (SCALE_FACTOR * SCALE_FACTOR)))
            else:
                val_int = 0 # Padding for incomplete pass

            # 注意：Bias hex2int 是按 32位读的。
            # 我们的 loader 是按 192位 写的。
            # 为了简单，我们这里还是按行写单行 hex 吗？
            # 不，之前的 Bias hex 是每行一个 32bit 数。
            # 我们应该保持一致：Bias hex 文件里，每行一个数。
            # Loader 会负责把 6 行读出来拼成一个宽字写进去。
            pass

    # 简单起见，Bias文件依然存单列。
    bias2_lines_flat = []
    for k in range(K2):
        val_float = b2_tensor[k].item()
        val_int = int(round(val_float * (SCALE_FACTOR * SCALE_FACTOR)))
        bias2_lines_flat.append(to_hex(val_int, 32))

    write_hex_file("conv2_bias.hex", bias2_lines_flat)

    print(f"All files exported to: {os.path.abspath(OUTPUT_DIR)}")

if __name__ == "__main__":
    main()
