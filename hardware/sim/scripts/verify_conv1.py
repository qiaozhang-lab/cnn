
import numpy as np
import sys

# ================= 配置 =================
WEIGHTS_FILE = "conv1_weights.hex"
BIAS_FILE    = "conv1_bias.hex"
IMAGE_FILE   = "input_image.hex"
SIM_OUT_FILE = "sim_output.txt"

# 硬件参数
IMG_W = 28
KERNEL = 5
OUT_W = 24  # 28 - 5 + 1
CHANNELS = 6
# =======================================

def hex2int(s, bits=32):
    """转换 Hex 补码字符串为整数"""
    val = int(s, 16)
    if val & (1 << (bits-1)):
        val -= (1 << bits)
    return val

def load_data():
    print("Loading Hardware Init Files...")

    # 1. Load Bias
    bias = []
    with open(BIAS_FILE) as f:
        for line in f:
            bias.append(hex2int(line.strip(), 32))

    # 2. Load Weights (Format: MSB=Ch5 ... LSB=Ch0)
    w_raw = [[], [], [], [], [], []] # 6 Channels
    with open(WEIGHTS_FILE) as f:
        for line in f:
            val = int(line.strip(), 16)
            for k in range(6):
                byte = (val >> (k*8)) & 0xFF
                if byte & 0x80: byte -= 0x100
                w_raw[k].append(byte)

    # Reshape to (6, 5, 5)
    weights = np.array(w_raw).reshape(6, 5, 5)

    # 3. Load Image
    img_data = []
    with open(IMAGE_FILE) as f:
        for line in f:
            img_data.append(hex2int(line.strip(), 8))
    img = np.array(img_data).reshape(28, 28)

    # 4. Load Simulation Output
    print(f"Loading Simulation Output: {SIM_OUT_FILE}...")
    sim_data = []
    try:
        with open(SIM_OUT_FILE) as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) == 6:
                    sim_data.append([int(p) for p in parts])
        sim_arr = np.array(sim_data) # Shape (576, 6)
        # Reshape to (H, W, Ch) -> (24, 24, 6)
        sim_arr = sim_arr.reshape(OUT_W, OUT_W, 6)
    except FileNotFoundError:
        print("Error: sim_output.txt not found. Please run VCS simulation first.")
        sys.exit(1)

    return img, weights, bias, sim_arr

def calculate_golden(img, weights, bias):
    print("Calculating Golden Model in Python (Valid Mode)...")
    # Output shape: (24, 24, 6)
    golden = np.zeros((OUT_W, OUT_W, CHANNELS), dtype=np.int32)

    for r in range(OUT_W):
        for c in range(OUT_W):
            # Patch is 5x5
            patch = img[r : r+KERNEL, c : c+KERNEL]

            for k in range(CHANNELS):
                # Conv + Bias
                conv = np.sum(patch * weights[k])
                golden[r, c, k] = conv + bias[k]

    return golden

def compare(golden, sim):
    print("\nStarting Comparison...")

    diff = golden - sim
    errors = np.nonzero(diff) # Tuple of arrays indices
    num_errors = len(errors[0])

    if num_errors == 0:
        print("\n" + "="*60)
        print("🎉 SUCCESS: ALL 3456 PIXELS MATCH! HARDWARE IS CORRECT.")
        print("="*60)
    else:
        print(f"\n❌ FAIL: Found {num_errors} mismatches.")
        print("-" * 60)
        print(f"{'Idx(R,C,K)':<15} | {'Exp (Py)':<10} | {'Act (RTL)':<10} | {'Diff'}")
        print("-" * 60)

        count = 0
        for i in range(num_errors):
            r = errors[0][i]
            c = errors[1][i]
            k = errors[2][i]

            exp = golden[r, c, k]
            act = sim[r, c, k]
            print(f"({r:2},{c:2},{k})     | {exp:<10} | {act:<10} | {exp-act}")

            count += 1
            if count > 10:
                print("... (truncating errors)")
                break

if __name__ == "__main__":
    img, w, b, sim = load_data()
    golden = calculate_golden(img, w, b)
    compare(golden, sim)
