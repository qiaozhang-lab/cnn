import numpy as np
import sys
import os

# ================= 配置区域 (请与 RTL 参数保持一致) =================
QUANT_SHIFT = 8
INPUT_H, INPUT_W = 28, 28
PADDING = 2       # 硬件输入变为 32x32
KERNEL_SIZE = 5

# 文件路径
RTL_DIR = "../../hardware/rtl/init_files"
WEIGHTS_FILE = os.path.join(RTL_DIR, "conv1_weights.hex")
BIAS_FILE    = os.path.join(RTL_DIR, "conv1_bias.hex")
IMAGE_FILE   = os.path.join(RTL_DIR, "input_image.hex")
OUTPUT_DIR   = "debug_data" # 输出目录

if not os.path.exists(OUTPUT_DIR):
    os.makedirs(OUTPUT_DIR)
# ===================================================================

def hex2signed(val, bits):
    """转换 Hex 到 有符号整数"""
    if val & (1 << (bits - 1)):
        val -= (1 << bits)
    return val

def saturate_cast(val):
    """模拟硬件的 8-bit 截断"""
    if val > 127: return 127
    elif val < -128: return -128
    else: return int(val)

def save_to_file(filename, data, fmt="{:d}"):
    """通用保存函数: (H, W, Ch) -> 文本"""
    filepath = os.path.join(OUTPUT_DIR, filename)
    print(f"   -> Saving {filename} ...")

    # 展平为 2D: 行 = 像素(按行优先), 列 = 通道
    h, w, c = data.shape

    with open(filepath, "w") as f:
        f.write(f"# Shape: {h}x{w}, Channels: {c}\n")
        f.write(f"# Format: Each line is one pixel location. Columns are Channels 0 to {c-1}\n")

        for r in range(h):
            for col in range(w):
                line_vals = []
                for k in range(c):
                    val = data[r, col, k]
                    line_vals.append(fmt.format(val))
                f.write(" ".join(line_vals) + "\n")

def run_debug_simulation():
    print("--- 1. Loading Data ---")

    # Load Image
    img_raw = []
    with open(IMAGE_FILE) as f:
        for line in f: img_raw.append(int(line.strip(), 16))
    img = np.array(img_raw).reshape(INPUT_H, INPUT_W)

    # Load Weights (MSB=Ch5..LSB=Ch0)
    w_raw = [[], [], [], [], [], []]
    with open(WEIGHTS_FILE) as f:
        for line in f:
            val = int(line.strip(), 16)
            for k in range(6):
                byte = (val >> (k*8)) & 0xFF
                w_raw[k].append(hex2signed(byte, 8))
    weights = np.array(w_raw).reshape(6, 5, 5)

    # Load Bias
    bias = []
    with open(BIAS_FILE) as f:
        for line in f: bias.append(hex2signed(int(line.strip(), 16), 32))

    print("--- 2. Processing Stages ---")

    # === Stage 0: Padding (Loader) ===
    padded_h = INPUT_H + 2 * PADDING
    padded_w = INPUT_W + 2 * PADDING
    padded_img = np.zeros((padded_h, padded_w), dtype=np.int32)
    padded_img[PADDING:-PADDING, PADDING:-PADDING] = img

    # 保存 Input Buffer 里的内容 (单通道)
    # Reshape to (H, W, 1) for uniform saving
    save_to_file("debug_0_padded_input.txt", padded_img.reshape(padded_h, padded_w, 1))

    # === Stage 1: Convolution (SA Output) ===
    out_h = padded_h - KERNEL_SIZE + 1
    out_w = padded_w - KERNEL_SIZE + 1

    conv_raw = np.zeros((out_h, out_w, 6), dtype=np.int32)
    conv_bias = np.zeros((out_h, out_w, 6), dtype=np.int32)
    conv_relu = np.zeros((out_h, out_w, 6), dtype=np.int32)

    for k in range(6):
        w_kernel = weights[k]
        b_val    = bias[k]

        for r in range(out_h):
            for c in range(out_w):
                # 1. MAC
                patch = padded_img[r : r+KERNEL_SIZE, c : c+KERNEL_SIZE]
                acc = np.sum(patch * w_kernel)
                conv_raw[r, c, k] = acc

                # 2. Add Bias
                acc_b = acc + b_val
                conv_bias[r, c, k] = acc_b

                # 3. ReLU
                if acc_b < 0: acc_b = 0
                conv_relu[r, c, k] = acc_b

    save_to_file("debug_1_conv_raw.txt", conv_raw)
    save_to_file("debug_2_bias_added.txt", conv_bias)
    save_to_file("debug_3_relu.txt", conv_relu)

    # === Stage 4: Max Pooling ===
    pool_h = out_h // 2
    pool_w = out_w // 2
    pool_out = np.zeros((pool_h, pool_w, 6), dtype=np.int32)

    for k in range(6):
        for r in range(pool_h):
            for c in range(pool_w):
                window = conv_relu[2*r : 2*r+2, 2*c : 2*c+2, k]
                pool_out[r, c, k] = np.max(window)

    save_to_file("debug_4_pool.txt", pool_out)

    # === Stage 5: Quantization (Final Output) ===
    final_out = np.zeros((pool_h, pool_w, 6), dtype=np.int32)

    print(f"   [Quantization] Applying Right Shift: {QUANT_SHIFT}")

    for k in range(6):
        for r in range(pool_h):
            for c in range(pool_w):
                val = pool_out[r, c, k]
                val_shifted = val >> QUANT_SHIFT
                final_out[r, c, k] = saturate_cast(val_shifted)

    save_to_file("debug_5_final_quant.txt", final_out)

    print(f"\n✅ All debug files generated in '{OUTPUT_DIR}/'.")

if __name__ == "__main__":
    run_debug_simulation()
