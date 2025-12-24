/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-23 06:29:54
 * @LastEditTime: 2025-12-23 06:29:56
 * @LastEditors: Qiao Zhang
 * @Description: Unit Test for Systolic Top - Signed Arithmetic Check.
 * @FilePath: /cnn/hardware/sim/unit_tests/tb_systolic_top.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module tb_systolic_top;

    // =========================================================
    // 1. Parameters & Signals
    // =========================================================
    parameter int CLK_PERIOD = 10;

    logic           clk_i;
    logic           rst_async_n_i;

    // Direct Interface
    logic [MATRIX_A_ROW-1 : 0]                west_valid_i;
    logic [MATRIX_A_ROW-1 : 0]                west_ready_o;
    logic [MATRIX_A_ROW-1 : 0][DATA_WIDTH-1:0] west_data_i;

    logic [MATRIX_B_COL-1 : 0]                north_valid_i;
    logic [MATRIX_B_COL-1 : 0]                north_ready_o;
    logic [MATRIX_B_COL-1 : 0][DATA_WIDTH-1:0] north_data_i;

    logic [ACC_WIDTH-1 : 0]                   result_o[MATRIX_A_ROW][MATRIX_B_COL];

    // =========================================================
    // 2. DUT Instantiation
    // =========================================================
    systolic_top u_dut (
        .clk_i          (clk_i),
        .rst_async_n_i  (rst_async_n_i),
        .west_valid_i   (west_valid_i),
        .west_ready_o   (west_ready_o),
        .west_data_i    (west_data_i),
        .north_valid_i  (north_valid_i),
        .north_ready_o  (north_ready_o),
        .north_data_i   (north_data_i),
        .result_o       (result_o)
    );

    // =========================================================
    // 3. Clock Gen
    // =========================================================
    initial begin
        clk_i = 0;
        forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end

    // =========================================================
    // 4. Test Sequence
    // =========================================================
    initial begin
        rst_async_n_i = 0;
        west_valid_i  = '0;
        north_valid_i = '0;
        west_data_i   = '{default: '0};
        north_data_i  = '{default: '0};

        $display("\n[TB] Starting Systolic Signed Arithmetic Check...");

        #(CLK_PERIOD * 5);
        rst_async_n_i = 1;
        #(CLK_PERIOD * 2);

        // --- Feed Data Step-by-Step (Manual Skew) ---
        // We will feed PE(0,0) with specific values to check calculation.
        // PE(0,0) Input: West[0], North[0]

        // Cycle 1: Feed 2 * (-3)
        $display("[TB] Cycle 1: Feeding 2 * (-3)...");
        @(negedge clk_i);
        west_valid_i[0]  = 1;
        west_data_i[0]   = 8'sd2;  // Signed 2

        north_valid_i[0] = 1;
        north_data_i[0]  = -8'sd3; // Signed -3 (8'hFD)

        // Cycle 2: Feed (-4) * 5
        @(negedge clk_i);
        $display("[TB] Cycle 2: Feeding (-4) * 5...");
        west_data_i[0]   = -8'sd4; // Signed -4 (8'hFC)
        north_data_i[0]  = 8'sd5;  // Signed 5

        // Cycle 3: Stop Feeding
        @(negedge clk_i);
        west_valid_i  = '0;
        north_valid_i = '0;
        west_data_i   = '0;
        north_data_i  = '0;

        // Wait for pipeline (PE latency)
        #(CLK_PERIOD * 5);

        // --- Check Result ---
        // Expected: (2 * -3) + (-4 * 5) = -6 + (-20) = -26
        // -26 in 32-bit Hex is FFFFFFE6

        $display("\n[TB] Checking Result at PE[0][0]...");
        $display("     Expected: -26 (0x...E6)");
        $display("     Actual  : %0d (0x%h)", $signed(result_o[0][0]), result_o[0][0]);

        if ($signed(result_o[0][0]) == -26)
            $display("[TB] PASS: Signed Arithmetic is Correct!");
        else
            $display("[TB] FAIL: Incorrect Calculation.");

        $finish;
    end

endmodule
