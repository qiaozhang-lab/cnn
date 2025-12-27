'''
 @Author: Qiao Zhang
 @Date: 2025-12-28 02:00:33
 @LastEditTime: 2025-12-28 02:05:38
 @LastEditors: Qiao Zhang
 @Description:
 @FilePath: /cnn/model/src/LeNet/export_conv2.py
'''
import torch
import numpy as np

# 配置
SCALE_FACTOR = 128.0

def to_hex(val, width=8):
    mask = (1 << width) - 1
    return f"{(val & mask):0{width//4}x}"

def to_fixed(val):
    int_val = int(round(val * SCALE_FACTOR))
    return max(min(int_val, 127), -128)

def export_conv2():
    print("Loading model...")
    net = torch.load("./lenet_weights.pth", map_location='cpu')

    # Conv2 Weights: [16, 6, 5, 5] (Out, In, H, W)
    w = net['features.3.weight'].numpy()
    b = net['features.3.bias'].numpy()

    print(f"Conv2 Weight Shape: {w.shape}")

    # 我们需要分 3 组 (Passes)
    # Pass 1: Out Ch 0-5
    # Pass 2: Out Ch 6-11
    # Pass 3: Out Ch 12-15 (最后两个补0)

    hex_lines = []

    # 遍历 3 个 Pass
    for group in range(3):
        start_ch = group * 6
        print(f"Processing Group {group}: Out Channels {start_ch} to {min(start_ch+6, 16)-1}")

        # 遍历 Input Channels (0..5) - 这是 Wrapper 内部循环的顺序
        for in_ch in range(6):
            # 遍历 Kernel 空间 (5x5)
            for r in range(5):
                for s in range(5):
                    # 构造 48-bit 宽字
                    # 包含当前 Group 的 6 个输出通道的权重
                    line_hex = ""

                    # 倒序遍历 6 个输出位置 (MSB=Ch5, LSB=Ch0 relative to group)
                    # 之前的经验：Row 0 对应 LSB。Row 0 是 Group 中的第 0 个通道。
                    # 所以我们要把 Group+5 放在 MSB，Group+0 放在 LSB。
                    for k in range(5, -1, -1):
                        out_ch = start_ch + k

                        if out_ch < 16:
                            val = w[out_ch, in_ch, r, s]
                            fixed = to_fixed(val)
                        else:
                            fixed = 0 # Padding for last group

                        line_hex += to_hex(fixed, 8)

                    hex_lines.append(line_hex)

    # 保存文件
    with open("../../../hardware/rtl/init_files/conv2_weights.hex", "w") as f:
        f.write("\n".join(hex_lines))
    print("Saved conv2_weights.hex")

    # 导出 Bias (同样按 Group 分组)
    # Bias Buffer 也是 48-bit 宽 (6个32位)
    bias_lines = []
    for group in range(3):
        start_ch = group * 6
        # Bias 只存一行 (因为 Controller 每次只读地址 0)
        # 我们需要把 3 个 Group 的 Bias 存成 3 行？
        # 是的。Controller 在每个 Pass 会重载 Bias Buffer，或者 Bias Buffer 足够大？
        # 你的 Bias Buffer 深度是 64。我们可以把 3 个 Group 存到地址 0, 1, 2。
        # 并在 Controller 里配置读取偏移。

        # 这里我们按顺序导出所有 Bias，Controller 负责加载
        # 实际上 Bias Buffer 的 Loader 是把所有数据灌进去。
        # 我们假设 Bias Buffer 存了所有层的 Bias？或者每次只存一层的？
        # 为了简单，我们假设每次 Load Layer 时，Bias Buffer 重写。
        # 那么文件里应该包含所有 3 个 Group 的 Bias。

        # 每一行 Hex 包含 6 个 32-bit Bias
        # 依然是 Row 0 (LSB) -> Group+0
        line_hex = ""
        # 注意：Bias 文件格式通常是一行一个 32bit 数 (单列)。
        # 但是我们的 Loader 逻辑 (tb_lenet5_top) 是把 6 行拼成一个宽字写进去。
        # 所以我们这里导出单列格式。
        for k in range(6):
            out_ch = start_ch + k
            if out_ch < 16:
                val = b[out_ch]
                fixed = int(round(val * 128 * 128))
            else:
                fixed = 0
            bias_lines.append(to_hex(fixed, 32))

    with open("../../../hardware/rtl/init_files/conv2_bias.hex", "w") as f:
        f.write("\n".join(bias_lines))
    print("Saved conv2_bias.hex")

if __name__ == "__main__":
    export_conv2()
