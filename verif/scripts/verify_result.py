'''
 @Author: Qiao Zhang
 @Date: 2025-12-24 16:50:55
 @LastEditTime: 2025-12-24 17:02:23
 @LastEditors: Qiao Zhang
 @Description: Verify the simulation result and Python result
 @FilePath: /cnn/verif/scripts/verify_result.py
'''
import numpy as np

# ================= 配置区域 =================
# 这里的参数必须与你的 LeNet 设定一致
IMG_H = 24  # Output Height (28 - 5 + 1)
IMG_W = 24  # Output Width
CHANNELS = 6

GOLDEN_FILE = "../conv1_golden_out.hex"
SIM_FILE    = "../sim_output.txt"

# 关键设置：你的 Golden 文件是怎么生成的？
# True:  如果是直接对 PyTorch Tensor 做 flatten() 或者 .tolist() (通常是 NCHW 格式)
# False: 如果你是写了3层循环 (Row->Col->Ch) 导出的
IS_GOLDEN_CHANNEL_FIRST = True
# ===========================================

def hex_to_signed(hex_str):
    """将 32位 Hex 补码字符串转换为 Python 整数"""
    # 1. 转为无符号整数
    val = int(hex_str, 16)
    # 2. 处理符号位 (32-bit Two's Complement)
    if val & (1 << 31):
        val -= (1 << 32)
    return val

def load_golden(filepath):
    """读取 Golden Hex 文件"""
    print(f"Loading Golden: {filepath} ...")
    data = []
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                data.append(hex_to_signed(line))

    arr = np.array(data, dtype=np.int32)

    # 检查数据量是否正确
    expected_len = IMG_H * IMG_W * CHANNELS
    if len(arr) != expected_len:
        print(f"Error: Golden file length {len(arr)} != Expected {expected_len}")
        return None

    # 处理数据排布 (Layout)
    if IS_GOLDEN_CHANNEL_FIRST:
        # 假设 Golden 是 [Channel, Height, Width]
        # 先 reshape 成 (6, 24, 24)
        arr = arr.reshape(CHANNELS, IMG_H, IMG_W)
        # 再转置成 (24, 24, 6) 以匹配硬件输出 (Height, Width, Channel)
        arr = arr.transpose(1, 2, 0)
    else:
        # 假设 Golden 已经是 [Height, Width, Channel]
        arr = arr.reshape(IMG_H, IMG_W, CHANNELS)

    return arr

def load_sim(filepath):
    """读取 Simulation Decimal 文件"""
    print(f"Loading Sim:    {filepath} ...")
    data = []
    with open(filepath, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == CHANNELS:
                # 硬件输出的一行包含 6 个通道的十进制数
                row_vals = [int(p) for p in parts]
                data.append(row_vals)

    arr = np.array(data, dtype=np.int32)

    # 应该是 (576, 6) -> reshape 为 (24, 24, 6)
    try:
        arr = arr.reshape(IMG_H, IMG_W, CHANNELS)
    except ValueError:
        print(f"Error: Sim file shape mismatch. Read {arr.shape}, Expected ({IMG_H*IMG_W}, {CHANNELS})")
        return None

    return arr

def compare(golden, sim):
    print("\nComparing...")

    # 计算差值
    diff = golden - sim

    # 统计错误
    errors = np.nonzero(diff)
    num_errors = len(errors[0])

    if num_errors == 0:
        print("\n✅ SUCCESS: All results match perfectly! (Bit-True)")
    else:
        print(f"\n❌ FAIL: Found {num_errors} mismatches.")
        print("-" * 60)
        print(f"{'Index (R,C,Ch)':<20} | {'Golden':<15} | {'Sim':<15} | {'Diff':<10}")
        print("-" * 60)

        # 打印前 10 个错误
        count = 0
        for r, c, k in zip(errors[0], errors[1], errors[2]):
            g_val = golden[r, c, k]
            s_val = sim[r, c, k]
            print(f"({r:2d}, {c:2d}, {k})      | {g_val:<15} | {s_val:<15} | {g_val-s_val}")
            count += 1
            if count >= 10:
                print("... (more errors omitted)")
                break

if __name__ == "__main__":
    golden_arr = load_golden(GOLDEN_FILE)
    sim_arr    = load_sim(SIM_FILE)

    if golden_arr is not None and sim_arr is not None:
        compare(golden_arr, sim_arr)
