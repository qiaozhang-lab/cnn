/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-19 18:24:28
 * @LastEditTime: 2025-12-19 18:28:01
 * @LastEditors: Qiao Zhang
 * @Description: Testbench for img2col_addr_gen.sv
 * @FilePath: /cnn/hardware/sim/unit_tests/tb_img2col_addr_gen.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module tb_img2col_addr_gen;

    // =========================================================
    // 1. Signals
    // =========================================================
    logic clk, rst_n;
    logic start;
    logic ready;
    logic [SRAM_ADDR_W-1:0] base_addr;

    logic valid;
    logic [SRAM_ADDR_W-1:0] addr;
    logic last;

    // =========================================================
    // 2. DUT Instantiation
    // =========================================================
    img2col_addr_gen dut (
        .clk_i(clk), .rst_async_n_i(rst_n),
        .start_i(start),
        .systolic_ready_i(ready),
        .base_addr_i(base_addr),
        .valid_o(valid),
        .sram_rd_addr_o(addr),
        .last_out_o(last)
    );

    // =========================================================
    // 3. Clock & Reset
    // =========================================================
    initial clk = 0;
    always #5 clk = ~clk; // 100MHz

    // =========================================================
    // 4. Main Test Sequence
    // =========================================================
    initial begin
        // Init
        rst_n = 0; start = 0; ready = 0; base_addr = 0;

        // Reset
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // -----------------------------------------------------
        // TEST CASE 1: Full Speed (Base = 0)
        // -----------------------------------------------------
        $display("\n=== TEST 1: Full Speed, Base Addr = 0 ===");
        $display("Image: %0dx%0d, Kernel: %0dx%0d", IMG_W, IMG_H, K_R, K_S);

        ready = 1;
        base_addr = 16'h0000;

        @(posedge clk);
        start = 1; // Pulse start
        @(posedge clk);
        start = 0;

        // Wait until finish
        wait(last);
        @(posedge clk);
        ready = 0;
        repeat(10) @(posedge clk);

        // -----------------------------------------------------
        // TEST CASE 2: Random Backpressure (Base = 100)
        // -----------------------------------------------------
        $display("\n=== TEST 2: Random Backpressure, Base Addr = 100 ===");

        base_addr = 16'd100;
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Randomly toggle ready
        fork
            begin
                while (!last) begin
                    @(posedge clk);
                    // 30% chance to be NOT ready
                    ready <= ($urandom_range(0, 10) > 3);
                end
                ready <= 1; // Ensure last signal is flushed
            end
        join

        @(posedge clk);
        $display("\n=== ALL TESTS FINISHED ===");
        $finish;
    end

    // =========================================================
    // 5. Monitor & Checker
    // =========================================================
    int pixel_cnt = 0;
    int kernel_size;
    assign kernel_size = K_R * K_S;

    always @(posedge clk) begin
        if (valid && ready) begin
            // Pretty Print: Group output by windows
            if (pixel_cnt == 0)
                $write("Win: ");

            $write("%3d ", addr);

            pixel_cnt++;
            if (pixel_cnt == kernel_size) begin
                $write("\n"); // Newline after one window (one GEMM column)
                pixel_cnt = 0;
            end
        end
    end

endmodule
