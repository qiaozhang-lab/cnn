'''
 @Author: Qiao Zhang
 @Date: 2026-01-01 19:52:13
 @LastEditTime: 2026-01-01 19:52:15
 @LastEditors: Qiao Zhang
 @Description:
 @FilePath: /cnn/verif/scripts/calc_fc2_fc3_debug_full.py
'''
import numpy as np
import os
import sys

# ================= 配置区域 =================
# 路径配置
RTL_INIT_DIR = "../../hardware/rtl/init_files"

# 输入文件 (来自 FC1 的计算结果)
FC1_OUT_FILE = "debug_data_fc1/fc1_debug_4_final.txt"

# 输出目录
DEBUG_DIR_FC2 = "debug_data_fc2"
DEBUG_DIR_FC3 = "debug_data_fc3"

# 硬件参数
QUANT_SHIFT = 8

# 维度定义
# FC2: 120 In -> 84 Out
FC2_IN_LEN  = 120
FC2_OUT_LEN = 84

# FC3: 84 In -> 10 Out
FC3_IN_LEN  = 84
FC3_OUT_LEN = 10

if not os.path.exists(DEBUG_DIR_FC2): os.makedirs(DEBUG_DIR_FC2)
if not os.path.exists(DEBUG_DIR_FC3): os.makedirs(DEBUG_DIR_FC3)

# ===========================================

def hex2signed8(val):
    if val > 127: val -= 256
    return val

def hex2signed32(val):
    if val > 0x7FFFFFFF: val -= 0x100000000
    return val

def saturate_cast(val):
    """硬件截断逻辑 (-128 ~ 127)"""
    if val > 127: return 127
    elif val < -128: return -128
    else: return int(val)

def load_hex_weights(filename, rows, cols):
    filepath = os.path.join(RTL_INIT_DIR, filename)
    print(f"Loading Weights from {filepath}...")
    data = []
    try:
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if not line: continue
                data.append(hex2signed8(int(line, 16)))
    except FileNotFoundError:
        print(f"[Error] File not found: {filepath}")
        sys.exit(1)

    arr = np.array(data, dtype=np.int32)
    if len(arr) != rows * cols:
        # Resize to handle potential padding differences
        arr.resize(rows * cols)
    return arr.reshape(rows, cols)

def load_hex_bias(filename, rows):
    filepath = os.path.join(RTL_INIT_DIR, filename)
    print(f"Loading Bias from {filepath}...")
    data = []
    try:
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if not line: continue
                data.append(hex2signed32(int(line, 16)))
    except FileNotFoundError:
        print(f"[Error] File not found: {filepath}")
        sys.exit(1)
    return np.array(data, dtype=np.int32)

def load_previous_output(filepath, expected_len):
    """读取上一层的输出 txt 文件 (每行一个十进制数)"""
    print(f"Loading Previous Output from {filepath}...")
    data = []
    try:
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith("#") or not line: continue
                data.append(int(line))
    except FileNotFoundError:
        print(f"[Error] File not found: {filepath}")
        print("Please run 'calc_fc1_golden.py' first!")
        sys.exit(1)

    arr = np.array(data, dtype=np.int32)
    if len(arr) != expected_len:
         print(f"[Warning] Input length mismatch! Expected {expected_len}, got {len(arr)}")
    return arr

def save_debug_file(folder, filename, data, desc):
    path = os.path.join(folder, filename)
    print(f"   -> Generating {filename} ({desc})...")
    with open(path, 'w') as f:
        f.write(f"# Description: {desc}\n")
        for val in data:
            f.write(f"{val}\n")

def simulate_layer(layer_name, input_vec, weights, bias, out_dir, use_relu=True):
    print(f"\n--- Simulating {layer_name.upper()} ---")

    # 1. Matrix Mult (Accumulation)
    acc = np.dot(weights, input_vec)
    save_debug_file(out_dir, f"{layer_name}_debug_1_acc.txt", acc, "Raw Accumulation")

    # 2. Add Bias
    biased = acc + bias
    save_debug_file(out_dir, f"{layer_name}_debug_2_bias.txt", biased, "Accumulation + Bias")

    # 3. ReLU (Optional)
    if use_relu:
        activated = np.maximum(0, biased)
        save_debug_file(out_dir, f"{layer_name}_debug_3_relu.txt", activated, "ReLU")
    else:
        activated = biased # Pass through
        print(f"   (Skipping ReLU for {layer_name})")

    # 4. Quantization
    quant = activated >> QUANT_SHIFT

    # Saturate
    final = np.array([saturate_cast(x) for x in quant], dtype=np.int32)
    save_debug_file(out_dir, f"{layer_name}_debug_4_final.txt", final, "Final 8-bit")

    return final

def main():
    # 1. Load FC1 Output (which is FC2 Input)
    fc1_out = load_previous_output(FC1_OUT_FILE, FC2_IN_LEN)

    # 2. Calculate FC2
    fc2_w = load_hex_weights("fc2_weights.hex", FC2_OUT_LEN, FC2_IN_LEN)
    fc2_b = load_hex_bias("fc2_bias.hex", FC2_OUT_LEN)

    fc2_out = simulate_layer("fc2", fc1_out, fc2_w, fc2_b, DEBUG_DIR_FC2, use_relu=True)

    # 3. Calculate FC3 (Input is FC2 Output)
    fc3_w = load_hex_weights("fc3_weights.hex", FC3_OUT_LEN, FC3_IN_LEN)
    fc3_b = load_hex_bias("fc3_bias.hex", FC3_OUT_LEN)

    # 注意：FC3 (Output Layer) 通常不加 ReLU，直接输出 Logits
    # 请根据你的 RTL 配置确认。这里假设 FC3 没有 ReLU。
    fc3_out = simulate_layer("fc3", fc2_out, fc3_w, fc3_b, DEBUG_DIR_FC3, use_relu=False)

    print("\nDone! Check debug_data_fc2/ and debug_data_fc3/")

if __name__ == "__main__":
    main()
