import numpy as np
import os
import sys

# ================= 配置区域 (必须精确匹配) =================
QUANT_SHIFT = 8

# 【修正 1】Layer 1 的输出是 14x14 (因为 28->32->28->14)
INPUT_H, INPUT_W = 14, 14
INPUT_CH = 6

# L2 卷积核
KERNEL_SIZE = 5
OUTPUT_CH = 16

# 【修正 2】Layer 2 的输出尺寸计算
# 14 - 5 + 1 = 10 (Conv Out)
# 10 / 2 = 5 (Pool Out)
OUT_H_FINAL = 5
OUT_W_FINAL = 5

# 路径配置
RTL_DIR = "../../hardware/rtl/init_files"
L1_RESULT_FILE = "debug_data/debug_5_final_quant.txt"

WEIGHTS_FILE   = os.path.join(RTL_DIR, "conv2_weights.hex")
BIAS_FILE      = os.path.join(RTL_DIR, "conv2_bias.hex")

DEBUG_DIR = "debug_data_l2"
if not os.path.exists(DEBUG_DIR):
    os.makedirs(DEBUG_DIR)
# ===========================================

def hex2signed(val, bits):
    if val & (1 << (bits - 1)):
        val -= (1 << bits)
    return val

def saturate_cast(val):
    if val > 127: return 127
    elif val < -128: return -128
    else: return int(val)

def save_debug_file(filename, data, desc):
    path = os.path.join(DEBUG_DIR, filename)
    print(f"   -> Generating {filename} ({desc})...")
    h, w, c = data.shape
    with open(path, 'w') as f:
        f.write(f"# Description: {desc}\n# Shape: {h}x{w}x{c}\n")
        for r in range(h):
            for col in range(w):
                vals = [str(data[r, col, k]) for k in range(c)]
                f.write(" ".join(vals) + "\n")

def load_l1_output():
    print("1. Loading Layer 1 Output...")
    data = []
    try:
        with open(L1_RESULT_FILE, 'r') as f:
            for line in f:
                if line.startswith("#"): continue
                parts = line.strip().split()
                if len(parts) == INPUT_CH:
                    data.append([int(p) for p in parts])
    except FileNotFoundError:
        print(f"Error: {L1_RESULT_FILE} not found.")
        sys.exit(1)

    # 【核心验证】：文件行数必须等于 14*14 = 196
    expected_pixels = INPUT_H * INPUT_W
    if len(data) != expected_pixels:
        print(f"❌ Error: File has {len(data)} pixels, expected {expected_pixels} (14x14).")
        print("   Did you update calc_layer1_golden.py to use PADDING=2 (Input 32x32)?")
        sys.exit(1)

    # Reshape: 这里将扁平的 196 行还原为 14x14 矩阵
    # 如果 INPUT_W 错了，这里还原出来的图片就是扭曲的
    arr = np.array(data, dtype=np.int32).reshape(INPUT_H, INPUT_W, INPUT_CH)
    print(f"   Loaded L1 Output shape: {arr.shape}")
    return arr

def load_weights_bias():
    print("2. Loading L2 Weights and Bias...")

    w_tensor = np.zeros((OUTPUT_CH, INPUT_CH, KERNEL_SIZE, KERNEL_SIZE), dtype=np.int32)
    with open(WEIGHTS_FILE, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    groups = [(0, 6), (6, 12), (12, 16)]
    line_idx = 0

    for start_ch, end_ch in groups:
        for in_c in range(INPUT_CH):
            for r in range(KERNEL_SIZE):
                for s in range(KERNEL_SIZE):
                    if line_idx >= len(lines): break
                    val_hex = int(lines[line_idx], 16)
                    line_idx += 1
                    for k in range(6):
                        out_c = start_ch + k
                        if out_c < end_ch:
                            byte = (val_hex >> (k*8)) & 0xFF
                            w_tensor[out_c, in_c, r, s] = hex2signed(byte, 8)

    b_tensor = np.zeros((OUTPUT_CH,), dtype=np.int32)
    with open(BIAS_FILE, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    for i, (start_ch, end_ch) in enumerate(groups):
        if i >= len(lines): break
        val_hex = int(lines[i], 16)
        for k in range(6):
            out_c = start_ch + k
            if out_c < end_ch:
                chunk = (val_hex >> (k*32)) & 0xFFFFFFFF
                b_tensor[out_c] = hex2signed(chunk, 32)
    return w_tensor, b_tensor

def simulate_layer2(img, weights, bias):
    print("3. Simulating Layer 2 Calculation Steps...")

    # Step A: Valid Convolution
    # In: 14x14, K: 5x5 -> Out: 10x10
    conv_h = INPUT_H - KERNEL_SIZE + 1
    conv_w = INPUT_W - KERNEL_SIZE + 1

    conv_out = np.zeros((conv_h, conv_w, OUTPUT_CH), dtype=np.int32)

    for k in range(OUTPUT_CH):
        for r in range(conv_h):
            for c in range(conv_w):
                acc = 0
                for in_c in range(INPUT_CH):
                    patch = img[r:r+KERNEL_SIZE, c:c+KERNEL_SIZE, in_c]
                    kernel = weights[k, in_c, :, :]
                    partial = np.sum(patch * kernel)

                    acc += partial

                    # 【新增验证】：打印 (0,0) 位置 Input Ch 0 的部分和
                    if k == 0 and r == 0 and c == 0 and in_c == 0:
                        print(f"\n[DEBUG CHECK] Out(0,0) OutCh 0:")
                        print(f"  Input Ch 0 Contribution: {partial}")
                        debug_acc_ch0 = partial

                    if k == 0 and r == 0 and c == 0 and in_c == 5:
                         print(f"  Total Conv Sum (All 6 Chs): {acc}\n")
                conv_out[r, c, k] = acc
    save_debug_file("l2_debug_1_conv.txt", conv_out, "Raw Conv")

    # Step B & C: Bias & ReLU
    relu_out = np.zeros_like(conv_out)
    for k in range(OUTPUT_CH):
        val = conv_out[:, :, k] + bias[k]
        val[val < 0] = 0
        relu_out[:, :, k] = val
    save_debug_file("l2_debug_3_relu.txt", relu_out, "Bias + ReLU")

    # Step D: Max Pooling (2x2)
    # In: 10x10 -> Out: 5x5
    # 【注意】：10/2 = 5. 这里的尺寸是 5x5.
    pool_out = np.zeros((OUT_H_FINAL, OUT_W_FINAL, OUTPUT_CH), dtype=np.int32)

    for k in range(OUTPUT_CH):
        for r in range(OUT_H_FINAL):
            for c in range(OUT_W_FINAL):
                window = relu_out[2*r : 2*r+2, 2*c : 2*c+2, k]
                pool_out[r, c, k] = np.max(window)
    save_debug_file("l2_debug_4_pool.txt", pool_out, "Pool")

    # Step E: Quantization
    final_out = np.zeros_like(pool_out, dtype=np.int8)
    print(f"   [Quantization] Right Shift: {QUANT_SHIFT}")
    for k in range(OUTPUT_CH):
        for r in range(OUT_H_FINAL):
            for c in range(OUT_W_FINAL):
                val = pool_out[r, c, k]
                val_shifted = val >> QUANT_SHIFT
                final_out[r, c, k] = saturate_cast(val_shifted)

    save_debug_file("l2_debug_5_final.txt", final_out, "Final L2 Out")
    return final_out

def generate_comparison_file(data):
    filename = "l2_golden_compare.txt"
    print(f"4. Generating Comparison File: {filename}...")

    # data shape: (5, 5, 16)
    h, w, _ = data.shape
    pixels_per_ch = h * w # 25 pixels

    # 【必须与 TB 的 Dump 循环一致】
    # TB: Loop i=0..24 (Pixels), then Loop k=0..5 (Group channels)
    with open(filename, 'w') as f:
        # Group 1: Ch 0-5
        for idx in range(pixels_per_ch):
            r, c = idx // w, idx % w
            vals = [str(data[r, c, k]) for k in range(6)]
            f.write(" ".join(vals) + "\n")

        # Group 2: Ch 6-11
        for idx in range(pixels_per_ch):
            r, c = idx // w, idx % w
            vals = [str(data[r, c, k]) for k in range(6, 12)]
            f.write(" ".join(vals) + "\n")

        # Group 3: Ch 12-15
        for idx in range(pixels_per_ch):
            r, c = idx // w, idx % w
            vals = [str(data[r, c, k]) for k in range(12, 16)]
            f.write(" ".join(vals) + "\n")

if __name__ == "__main__":
    l1_out = load_l1_output()
    w, b = load_weights_bias()
    result = simulate_layer2(l1_out, w, b)
    generate_comparison_file(result)
    print("\nDone!")
