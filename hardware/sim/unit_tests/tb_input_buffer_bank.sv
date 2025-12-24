/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-21 18:16:43
 * @LastEditTime: 2025-12-21 18:17:50
 * @LastEditors: Qiao Zhang
 * @Description:
 * @FilePath: /cnn/hardware/sim/unit_tests/tb_input_buffer_bank.sv
 */

/**
 * @Author: Qiao Zhang & Co-Pilot
 * @Date: 2025-12-21
 * @Description: Testbench for Smart Input Buffer Bank + ROM Image
 *               Verifies DMA fetching, Prefetch logic, and Row Refill handshakes.
 */

`timescale 1ns/1ps
`include "definitions.sv"

module tb_input_buffer_bank;

    // =========================================================
    // 1. Simulation Parameters
    // =========================================================
    parameter int CLK_PERIOD = 10; // 100MHz

    // Override BANK_WIDTH for simulation if needed, or use default
    // Using a slightly larger width than IMG_W to verify wrapping logic
    parameter int TB_BANK_WIDTH = 64;

    // Simulation Settings (LeNet)
    parameter int TEST_IMG_W    = 28;
    parameter int TEST_KERNEL_R = 5;

    // =========================================================
    // 2. Signals
    // =========================================================
    logic           clk_i;
    logic           rst_async_n_i;

    // Config & Control
    logic           start_i;
    logic [31:0]    cfg_img_w_i;
    logic [3:0]     cfg_kernel_r_i;
    logic           pre_wave_done_i;
    logic           ib_ready_o;

    // ROM Interface (IB is Master, ROM is Slave)
    logic [ROM_IMAGE_DEPTH_W-1 : 0] rom_addr;
    logic                           rom_rd_en;
    logic [INT_WIDTH-1 : 0]         rom_data;

    // Parallel Output Interface
    logic [TB_BANK_WIDTH-1 : 0]                     pop_i;
    logic [TB_BANK_WIDTH-1 : 0][INT_WIDTH-1 : 0]    data_out_o;

    // Debug Counters
    int prefetch_cyc_cnt;

    // =========================================================
    // 3. DUT Instantiation
    // =========================================================
    input_buffer_bank #(
        .BANK_WIDTH(TB_BANK_WIDTH) // Override to 64 for this test
    ) u_dut (
        .clk_i          (clk_i),
        .rst_async_n_i  (rst_async_n_i),

        .start_i        (start_i),
        .cfg_img_w_i    (cfg_img_w_i),
        .cfg_kernel_r_i (cfg_kernel_r_i),

        // ROM Master Interface
        .rom_addr_o     (rom_addr),
        .rom_rd_en_o    (rom_rd_en),
        .rom_data_i     (rom_data),

        // Read Interface
        .pop_i          (pop_i),
        .data_out_o     (data_out_o),

        // Handshake
        .pre_wave_done_i(pre_wave_done_i),
        .ib_ready_o     (ib_ready_o)
    );

    // =========================================================
    // 4. ROM Instantiation
    // =========================================================
    rom_image #(
        .WIDTH      (8),
        .DEPTH      (TEST_IMG_W * TEST_IMG_W), // 28*28 = 784
        .INIT_FILE  (ROM_IMAGE_INIT_FILE)
    ) u_rom (
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
        // --- Init Signals ---
        rst_async_n_i   = 0;
        start_i         = 0;
        pre_wave_done_i = 0;
        cfg_img_w_i     = TEST_IMG_W;
        cfg_kernel_r_i  = TEST_KERNEL_R;
        pop_i           = '0;

        $display("\n[TB] Simulation Start");
        $display("[TB] Configuration: Img Width=%0d, Kernel Size=%0d, Prefetch Rows=%0d",
                 TEST_IMG_W, TEST_KERNEL_R, TEST_KERNEL_R+1);

        // --- Reset ---
        #(CLK_PERIOD * 5);
        rst_async_n_i = 1;
        #(CLK_PERIOD * 2);

        // =========================================================
        // Test Case 1: Start Prefetch (Loading Initial K+1 Rows)
        // =========================================================
        $display("[TB] [Time %t] Asserting Start...", $time);
        start_i = 1;
        @(posedge clk_i);
        start_i = 0; // Pulse start

        // Wait for IB to become Ready
        // It needs to load (K+1) * W = 6 * 28 = 168 pixels.
        // This takes roughly 168 cycles.
        prefetch_cyc_cnt = 0;
        while (!ib_ready_o) begin
            @(posedge clk_i);
            prefetch_cyc_cnt++;
            if (prefetch_cyc_cnt > 1000) begin
                $error("[TB] Timeout waiting for Prefetch!");
                $finish;
            end
        end

        $display("[TB] [Time %t] Prefetch Done! Cycles taken: %0d", $time, prefetch_cyc_cnt);

        // Verification: Check ROM Address
        // Should be at 168 (reading the start of 7th row next)
        // Note: rom_addr_o updates continuously, so it might point to 168 now.
        if (rom_addr == (TEST_KERNEL_R + 1) * TEST_IMG_W)
            $display("[TB] CHECK PASS: ROM Address is %0d (Expected 168)", rom_addr);
        else
            $error("[TB] CHECK FAIL: ROM Address is %0d (Expected 168)", rom_addr);


        // =========================================================
        // Test Case 2: Data Validation (Peeking into FIFOs)
        // =========================================================
        // We assume Row 0 Pixel 0 is at Col 0, Row 0 Pixel 1 is at Col 1...
        // Let's verify FIFO Col 0 and Col 1 have data.

        // Let's perform a Pop on Col 0 and Col 1 to see the first pixel values
        $display("[TB] Checking FIFO Data output...");

        // Note: Since FIFO is FWFT (First Word Fall Through) or standard?
        // Your column_fifo implementation outputs `mems[rd_ptr]`.
        // It shows data BEFORE pop if not empty.

        #(CLK_PERIOD);
        $display("     FIFO[0] Data = 0x%h (Should match input_image.hex first byte)", data_out_o[0]);
        $display("     FIFO[1] Data = 0x%h (Should match input_image.hex second byte)", data_out_o[1]);

        // Pop one element
        pop_i[0] = 1;
        pop_i[1] = 1;
        @(posedge clk_i);
        pop_i = '0;

        #(CLK_PERIOD); // Wait for update
        $display("     [After Pop] FIFO[0] Data = 0x%h (Next pixel in Col 0)", data_out_o[0]);


        // =========================================================
        // Test Case 3: Trigger Refill (Simulating SA moving down)
        // =========================================================
        $display("[TB] [Time %t] Triggering 'pre_wave_done_i' (SA finished Row 0)", $time);

        @(negedge clk_i);
        pre_wave_done_i = 1;
        @(negedge clk_i);
        pre_wave_done_i = 0;

        // Verify that IB starts fetching the NEXT row (Row Index 6)
        // It should fetch 28 pixels then go back to wait.

        wait(rom_rd_en); // Wait for read to start
        $display("[TB] Refill started...");

        wait(!rom_rd_en); // Wait for read to finish
        $display("[TB] [Time %t] Refill finished.", $time);

        // Verification: ROM Address should have increased by 28
        // 168 + 28 = 196
        if (rom_addr == 196)
            $display("[TB] CHECK PASS: ROM Address is %0d (Expected 196)", rom_addr);
        else
            $error("[TB] CHECK FAIL: ROM Address is %0d (Expected 196)", rom_addr);

        // =========================================================
        // Test Case 4: Trigger Refill Again (Row 7)
        // =========================================================
        #(CLK_PERIOD * 10);
        $display("[TB] Triggering 'pre_wave_done_i' again...");
        @(negedge clk_i);
        pre_wave_done_i = 1;
        @(negedge clk_i);
        pre_wave_done_i = 0;

        wait(rom_rd_en);
        wait(!rom_rd_en);

        if (rom_addr == 196 + 28)
             $display("[TB] CHECK PASS: ROM Address is %0d (Expected 224)", rom_addr);
        else $error("[TB] CHECK FAIL: ROM Address is %0d", rom_addr);

        $display("\n[TB] All Tests Passed!");
        $finish;
    end

    // Optional: Monitor ROM activity
    // always @(posedge clk_i) begin
    //     if (rom_rd_en)
    //         $display("[MON] Time %t | ROM Addr: %0d | Data Read: %h", $time, rom_addr, rom_data);
    // end

endmodule
