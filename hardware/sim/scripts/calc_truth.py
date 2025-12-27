'''
 @Author: Qiao Zhang
 @Date: 2025-12-24 18:57:15
 @LastEditTime: 2025-12-24 19:00:05
 @LastEditors: Qiao Zhang
 @Description:
 @FilePath: /cnn/hardware/rtl/init_files/calc_truth.py
'''
import numpy as np
import sys

# ================= 配置 =================
WEIGHTS_FILE = "conv1_weights.hex"
BIAS_FILE    = "conv1_bias.hex"
IMAGE_FILE   = "input_image.hex"
GOLDEN_FILE  = "conv1_golden_out.hex" # 你的Golden文件路径
# =======================================

def hex2int(s, bits=32):
    val = int(s, 16)
    if val & (1 << (bits-1)):
        val -= (1 << bits)
    return val

def main():
    print("--- Starting Manual Calculation ---")

    # 1. 读取 Bias (6 lines)
    # Line 0 = Ch0 ?, Line 5 = Ch5 ?
    bias = []
    with open(BIAS_FILE) as f:
        for line in f:
            bias.append(hex2int(line.strip(), 32))
    print(f"Bias Loaded: {len(bias)} channels")
    print(f"  Bias[0] (Line 0): {bias[0]}")
    print(f"  Bias[5] (Line 5): {bias[5]}")

    # 2. 读取 Weights (25 lines, 48 bits each)
    # File Format assumption: MSB..LSB = Ch5..Ch0
    # Each line corresponds to a spatial kernel position (0..24)
    w_ch0 = []
    w_ch5 = []

    with open(WEIGHTS_FILE) as f:
        for line in f:
            val = int(line.strip(), 16)
            # Extract Ch0 (LSB, bits 7:0)
            ch0_byte = val & 0xFF
            if ch0_byte & 0x80: ch0_byte -= 0x100
            w_ch0.append(ch0_byte)

            # Extract Ch5 (MSB, bits 47:40)
            ch5_byte = (val >> 40) & 0xFF
            if ch5_byte & 0x80: ch5_byte -= 0x100
            w_ch5.append(ch5_byte)

    # Reshape to 5x5
    w0 = np.array(w_ch0).reshape(5, 5)
    w5 = np.array(w_ch5).reshape(5, 5)

    print("Weights Loaded.")
    print(f"  W_Ch0 (First 5): {w_ch0[:5]}")

    # 3. 读取 Image (28*28 lines)
    # Line 0 = (0,0), Line 1 = (0,1)...
    img_data = []
    with open(IMAGE_FILE) as f:
        for line in f:
            img_data.append(hex2int(line.strip(), 8))

    img = np.array(img_data).reshape(28, 28)
    print("Image Loaded.")
    print(f"  Img Top-Left 5x5:\n{img[0:5, 0:5]}")

    # 4. 计算 Output(0,0) 的真值
    # Convolve Top-Left 5x5 patch
    patch = img[0:5, 0:5]

    # Truth for Ch 0
    conv0 = np.sum(patch * w0)
    res0  = conv0 + bias[0]

    # Truth for Ch 5
    conv5 = np.sum(patch * w5)
    res5  = conv5 + bias[5]

    print("\n=== CALCULATED TRUTH (Output 0,0) ===")
    print(f"Channel 0 Expect: Conv({conv0}) + Bias({bias[0]}) = {res0}")
    print(f"Channel 5 Expect: Conv({conv5}) + Bias({bias[5]}) = {res5}")

    # 5. 检查 Golden File 第一个数是谁
    try:
        with open(GOLDEN_FILE) as f:
            first_line = f.readline().strip()
            golden_val = hex2int(first_line, 32)

        print("\n=== GOLDEN FILE CHECK ===")
        print(f"Golden File Line 0 Value: {golden_val}")

        if golden_val == res0:
            print(">>> MATCHES Channel 0! (Golden is Channel-First: Ch0, Ch1...)")
            print(">>> RTL Config Required: Row 0 maps to Ch 0.")
        elif golden_val == res5:
            print(">>> MATCHES Channel 5! (Golden is Reversed: Ch5, Ch4...)")
            print(">>> RTL Config Required: Row 0 maps to Ch 5.")
        else:
            print(">>> MISMATCH BOTH! Something is wrong with calculation or file order.")
    except Exception as e:
        print(f"Could not read golden file: {e}")

if __name__ == "__main__":
    main()
