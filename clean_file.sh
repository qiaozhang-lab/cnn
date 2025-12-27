#!/usr/bin/env bash
mkdir -p hardware/rtl/top
mkdir -p hardware/rtl/compute
mkdir -p hardware/sim/scripts
mkdir -p hardware/sim/output

# 2. 移动 Python 脚本 (清理 init_files)
mv hardware/rtl/init_files/*.py hardware/sim/scripts/
mv hardware/rtl/init_files/*.txt hardware/sim/output/

# 3. 移动 Top Wrapper
mv hardware/rtl/wrapper/systolic_wrapper.sv hardware/rtl/top/

# 4. 移动 ARR 到 Control (因为它本质是控制器)
mv hardware/rtl/wrapper/active_row_register.sv hardware/rtl/control/
# 删除空的 wrapper 文件夹
rmdir hardware/rtl/wrapper

# 5. 重组 Compute (原 ip)
mv hardware/rtl/ip/systolic_arrays/* hardware/rtl/compute/
rm -rf hardware/rtl/ip

# 6. 移动 Result Handler 到 Post Process
mv hardware/rtl/memory/result_handler.sv hardware/rtl/post_process/

# 7. 清理不用的旧文件 (如果你确定不用了)
rm hardware/rtl/control/weight_addr_gen.sv
rm hardware/rtl/control/img2col_addr_gen.sv
