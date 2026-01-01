import torch
import torch.nn as nn
import numpy as np
import os

# 定义你的模型结构以便加载权重
class LeNet5(nn.Module):
    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(1, 6, kernel_size=5, padding=2),
            nn.ReLU(),
            nn.MaxPool2d(kernel_size=2, stride=2),
            nn.Conv2d(6, 16, kernel_size=5),
            nn.ReLU(),
            nn.MaxPool2d(kernel_size=2, stride=2)
        )
        self.classifier = nn.Sequential(
            nn.Flatten(),
            nn.Linear(16*5*5, 120),
            nn.ReLU(inplace=True),
            nn.Linear(120, 84),
            nn.ReLU(inplace=True),
            nn.Linear(84, 10)
        )

def quantize(tensor, scale_factor=1.0):
    val = tensor * scale_factor
    val = torch.clamp(torch.round(val), -128, 127)
    return val.int().numpy()

def write_linear_hex_file(filepath, data_array):
    """
    导出线性 Hex 文件 (每行 1 个字节)
    data_array: numpy array or list of integers
    """
    # 展平数组 (Flatten)
    flat_data = data_array.flatten()

    with open(filepath, 'w') as f:
        for val in flat_data:
            # 确保是 8-bit (两位 Hex)
            val = val & 0xFF
            f.write(f"{val:02X}\n")
    print(f"Exported: {filepath} (Count: {len(flat_data)})")

def write_bias_file(filepath, data_list):
    """
    导出 Bias (每行 1 个 32-bit 数据)
    """
    with open(filepath, 'w') as f:
        for val in data_list:
            val = val & 0xFFFFFFFF
            f.write(f"{val:08X}\n")
    print(f"Exported: {filepath}")

def main():
    # ======================================================
    # 1. 路径自动定位
    # ======================================================
    script_dir = os.path.dirname(os.path.abspath(__file__))
    weights_path = os.path.join(script_dir, "lenet_weights.pth")
    output_dir = os.path.join(script_dir, "../../../hardware/rtl/init_files")
    os.makedirs(output_dir, exist_ok=True)

    print(f"Script Dir: {script_dir}")
    print(f"Weights Path: {weights_path}")
    print(f"Output Dir: {output_dir}")

    # ======================================================
    # 2. Load Model
    # ======================================================
    device = torch.device('cpu')
    model = LeNet5()
    try:
        try:
            model.load_state_dict(torch.load(weights_path, map_location=device, weights_only=False))
        except TypeError:
            model.load_state_dict(torch.load(weights_path, map_location=device))
        print("Model loaded successfully.")
    except FileNotFoundError:
        print(f"Error: File not found at {weights_path}")
        return

    # ======================================================
    # 3. Extract and Export (Linear Format)
    # ======================================================
    Q_SCALE = 64.0

    # --- FC1 (120, 400) ---
    fc1_w = model.classifier[1].weight.data
    fc1_b = model.classifier[1].bias.data
    fc1_w_q = quantize(fc1_w, Q_SCALE)      # Shape: [120, 400]
    fc1_b_q = quantize(fc1_b, Q_SCALE*Q_SCALE)

    # 导出权重：PyTorch 默认是 [Out_Ch, In_Ch]
    # 我们的硬件是按输出神经元并行/分批处理的，所以直接导出即可
    # TB 会按顺序读取加载到 DRAM
    write_linear_hex_file(os.path.join(output_dir, "fc1_weights.hex"), fc1_w_q)
    write_bias_file(os.path.join(output_dir, "fc1_bias.hex"), fc1_b_q)

    # --- FC2 (84, 120) ---
    fc2_w = model.classifier[3].weight.data
    fc2_b = model.classifier[3].bias.data
    fc2_w_q = quantize(fc2_w, Q_SCALE)
    fc2_b_q = quantize(fc2_b, Q_SCALE*Q_SCALE)

    write_linear_hex_file(os.path.join(output_dir, "fc2_weights.hex"), fc2_w_q)
    write_bias_file(os.path.join(output_dir, "fc2_bias.hex"), fc2_b_q)

    # --- FC3 (10, 84) ---
    fc3_w = model.classifier[5].weight.data
    fc3_b = model.classifier[5].bias.data
    fc3_w_q = quantize(fc3_w, Q_SCALE)
    fc3_b_q = quantize(fc3_b, Q_SCALE*Q_SCALE)

    # 注意：FC3 只有 10 个输出。
    # 硬件一次处理 100 个，但有长度检查 (cnt < 10)，所以不会计算多余的。
    # Testbench 会尝试读取 DRAM，只要 DRAM 里有这 10 行的数据即可。
    # 不需要额外的 Padding，因为 TB 的 dram_fc3_weights 数组足够大，未初始化的部分默认为 0/X
    # 只要前 10 个神经元的权重是对的就行。

    write_linear_hex_file(os.path.join(output_dir, "fc3_weights.hex"), fc3_w_q)
    write_bias_file(os.path.join(output_dir, "fc3_bias.hex"), fc3_b_q)

    print("All FC weights exported successfully (Linear 8-bit format).")

if __name__ == "__main__":
    main()
