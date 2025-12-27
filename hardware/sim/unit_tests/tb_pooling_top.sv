/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-25 00:34:34
 * @LastEditTime: 2025-12-25 00:50:47
 * @LastEditors: Qiao Zhang
 * @Description:  Unit Test for Pooling Top (6-Channel 2x2 Max Pooling).
 *               - Verifies Line Buffer logic and Max calculation.
 *               - Verifies Flow Control (Valid/Ready).
 * @FilePath: /cnn/hardware/sim/unit_tests/tb_pooling_top.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module tb_pooling_top;

    // =========================================================
    // 1. Simulation Parameters
    // =========================================================
    parameter int CLK_PERIOD = 10;

    // LeNet Conv1 Output is 24x24
    parameter int IMG_W = 24;
    parameter int IMG_H = 24;

    // =========================================================
    // 2. Signals
    // =========================================================
    logic           clk_i;
    logic           rst_async_n_i;

    // Config
    logic [31:0]    cfg_img_w_i;

    // Input Stream
    logic [K_CHANNELS-1:0]  valid_i;
    logic [K_CHANNELS-1:0]  ready_o;
    logic [ACC_WIDTH-1:0]   data_i [K_CHANNELS];

    // Output Stream
    logic [K_CHANNELS-1:0]  valid_o;
    logic [K_CHANNELS-1:0]  ready_i;
    logic [ACC_WIDTH-1:0]   data_o [K_CHANNELS];

    // Counters for verification
    int out_cnt;

    // =========================================================
    // 3. DUT Instantiation
    // =========================================================
    pooling_top #(
        .WIDTH(ACC_WIDTH),
        .DEPTH(MAX_LINE_W/2)
    ) u_dut (
        .clk_i(clk_i),
        .rst_async_n_i(rst_async_n_i),
        .cfg_img_w_i(cfg_img_w_i),

        .valid_i(valid_i),
        .ready_o(ready_o),
        .data_i(data_i),

        .valid_o(valid_o),
        .ready_i(ready_i),
        .data_o(data_o)
    );

    // =========================================================
    // 4. Clock Gen
    // =========================================================
    initial begin
        clk_i = 0;
        forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end

    // =========================================================
    // 5. Driver Process (Stimulus)
    // =========================================================
    initial begin
        // --- Init ---
        rst_async_n_i = 0;
        cfg_img_w_i   = IMG_W;
        valid_i       = '0;
        data_i        = '{default: '0};

        // Assume downstream is always ready
        ready_i       = {K_CHANNELS{1'b1}};

        $display("\n[TB] Starting Pooling Unit Test...");
        $display("[TB] Image Size: %0dx%0d", IMG_W, IMG_H);

        // --- Reset ---
        #(CLK_PERIOD*2);
        rst_async_n_i = 1;
        #(CLK_PERIOD*2);

        // 同步到时钟下降沿开始，保证 setup time
        @(negedge clk_i);

        // --- Feed Data (Row by Row) ---
        for (int r = 0; r < IMG_H; r++) begin
            for (int c = 0; c < IMG_W; c++) begin

                // 1. 准备数据
                valid_i = {K_CHANNELS{1'b1}};
                for (int k = 0; k < K_CHANNELS; k++) begin
                    data_i[k] = (r * 100 + c) + (k * 1000);
                end

                // 2. 等待握手成功 (Clock Edge where Valid=1 and Ready=1)
                // 这种写法保证数据至少保持一个周期，且直到 DUT 接收才切换
                do begin
                    @(posedge clk_i);
                end while (ready_o[0] == 1'b0); // 假设所有通道 Ready 同步

                // 3. 握手成功，为了模拟真实间隔，可以在这里稍微拉低 valid (可选)
                // 为了最高吞吐量，我们保持 Valid 为高，直接进入下一次循环更新 Data
                // 在下降沿更新数据可以避免竞争
                #1;
            end
        end

        // End of Stream
        valid_i = '0;

        // Wait for all outputs
        #(CLK_PERIOD * 100);

        if (out_cnt == (IMG_W/2) * (IMG_H/2))
            $display("\n[TB] SUCCESS: Received exactly %0d outputs.", out_cnt);
        else
            $display("\n[TB] FAIL: Received %0d outputs (Expected %0d).", out_cnt, (IMG_W/2)*(IMG_H/2));

        $finish;
    end

    // =========================================================
    // 6. Monitor / Checker
    // =========================================================
    initial out_cnt = 0;

    always @(posedge clk_i) begin
        // Monitor Channel 0 Output
        // Assuming all channels output simultaneously (Lock-step)
        if (valid_o[0] && ready_i[0]) begin

            // Calculate coordinates of the output
            int out_r;
            int out_c;
            int expected_val = (2*out_r + 1) * 100 + (2*out_c + 1);

            // Expected Value Calculation:
            // Input block bottom-right is at: InputRow = 2*out_r + 1, InputCol = 2*out_c + 1
            // Pattern was: r*100 + c
            out_r = out_cnt / (IMG_W/2);
            out_c = out_cnt % (IMG_W/2);
            expected_val = (2*out_r + 1) * 100 + (2*out_c + 1);

            $display("[MON] Out(%2d,%2d) Data=%0d (Expected %0d)",
                     out_r, out_c, $signed(data_o[0]), expected_val);

            // Check correctness
            if ($signed(data_o[0]) !== expected_val) begin
                $error("[MON] Mismatch at output %0d! Got %0d, Want %0d", out_cnt, $signed(data_o[0]), expected_val);
            end

            out_cnt++;
        end
    end

endmodule
