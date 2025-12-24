/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-23
 * @Description: Top-Level Testbench for Systolic Wrapper.
 *               - Simulates full LeNet Layer 1 execution.
 *               - Captures results from Result Handler Memory.
 */

`timescale 1ns/1ps
`include "definitions.sv"

module tb_systolic_wrapper;

    // =========================================================
    // 1. Parameters
    // =========================================================
    parameter int CLK_PERIOD = 10;

    // LeNet Config
    parameter int TB_IMG_W    = 28;
    parameter int TB_IMG_H    = 28;
    parameter int TB_KERNEL_R = 5;

    // Calculated Output Size: 24x24
    parameter int OUT_W = TB_IMG_W - TB_KERNEL_R + 1;
    parameter int OUT_H = TB_IMG_H - TB_KERNEL_R + 1;

    // =========================================================
    // 2. Signals
    // =========================================================
    logic           clk_i;
    logic           rst_async_n_i;
    logic           start_i;
    logic           busy_o;
    logic           done_o;

    // Memory Interfaces (SRAM Write - Not used in this demo, we rely on ROMs)
    // In your wrapper, these are outputs/inputs for external SRAM,
    // but here we let the internal ROMs drive the logic.
    // Wait, check wrapper:
    // rom_rd_en_o, rom_addr_o are outputs. rom_data_i is input.
    // So we need to instantiate the Image ROM here in TB to feed the Wrapper.

    logic [ROM_IMAGE_DEPTH_W-1 : 0]      rom_addr;
    logic                                rom_rd_en;
    logic [INT_WIDTH-1 : 0]              rom_data;

    // Result Output (Direct from SA, but we will look into Result Handler Memory)
    logic [ACC_WIDTH-1 : 0]  result_o[MATRIX_A_ROW][MATRIX_B_COL];

    // =========================================================
    // 3. DUT Instantiation
    // =========================================================
    systolic_wrapper #(
        .PTR_WIDTH(32)
    ) u_dut (
        .clk_i          (clk_i),
        .rst_async_n_i  (rst_async_n_i),

        .cfg_img_w_i    (TB_IMG_W),
        .cfg_img_h_i    (TB_IMG_H),
        .cfg_kernel_r_i (TB_KERNEL_R),

        .start_i        (start_i),
        .busy_o         (busy_o),
        .done_o         (done_o),

        // Image ROM Interface (Wrapper is Master)
        .rom_addr_o     (rom_addr),
        .rom_rd_en_o    (rom_rd_en),
        .rom_data_i     (rom_data),

        .result_o       (result_o)
    );

    // =========================================================
    // 4. Image ROM (The Data Source)
    // =========================================================
    rom_image #(
        .WIDTH      (8),
        .DEPTH      (TB_IMG_W * TB_IMG_H),
        .INIT_FILE  (ROM_IMAGE_INIT_FILE)
    ) u_tb_rom (
        .clk_i      (clk_i),
        .rd_en      (rom_rd_en),
        .addr_i     (rom_addr),
        .rd_o       (rom_data)
    );

    // =========================================================
    // 5. Clock Gen
    // =========================================================
    initial begin
        clk_i = 0;
        forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end

    // =========================================================
    // 6. Test Sequence
    // =========================================================
    initial begin
        rst_async_n_i = 0;
        start_i       = 0;

        $display("\n========================================================");
        $display("[TB] Starting Full System Simulation (LeNet Layer 1)");
        $display("     Image: %0dx%0d, Kernel: %0dx%0d", TB_IMG_W, TB_IMG_H, TB_KERNEL_R, TB_KERNEL_R);
        $display("========================================================\n");

        // Reset
        #(CLK_PERIOD * 10);
        rst_async_n_i = 1;
        #(CLK_PERIOD * 5);

        // Start
        $display("[TB] Asserting Start...");
        @(negedge clk_i); start_i = 1;
        @(negedge clk_i); start_i = 0;

        // Wait for Completion
        $display("[TB] System Running... (This may take a while)");
        wait(done_o);

        $display("\n[TB] DONE Signal Asserted at time %t", $time);

        // Wait a bit for final flush
        #(CLK_PERIOD * 20);

        // =========================================================
        // 7. Check Results (Dump from Result Handler)
        // =========================================================
        dump_results();

        $finish;
    end

    // Task to read internal memory of Result Handler and print to file/screen
    task dump_results();
        integer f, r, c, i;
        logic [ACC_WIDTH-1:0] val;

        $display("\n========================================================");
        $display("[TB] DUMPING RESULTS (First 10 Pixels of Channel 0)");
        $display("========================================================");

        // Access internal memory: u_dut.u_res_handler.result_mems[channel][pixel_index]
        // Note: Pixel Index 0 corresponds to (Row 0, Col 0) output

        for (i = 0; i < 10; i++) begin
            // Read Channel 0, Pixel i
            val = u_dut.u_res_handler.result_mems[0][i];
            $display("Pixel %0d (Ch 0): %d (0x%h)", i, $signed(val), val);
        end

        // Optional: Dump ALL results to a file for Python comparison
        f = $fopen("../../verif/sim_output.txt", "w");
        if (f) begin
            $display("[TB] Writing all results to 'sim_output.txt'...");

            // Format: Row-Major, Channel-Major
            // For LeNet: 24 rows * 24 cols. Each pixel has 6 channels.
            // Our Memory stores them sequentially by output generation order.
            // Order: (Row 0 Col 0), (Row 0 Col 1)...

            for (i = 0; i < OUT_H * OUT_W; i++) begin
                // Print all 6 channels for this pixel
                for (int ch = 0; ch < 6; ch++) begin
                    $fwrite(f, "%d ", $signed(u_dut.u_res_handler.result_mems[ch][i]));
                end
                $fwrite(f, "\n"); // Newline per pixel
            end
            $fclose(f);
        end
    endtask

endmodule
