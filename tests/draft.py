'''
 @Author: Qiao Zhang
 @Date: 2025-12-23 10:05:00
 @LastEditTime: 2025-12-27 19:24:11
 @LastEditors: Qiao Zhang
 @Description:
 @FilePath: /cnn/tests/draft.py
'''
import numpy as np

matrix = [
    # 行1（原列6）
    [0xee, 0xf9, 0xfd, 0x1a, 0x1f, 0xfc, 0x03, 0x12, 0x19, 0xfb, 0xe3, 0xf6, 0x04, 0x27, 0x15, 0xe0, 0x16, 0x0a, 0x22, 0x27, 0xeb, 0xea, 0x1a, 0x1f, 0x0b],
    # 行2（原列5）
    [0xd1, 0xf8, 0x22, 0x26, 0x11, 0xda, 0xb7, 0xc7, 0x0e, 0x0f, 0xf9, 0xdd, 0xb4, 0xb4, 0xdf, 0x21, 0x1c, 0xfa, 0xdf, 0xd8, 0x1c, 0x11, 0x28, 0x04, 0xf1],
    # 行3（原列4）
    [0xfc, 0x16, 0x02, 0x06, 0x23, 0xfc, 0xfa, 0xfd, 0x29, 0x1c, 0x1d, 0x21, 0x1b, 0x02, 0x10, 0x21, 0xf9, 0x03, 0x0e, 0xfa, 0x1b, 0x10, 0xda, 0xdc, 0xd8],
    # 行4（原列3）
    [0x0a, 0x19, 0x13, 0xdd, 0xf3, 0x0a, 0x0c, 0xe2, 0xe7, 0xf1, 0x26, 0x1e, 0xe8, 0xe2, 0x04, 0x2c, 0x27, 0x17, 0x0d, 0x02, 0x14, 0x1e, 0x30, 0x1f, 0xf7],
    # 行5（原列2）
    [0x0f, 0xdf, 0xcd, 0xdd, 0x05, 0x10, 0xe2, 0xd4, 0xee, 0x03, 0x1b, 0x16, 0x14, 0xff, 0x22, 0xf7, 0x18, 0x13, 0x2b, 0x2a, 0x2d, 0x3b, 0x2f, 0x20, 0x24],
    # 行6（原列1）
    [0x20, 0x13, 0xfc, 0xe5, 0xef, 0x2d, 0x0b, 0xff, 0xe8, 0xdc, 0x27, 0x08, 0x07, 0xc1, 0xe8, 0x32, 0xfe, 0xe3, 0xcb, 0x0b, 0x12, 0x06, 0xeb, 0xe6, 0x00]
]

# 如果需要十进制表示，可以转换：
matrix_decimal = [[int(x) if x <= 0x7f else int(x) - 256 for x in row] for row in matrix]
# 注意：如果原意是无符号，就不用减 256

weights = np.array(matrix_decimal)
# 原始数据列表（十六进制字符串转十进制整数）
data_hex = [
    "00", "01", "01", "02", "02", "03", "03", "04", "04", "05", "05", "06", "06", "07", "07", "08", "08", "09", "09",
    "0a", "0a", "0b", "0b", "0c", "0c", "0d", "0d", "0e", "0e", "0f", "0f", "10", "10", "11", "11", "12", "12", "13", "13",
    "14", "14", "15", "15", "16", "16", "17", "17", "18", "18", "19", "19", "1a", "1a", "1b", "1b", "1c", "1c", "1d", "1d",
    "1e", "1e", "1f", "1f", "20", "20", "21", "21", "22", "22", "23", "23", "24", "24", "25", "25", "26", "26", "27", "27",
    "28", "28", "29", "29", "2a", "2a", "2b", "2b", "2c", "2c", "2d", "2d", "2e", "2e", "2f", "2f", "30", "30", "31", "31",
    "32", "32", "33", "33", "34", "34", "35", "35", "36", "36", "37", "37", "38", "38", "39", "39", "3a", "3a", "3b", "3b",
    "3c", "3c", "3d", "3d", "3e", "3e", "3f", "3f", "40", "40", "41", "41", "42", "42", "43", "43", "44", "44", "45", "45",
    "46", "46", "47", "47", "48", "48", "49", "49", "4a", "4a", "4b", "4b", "4c", "4c", "4d", "4d", "4e", "4e", "4f", "4f",
    "50", "50", "51", "51", "52", "52", "53", "53", "54", "54", "55", "55", "56", "56", "57", "57", "58", "58", "59", "59",
    "5a", "5a", "5b", "5b", "5c", "5c", "5d", "5d", "5e", "5e", "5f", "5f", "60", "60", "61", "61", "62", "62", "63", "63",
    "64", "64", "65", "65", "66", "66", "67", "67", "68", "68", "69", "69", "6a", "6a", "6b", "6b", "6c", "6c", "6d", "6d",
    "6e", "6e", "6f", "6f", "70", "70", "71", "71", "72", "72", "73", "73", "74", "74", "75", "75", "76", "76", "77", "77",
    "78", "78", "79", "79", "7a", "7a", "7b", "7b", "7c", "7c", "7d", "7d", "7e", "7e", "7f", "7f",
    "00", "01", "01", "02", "02", "03", "03", "04", "04", "05", "05", "06", "06", "07", "07", "08", "08", "09", "09",
    "0a", "0a", "0b", "0b", "0c", "0c", "0d", "0d", "0e", "0e", "0f", "0f", "10", "10", "11", "11", "12", "12", "13", "13",
    "14", "14", "15", "15", "16", "16", "17", "17", "18", "18", "19", "19", "1a", "1a", "1b", "1b", "1c", "1c", "1d", "1d",
    "1e", "1e", "1f", "1f", "20", "20", "21", "21", "22", "22", "23", "23", "24", "24", "25", "25", "26", "26", "27", "27",
    "28", "28", "29", "29", "2a", "2a", "2b", "2b", "2c", "2c", "2d", "2d", "2e", "2e", "2f", "2f", "30", "30", "31", "31",
    "32", "32", "33", "33", "34", "34", "35", "35", "36", "36", "37", "37", "38", "38", "39", "39", "3a", "3a", "3b", "3b",
    "3c", "3c", "3d", "3d", "3e", "3e", "3f", "3f", "40", "40", "41", "41", "42", "42", "43", "43", "44", "44", "45", "45",
    "46", "46", "47", "47", "48", "48", "49", "49", "4a", "4a", "4b", "4b", "4c", "4c", "4d", "4d", "4e", "4e", "4f", "4f",
    "50", "50", "51", "51", "52", "52", "53", "53", "54", "54", "55", "55", "56", "56", "57", "57", "58", "58", "59", "59",
    "5a", "5a", "5b", "5b", "5c", "5c", "5d", "5d", "5e", "5e", "5f", "5f", "60", "60", "61", "61", "62", "62", "63", "63",
    "64", "64", "65", "65", "66", "66", "67", "67", "68", "68", "69", "69", "6a", "6a", "6b", "6b", "6c", "6c", "6d", "6d",
    "6e", "6e", "6f", "6f", "70", "70", "71", "71", "72", "72", "73", "73", "74", "74", "75", "75", "76", "76", "77", "77",
    "78", "78", "79", "79", "7a", "7a", "7b", "7b", "7c", "7c", "7d", "7d", "7e", "7e", "7f", "7f",
    "00", "01", "01", "02", "02", "03", "03", "04", "04", "05", "05", "06", "06", "07", "07", "08", "08", "09", "09",
    "0a", "0a", "0b", "0b", "0c", "0c", "0d", "0d", "0e", "0e", "0f", "0f", "10", "10", "11", "11", "12", "12", "13", "13",
    "14", "14", "15", "15", "16", "16", "17", "17", "18", "18", "19", "19", "1a", "1a", "1b", "1b", "1c", "1c", "1d", "1d",
    "1e", "1e", "1f", "1f", "20", "20", "21", "21", "22", "22", "23", "23", "24", "24", "25", "25", "26", "26", "27", "27",
    "28", "28", "29", "29", "2a", "2a", "2b", "2b", "2c", "2c", "2d", "2d", "2e", "2e", "2f", "2f", "30", "30", "31", "31",
    "32", "32", "33", "33", "34", "34", "35", "35", "36", "36", "37", "37", "38", "38", "39", "39", "3a", "3a", "3b", "3b",
    "3c", "3c", "3d", "3d", "3e", "3e", "3f", "3f", "40", "40", "41", "41", "42", "42", "43", "43", "44", "44", "45", "45",
    "46", "46", "47", "47", "48", "48", "49", "49", "4a", "4a", "4b", "4b", "4c", "4c", "4d", "4d", "4e", "4e", "4f", "4f",
    "50", "50", "51", "51", "52", "52", "53", "53", "54", "54", "55", "55", "56", "56", "57", "57", "58", "58", "59", "59",
    "5a", "5a", "5b", "5b", "5c", "5c", "5d", "5d", "5e", "5e", "5f", "5f", "60", "60", "61", "61", "62", "62", "63", "63",
    "64", "64", "65", "65", "66", "66", "67", "67", "68", "68", "69", "69", "6a", "6a", "6b", "6b", "6c", "6c", "6d", "6d",
    "6e", "6e", "6f", "6f", "70", "70", "71", "71", "72", "72", "73", "73", "74", "74", "75", "75", "76", "76", "77", "77",
    "78", "78", "79", "79", "7a", "7a", "7b", "7b", "7c", "7c", "7d", "7d", "7e", "7e", "7f", "7f",
    "00", "01", "01", "02", "02", "03", "03", "04", "04", "05", "05", "06", "06", "07", "07", "08", "08", "09", "09"
]

# 转换为十进制整数（无符号 0-255）
data = [int(h, 16) for h in data_hex]

# 确保长度为 28*28 = 784
assert len(data) == 784, f"数据长度应为784，实际为{len(data)}"

# 重塑为 28x28 矩阵
matrix_28x28 = [data[i*28:(i+1)*28] for i in range(28)]

inputs = np.array(matrix_28x28)
weights_row = 4
# input matrix configuration
    # row
input_start_row = 0
input_end_row = 5
    # column
input_start_col = 23
input_end_col = 28

# Slice
w_tile = weights[weights_row,:]
i_tile = inputs[input_start_row:input_end_row,input_start_col:input_end_col].reshape(1,-1)
# hex_func = np.vectorize(lambda x: f"{x:x}")
# hex_mat = hex_func(inputs[1:6,0:5])
# print(hex_mat)
print("================= Expect =================")
print(f"Weights Matrix:W[{weights_row},:]")
print(f"Input Matrix:I[{input_start_row}:{input_end_row},{input_start_col}:{input_end_col}]")
print("Expect:",np.sum(w_tile*i_tile))
# weights_row = 1
# # input matrix configuration
#     # row
# input_start_row = 0
# input_end_row = 5
#     # column
# input_start_col = 0
# input_end_col = 5

# # Slice
# w_tile = weights[weights_row,:]
# i_tile = inputs[input_start_row:input_end_row,input_start_col:input_end_col].reshape(1,-1)

# print("================= Expect =================")
# print(f"Weights Matrix:W[{weights_row},:]")
# print(f"Input Matrix:I[{input_start_row}:{input_end_row},{input_start_col}:{input_end_col}]")
# print("Expect:",np.sum(w_tile*i_tile))

# weights_row = 1
# # input matrix configuration
#     # row
# input_start_row = 3
# input_end_row = 8
#     # column
# input_start_col = 93
# input_end_col = 98

# # Slice
# w_tile = weights[weights_row,:]
# i_tile = inputs[input_start_row:input_end_row,input_start_col:input_end_col].reshape(1,-1)

# print("================= Expect =================")
# print(f"Weights Matrix:W[{weights_row},:]")
# print(f"Input Matrix:I[{input_start_row}:{input_end_row},{input_start_col}:{input_end_col}]")
# print("Expect:",np.sum(w_tile*i_tile))

# weights_row = 2
# # input matrix configuration
#     # row
# input_start_row = 0
# input_end_row = 5
#     # column
# input_start_col = 0
# input_end_col = 5

# # Slice
# w_tile = weights[weights_row,:]
# i_tile = inputs[input_start_row:input_end_row,input_start_col:input_end_col].reshape(1,-1)

# print("================= Expect =================")
# print(f"Weights Matrix:W[{weights_row},:]")
# print(f"Input Matrix:I[{input_start_row}:{input_end_row},{input_start_col}:{input_end_col}]")
# print("Expect:",np.sum(w_tile*i_tile))

# weights_row = 2
# # input matrix configuration
#     # row
# input_start_row = 3
# input_end_row = 8
#     # column
# input_start_col = 93
# input_end_col = 98

# # Slice
# w_tile = weights[weights_row,:]
# i_tile = inputs[input_start_row:input_end_row,input_start_col:input_end_col].reshape(1,-1)

# print("================= Expect =================")
# print(f"Weights Matrix:W[{weights_row},:]")
# print(f"Input Matrix:I[{input_start_row}:{input_end_row},{input_start_col}:{input_end_col}]")
# print("Expect:",np.sum(w_tile*i_tile))

# weights_row = 3
# # input matrix configuration
#     # row
# input_start_row = 0
# input_end_row = 5
#     # column
# input_start_col = 0
# input_end_col = 5

# # Slice
# w_tile = weights[weights_row,:]
# i_tile = inputs[input_start_row:input_end_row,input_start_col:input_end_col].reshape(1,-1)

# print("================= Expect =================")
# print(f"Weights Matrix:W[{weights_row},:]")
# print(f"Input Matrix:I[{input_start_row}:{input_end_row},{input_start_col}:{input_end_col}]")
# print("Expect:",np.sum(w_tile*i_tile))

# weights_row = 3
# # input matrix configuration
#     # row
# input_start_row = 3
# input_end_row = 8
#     # column
# input_start_col = 93
# input_end_col = 98

# # Slice
# w_tile = weights[weights_row,:]
# i_tile = inputs[input_start_row:input_end_row,input_start_col:input_end_col].reshape(1,-1)

# print("================= Expect =================")
# print(f"Weights Matrix:W[{weights_row},:]")
# print(f"Input Matrix:I[{input_start_row}:{input_end_row},{input_start_col}:{input_end_col}]")
# print("Expect:",np.sum(w_tile*i_tile))

# weights_row = 4
# # input matrix configuration
#     # row
# input_start_row = 0
# input_end_row = 5
#     # column
# input_start_col = 0
# input_end_col = 5

# # Slice
# w_tile = weights[weights_row,:]
# i_tile = inputs[input_start_row:input_end_row,input_start_col:input_end_col].reshape(1,-1)

# print("================= Expect =================")
# print(f"Weights Matrix:W[{weights_row},:]")
# print(f"Input Matrix:I[{input_start_row}:{input_end_row},{input_start_col}:{input_end_col}]")
# print("Expect:",np.sum(w_tile*i_tile))

# weights_row = 4
# # input matrix configuration
#     # row
# input_start_row = 3
# input_end_row = 8
#     # column
# input_start_col = 93
# input_end_col = 98

# # Slice
# w_tile = weights[weights_row,:]
# i_tile = inputs[input_start_row:input_end_row,input_start_col:input_end_col].reshape(1,-1)

# print("================= Expect =================")
# print(f"Weights Matrix:W[{weights_row},:]")
# print(f"Input Matrix:I[{input_start_row}:{input_end_row},{input_start_col}:{input_end_col}]")
# print("Expect:",np.sum(w_tile*i_tile))

# weights_row = 5
# # input matrix configuration
#     # row
# input_start_row = 0
# input_end_row = 5
#     # column
# input_start_col = 0
# input_end_col = 5

# # Slice
# w_tile = weights[weights_row,:]
# i_tile = inputs[input_start_row:input_end_row,input_start_col:input_end_col].reshape(1,-1)

# print("================= Expect =================")
# print(f"Weights Matrix:W[{weights_row},:]")
# print(f"Input Matrix:I[{input_start_row}:{input_end_row},{input_start_col}:{input_end_col}]")
# print("Expect:",np.sum(w_tile*i_tile))


# print("================= Error Speculate =================")

