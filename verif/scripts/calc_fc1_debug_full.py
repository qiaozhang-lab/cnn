import numpy as np
import os
import sys

# ================= 配置区域 =================
# 输入/输出目录
RTL_INIT_DIR = "../../hardware/rtl/init_files"
L2_OUT_FILE  = "debug_data_l2/l2_debug_5_final.txt"
DEBUG_DIR    = "debug_data_fc1"

# 权重/偏置文件
WEIGHTS_FILE = os.path.join(RTL_INIT_DIR, "fc1_weights.hex")
BIAS_FILE    = os.path.join(RTL_INIT_DIR, "fc1_bias.hex")

# 硬件参数
INPUT_LEN   = 400  # 16ch * 5 * 5
OUTPUT_LEN  = 120  # FC1 Neurons
QUANT_SHIFT = 8

if not os.path.exists(DEBUG_DIR):
    os.makedirs(DEBUG_DIR)

# ===========================================

def hex2signed8(val):
    """转换 8-bit Hex 到有符号整数"""
    if val > 127: val -= 256
    return val

def hex2signed32(val):
    """转换 32-bit Hex 到有符号整数"""
    if val > 0x7FFFFFFF: val -= 0x100000000
    return val

def saturate_cast(val):
    """硬件截断逻辑 (-128 ~ 127)"""
    if val > 127: return 127
    elif val < -128: return -128
    else: return int(val)

def load_hex_weights(filepath, rows, cols):
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
        print(f"[Warning] Size mismatch! Expected {rows*cols}, got {len(arr)}")
        # Resize safely
        arr.resize(rows * cols)

    return arr.reshape(rows, cols)

def load_hex_bias(filepath, rows):
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

def load_l2_output_and_flatten():
    """
    读取 L2 输出文件并转换为 FC 输入向量。
    文件格式 (l2_debug_5_final.txt): 25行 (Pixels), 每行 16个数 (Channels)
    目标格式: Channel-Major Flatten (先 Ch0 所有像素, 再 Ch1...)
    """
    print(f"Loading L2 Output from {L2_OUT_FILE}...")
    data = []
    try:
        with open(L2_OUT_FILE, 'r') as f:
            for line in f:
                if line.startswith("#") or not line.strip(): continue
                parts = [int(p) for p in line.split()]
                if len(parts) == 16:
                    data.append(parts)
    except FileNotFoundError:
        print(f"[Error] File not found: {L2_OUT_FILE}")
        sys.exit(1)

    # 原始形状: [25 (Pixels), 16 (Channels)]
    # (Pixel 0, Ch 0..15)
    # (Pixel 1, Ch 0..15)
    arr_2d = np.array(data, dtype=np.int32) # Shape: (25, 16)

    # 转置为 [16, 25] -> (Ch 0, Px 0..24), (Ch 1, Px 0..24)...
    arr_transposed = arr_2d.T

    # 展平
    input_vec = arr_transposed.flatten() # Shape: (400,)

    print(f"   -> Loaded Shape: {arr_2d.shape}")
    print(f"   -> Flattened (Channel-Major) Size: {len(input_vec)}")

    # 打印前几个数用于核对
    print(f"   -> Sample Ch0 (First 5): {input_vec[:5]}")
    print(f"   -> Sample Ch1 (First 5): {input_vec[25:30]}")

    return input_vec

def save_debug_file(filename, data, desc):
    path = os.path.join(DEBUG_DIR, filename)
    print(f"   -> Generating {filename} ({desc})...")
    with open(path, 'w') as f:
        f.write(f"# Description: {desc}\n")
        f.write(f"# Shape: {len(data)} (1D Vector)\n")
        # 每行打印一个值，方便对比
        for i, val in enumerate(data):
            f.write(f"{val}\n")

def simulate_fc1(input_vec, weights, bias):
    print("\n--- Simulating FC1 ---")

    # 1. Matrix Multiplication (Accumulation)
    # [120, 400] x [400] -> [120]
    acc = np.dot(weights, input_vec)
    save_debug_file("fc1_debug_1_acc.txt", acc, "Raw Accumulation (Sum)")

    # 2. Add Bias
    biased = acc + bias
    save_debug_file("fc1_debug_2_bias.txt", biased, "Accumulation + Bias")

    # 3. ReLU
    relu = np.maximum(0, biased)
    save_debug_file("fc1_debug_3_relu.txt", relu, "ReLU")

    # 4. Quantization
    # Right shift 8 (Arithmetic)
    quant = relu >> QUANT_SHIFT

    # Saturate to 8-bit
    final = np.array([saturate_cast(x) for x in quant], dtype=np.int32)
    save_debug_file("fc1_debug_4_final.txt", final, "Final Quantized (8-bit)")

    print("\nSimulation Complete.")
    print(f"Check '{DEBUG_DIR}' for output files.")

if __name__ == "__main__":
    # Load Data
    fc_in = load_l2_output_and_flatten()
    fc_w  = load_hex_weights(WEIGHTS_FILE, OUTPUT_LEN, INPUT_LEN)
    fc_b  = load_hex_bias(BIAS_FILE, OUTPUT_LEN)

    # Run Sim
    simulate_fc1(fc_in, fc_w, fc_b)
