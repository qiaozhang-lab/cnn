/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-22
 * @Description: Testbench for Joint Verification (Full Image Simulation).
 *               - Simulates Wrapper logic (Auto-restart & Done generation).
 *               - Verifies Input Buffer stops reading ROM at end of image.
 */

`timescale 1ns/1ps
`include "definitions.sv"

module tb_active_row_register;

    // =========================================================
    // 1. Simulation Parameters
    // =========================================================
    parameter int CLK_PERIOD = 10;

    // LeNet: 28x28 Input, 5x5 Kernel -> 24x24 Output
    parameter int TB_IMG_W    = 28;
    parameter int TB_IMG_H    = 28;
    logic [3 :0]  TB_KERNEL_R = 5;

    // Calculated Output Height
    int total_output_rows;

    // =========================================================
    // 2. Signals
    // =========================================================
    logic           clk_i;
    logic           rst_async_n_i;
    logic           start_i;

    // Simulation of Wrapper's Done Signal
    logic           sim_done_i;
    int             rows_processed_cnt;

    // Interconnects
    logic [ROM_IMAGE_DEPTH_W-1 : 0] rom_addr;
    logic                           rom_rd_en;
    logic [INT_WIDTH-1 : 0]         rom_data;

    logic [IB_BANK_W-1 : 0]                   ib_pop;
    logic [IB_BANK_W-1 : 0][INT_WIDTH-1 : 0]  ib_data_out;
    logic                                     ib_ready;

    logic                                     arr_busy;
    logic                                     arr_row_done;
    logic [MATRIX_B_COL-1 : 0]                north_valid;
    logic [MATRIX_B_COL-1 : 0][INT_WIDTH-1 : 0] north_data;

    // =========================================================
    // 3. Instantiations
    // =========================================================
    rom_image #(
        .WIDTH      (8),
        .DEPTH      (TB_IMG_W * TB_IMG_H),
        .INIT_FILE  (ROM_IMAGE_INIT_FILE)
    ) u_rom (
        .clk_i(clk_i), .rd_en(rom_rd_en), .addr_i(rom_addr), .rd_o(rom_data)
    );

    input_buffer_bank u_ib (
        .clk_i          (clk_i),
        .rst_async_n_i  (rst_async_n_i),
        .start_i        (start_i),

        // Config
        .cfg_img_w_i    (TB_IMG_W),
        .cfg_img_h_i    (TB_IMG_H),     // 【新增】
        .cfg_kernel_r_i (TB_KERNEL_R),

        // Control
        .sa_done_i     (sim_done_i),   // 【新增】模拟的全局完成信号

        .rom_addr_o     (rom_addr),
        .rom_rd_en_o    (rom_rd_en),
        .rom_data_i     (rom_data),
        .pop_i          (ib_pop),
        .data_out_o     (ib_data_out),
        .pre_wave_done_i(arr_row_done),
        .ib_ready_o     (ib_ready)
    );

    active_row_register u_arr (
        .clk_i          (clk_i),
        .rst_async_n_i  (rst_async_n_i),
        .start_i        (start_i),
        .cfg_img_w_i    (TB_IMG_W),
        .cfg_kernel_r_i (TB_KERNEL_R),
        .ib_ready_i     (ib_ready),
        .busy_o         (arr_busy),
        .row_done_o     (arr_row_done),
        .ib_pop_o       (ib_pop),
        .ib_data_i      (ib_data_out),
        .north_valid_o  (north_valid),
        .north_data_o   (north_data)
    );

    // =========================================================
    // 4. Clock Gen
    // =========================================================
    initial begin
        clk_i = 0;
        forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end

    // =========================================================
    // 5. Automatic Control Logic (Simulating Wrapper)
    // =========================================================
    initial begin
        total_output_rows = TB_IMG_H - TB_KERNEL_R + 1; // 28 - 5 + 1 = 24
        rows_processed_cnt = 0;
        sim_done_i = 0;
    end

    // 自动重启与计数逻辑
    always @(posedge clk_i) begin
        if (rst_async_n_i && ib_ready) begin // Only active when system is running
            if (arr_row_done) begin
                rows_processed_cnt++;
                $display("\n[TB] Row %0d Finished at time %t", rows_processed_cnt, $time);

                if (rows_processed_cnt == total_output_rows) begin
                    $display("[TB] All %0d Rows Processed. Asserting DONE.", total_output_rows);
                    sim_done_i <= 1; // 触发 IB 复位
                end else begin
                    // Trigger next row automatically
                    // 在 TB 中模拟 Wrapper 的行为：只要没做完，就再给一次 Start
                    // 注意：这里使用非阻塞赋值模拟寄存器行为，或者使用延时生成脉冲
                    #1;
                    // 简单的脉冲生成 (Blocking inside always is fine for TB control)
                    start_i = 1;
                    @(posedge clk_i);
                    start_i = 0;
                end
            end
        end
    end

    // 监控 ROM 读取行为
    int rom_read_cnt;
    always @(posedge clk_i) begin
        if (!rst_async_n_i) rom_read_cnt = 0;
        else if (rom_rd_en) rom_read_cnt++;
    end

    // =========================================================
    // 6. Test Sequence
    // =========================================================
    initial begin
        rst_async_n_i = 0;
        start_i       = 0;

        $display("\n[TB] Starting Full Image Verification...");
        $display("[TB] Target Output Rows: %0d", TB_IMG_H - TB_KERNEL_R + 1);

        #(CLK_PERIOD * 5);
        rst_async_n_i = 1;
        #(CLK_PERIOD * 2);

        // --- Step 1: Initial Start ---
        $display("[TB] Triggering Initial Prefetch...");
        @(negedge clk_i); start_i = 1;
        @(negedge clk_i); start_i = 0;

        // --- Step 2: Wait for Prefetch ---
        wait(ib_ready);
        $display("[TB] IB Prefetch Done. Starting Auto-Run Loop...");

        // --- Step 3: Trigger First Row (The loop above handles the rest) ---
        @(negedge clk_i); start_i = 1;
        @(negedge clk_i); start_i = 0;

        // --- Step 4: Wait for Completion ---
        wait(sim_done_i);

        // Wait a bit to see IB go to IDLE
        #(CLK_PERIOD * 10);

        $display("\n[TB] Simulation Finished.");
        $display("[TB] Total ROM Reads: %0d cycles", rom_read_cnt);

        // Check ROM Reads:
        // Should be Total Pixels = 28 * 28 = 784
        if (rom_read_cnt == TB_IMG_W * TB_IMG_H)
            $display("[TB] CHECK PASS: ROM read exactly %0d pixels.", rom_read_cnt);
        else
            $display("[TB] CHECK FAIL: ROM read %0d pixels (Expected %0d).", rom_read_cnt, TB_IMG_W * TB_IMG_H);

        $finish;
    end

    // =========================================================
    // 7. Visualizer (Optional - Simplified)
    // =========================================================
    // Only print first few cols to keep log clean

    // string line_buffer;
    // initial begin
    //     forever begin
    //         @(posedge clk_i);
    //         if (arr_busy && north_valid[0]) begin
    //             $sformat(line_buffer, "T=%0t | ", $time);
    //             for (int c = 0; c < 5; c++) begin // Print first 5 cols
    //                 if (north_valid[c]) $sformat(line_buffer, "%s%2h ", line_buffer, north_data[c]);
    //                 else $sformat(line_buffer, "%s.. ", line_buffer);
    //             end
    //             $display("%s", line_buffer);
    //         end
    //     end
    // end


endmodule
