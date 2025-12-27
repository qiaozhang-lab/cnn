/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-27
 * @Description: System Testbench for LeNet-5 Accelerator.
 *               - Simulates full LeNet Layer 1 execution (Conv1 + Bias + ReLU + Pool).
 *               - Includes Software Padding (28->32) logic in Loader.
 *               - QUANT_SHIFT set to 8.
 */

`timescale 1ns/1ps
`include "definitions.sv"

module tb_lenet5_top;

    // =========================================================
    // 1. Simulation Parameters
    // =========================================================
    parameter int CLK_PERIOD = 10;

    // Original LeNet sizes
    parameter int REAL_IMG_W  = 28;
    parameter int REAL_IMG_H  = 28;
    parameter int TB_KERNEL_R = 5;

    // Padding settings (Pad=2)
    parameter int PAD_SIZE    = 2;
    // Hardware sees the Padded size
    parameter int PADDED_W    = REAL_IMG_W + 2 * PAD_SIZE; // 32
    parameter int PADDED_H    = REAL_IMG_H + 2 * PAD_SIZE; // 32

    // Memory Map
    // Input (32x32=1024 bytes): 0x0000 ~ 0x03FF
    // Output (12x12=144 bytes): 0x0400 ~ ...
    parameter int ADDR_IMG_IN  = 32'h0000;
    parameter int ADDR_L1_OUT  = 32'h0400; // 1024

    // =========================================================
    // 2. Signals
    // =========================================================
    logic           clk_i;
    logic           rst_async_n_i;

    // Host Control
    logic           host_start_i;
    logic           accelerator_busy_o;
    logic           accelerator_done_o;

    // Loader Interface
    logic [1:0]     loader_target_sel_i;
    logic           loader_wr_en_i;
    logic [31:0]    loader_wr_addr_i;
    logic [K_CHANNELS-1:0][31:0] loader_wr_data_i;

    // Config Signals (Driven by TB)
    logic [31:0]    cfg_img_w;
    logic [31:0]    cfg_img_h;
    logic [3:0]     cfg_kernel_r;
    logic [2:0]     cfg_input_ch_sel;
    logic           cfg_do_pool;
    logic           cfg_has_bias;
    logic           cfg_do_relu;
    logic [4:0]     cfg_quant_shift;
    logic [31:0]    cfg_read_base;
    logic [31:0]    cfg_write_base;

    // =========================================================
    // 3. DUT Instantiation
    // =========================================================
    lenet5_top u_dut (
        .clk_i              (clk_i),
        .rst_async_n_i      (rst_async_n_i),

        .host_start_i       (host_start_i),
        .accelerator_busy_o (accelerator_busy_o),
        .accelerator_done_o (accelerator_done_o),

        .loader_target_sel_i(loader_target_sel_i),
        .loader_wr_en_i     (loader_wr_en_i),
        .loader_wr_addr_i   (loader_wr_addr_i),
        .loader_wr_data_i   (loader_wr_data_i),

        // Configuration Inputs
        // Note: In a real CPU system, these would be register writes.
        // Here we wire them directly for the specific layer test.
        .cfg_img_w_i        (cfg_img_w),
        .cfg_img_h_i        (cfg_img_h),
        .cfg_kernel_r_i     (cfg_kernel_r),

        .cfg_input_ch_sel_i (cfg_input_ch_sel),
        .cfg_do_pool_i      (cfg_do_pool),
        .cfg_has_bias_i     (cfg_has_bias),
        .cfg_do_relu_i      (cfg_do_relu),
        .cfg_quant_shift_i  (cfg_quant_shift),

        .cfg_read_base_addr_i (cfg_read_base),
        .cfg_write_base_addr_i(cfg_write_base)
    );

    // =========================================================
    // 4. Clock Gen
    // =========================================================
    initial begin
        clk_i = 0;
        forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end

    // =========================================================
    // 5. Main Test Sequence
    // =========================================================
    initial begin
        // --- Init ---
        rst_async_n_i = 0;
        host_start_i  = 0;
        loader_wr_en_i = 0;
        loader_target_sel_i = 0;
        loader_wr_addr_i = 0;
        loader_wr_data_i = '{default: '0};

        // --- Configure Layer 1 Parameters ---
        // We are "tricking" the hardware to process a 32x32 padded image
        cfg_img_w      = PADDED_W; // 32
        cfg_img_h      = PADDED_H; // 32
        cfg_kernel_r   = TB_KERNEL_R;
        cfg_input_ch_sel = 0; // Not used in TDM Wrapper internal loop, but good to set 0

        cfg_do_pool    = 1; // Enable Pooling
        cfg_has_bias   = 1; // Enable Bias
        cfg_do_relu    = 1; // Enable ReLU

        // 【关键配置】：Quant Shift = 8
        cfg_quant_shift = 5'd8;

        cfg_read_base  = ADDR_IMG_IN; // 0x0000
        cfg_write_base = ADDR_L1_OUT; // 0x0400

        $display("\n========================================================");
        $display("[TB] LeNet-5 System Verification Start");
        $display("     Hardware Config: %0dx%0d (Padded), Shift=%0d", cfg_img_w, cfg_img_h, cfg_quant_shift);
        $display("========================================================");

        // --- Reset ---
        #(CLK_PERIOD * 10);
        rst_async_n_i = 1;
        #(CLK_PERIOD * 5);

        // --- 1. Load Phase (Simulate DMA) ---
        $display("[TB] Phase 1: Loading Data to SRAMs...");

        // 1.1 Load Image (Software Padding to 32x32)
        load_image_to_sram("../rtl/init_files/input_image.hex");

        // 1.2 Load Weights
        load_weights_to_buffer("../rtl/init_files/conv1_weights.hex");

        // 1.3 Load Bias
        load_bias_to_buffer("../rtl/init_files/conv1_bias.hex");

        $display("[TB] Data Loading Complete.");
        #(CLK_PERIOD * 10);

        // --- 2. Run Phase ---
        $display("[TB] Phase 2: Starting Accelerator...");

        // Pulse Start at Negedge
        @(negedge clk_i);
        host_start_i = 1;
        @(negedge clk_i);
        host_start_i = 0;

        // Wait for Done
        $display("[TB] System Running... (Waiting for interrupt)");
        wait(accelerator_done_o);

        $display("\n[TB] Interrupt Received! Layer execution finished at time %t", $time);

        // Wait a bit for final writes to settle
        #(CLK_PERIOD * 20);

        // --- 3. Verify Phase ---
        $display("[TB] Phase 3: Dumping Result from Global Buffer...");
        dump_sram_results();

        $display("[TB] Simulation Finished.");
        $finish;
    end

    // =========================================================
    // Tasks: Loader Helpers
    // =========================================================

    // Task: Load Image with SOFTWARE PADDING (28x28 -> 32x32)
    task load_image_to_sram(string filename);
        int fd, val, code;
        int r, c;
        int addr;

        // Use logic array to store temporary image
        logic [7:0] img_buffer [32][32]; // [Row][Col]

        // 1. Initialize buffer with 0 (Padding)
        for (r = 0; r < 32; r++) begin
            for (c = 0; c < 32; c++) begin
                img_buffer[r][c] = 8'd0;
            end
        end

        // 2. Read file (28x28) and fill center
        fd = $fopen(filename, "r");
        if (fd == 0) begin
            $error("[TB] Error opening image file: %s", filename);
            $finish;
        end

        for (r = 0; r < REAL_IMG_H; r++) begin
            for (c = 0; c < REAL_IMG_W; c++) begin
                code = $fscanf(fd, "%h", val);
                // Offset by PAD_SIZE (2,2)
                img_buffer[r + PAD_SIZE][c + PAD_SIZE] = val;
            end
        end
        $fclose(fd);

        // 3. Write 32x32 Buffer to SRAM (Bank 0)
        addr = ADDR_IMG_IN;
        for (r = 0; r < PADDED_H; r++) begin
            for (c = 0; c < PADDED_W; c++) begin
                @(negedge clk_i);
                loader_target_sel_i = 2'd0; // Target: Global Buffer
                loader_wr_en_i      = 1'b1;
                loader_wr_addr_i    = addr;

                // Reset data bus
                loader_wr_data_i = '{default: '0};
                loader_wr_data_i[0] = {24'h0, img_buffer[r][c]}; // Bank 0

                addr++;
            end
        end

        @(negedge clk_i);
        loader_wr_en_i = 1'b0;
        $display("[TB] Loaded Padded Image (32x32) to Global Buffer Bank 0.");
    endtask

    // Task: Load Weights
    task load_weights_to_buffer(string filename);
        int fd, addr, code;
        logic [63:0] val_long; // Use 64-bit var to read >32 bit hex if needed
        // Note: fscanf %h might be limited by variable size.
        // If file has 48-bit hex per line (e.g. 123456789ABC), logic [63:0] is needed.

        addr = 0;
        fd = $fopen(filename, "r");
        if (fd == 0) begin
            $error("[TB] Error opening weight file."); $finish;
        end

        while (!$feof(fd)) begin
            code = $fscanf(fd, "%h", val_long);
            if (code == 1) begin
                @(negedge clk_i);
                loader_target_sel_i = 2'd1; // Weight Buffer
                loader_wr_en_i      = 1'b1;
                loader_wr_addr_i    = addr;

                // Pack into array [K][32]
                for (int k=0; k<6; k++) begin
                    // Extract byte k. Note: Weights are 8-bit.
                    // loader_wr_data_i is 32-bit wide per channel.
                    // We only use the lower 8 bits for the weight buffer (logic inside top handles this)
                    loader_wr_data_i[k] = (val_long >> (k*8)) & 32'hFF;
                end
                addr++;
            end
        end
        $fclose(fd);
        @(negedge clk_i);
        loader_wr_en_i = 1'b0;
        $display("[TB] Loaded Weights.");
    endtask

    // Task: Load Bias
    task load_bias_to_buffer(string filename);
        int fd, val, code;
        logic [31:0] bias_cache [6];
        int ch_idx = 0;

        fd = $fopen(filename, "r");
        while (!$feof(fd) && ch_idx < 6) begin
            code = $fscanf(fd, "%h", val);
            if (code == 1) begin
                bias_cache[ch_idx] = val;
                ch_idx++;
            end
        end
        $fclose(fd);

        // Write to Buffer at Addr 0
        @(negedge clk_i);
        loader_target_sel_i = 2'd2; // Bias Buffer
        loader_wr_en_i      = 1'b1;
        loader_wr_addr_i    = 0;

        for (int k=0; k<6; k++) begin
            loader_wr_data_i[k] = bias_cache[k];
        end

        @(negedge clk_i);
        loader_wr_en_i = 1'b0;
        $display("[TB] Loaded Biases.");
    endtask

    // =========================================================
    // Task: Dump Results
    // =========================================================
    task dump_sram_results();
        int f, i, k;
        logic signed [7:0] val;

        // Output: 12x12
        int out_size = 12 * 12;

        f = $fopen("sim_final_result.txt", "w");

        for (i = 0; i < out_size; i++) begin
            for (k = 0; k < 6; k++) begin
                // Backdoor access to Global Buffer SRAM
                // Note: Need 'case' to avoid XMRE errors with dynamic index
                case (k)
                    0: val = u_dut.u_global_mem.gen_sram_banks[0].mems[ADDR_L1_OUT + i];
                    1: val = u_dut.u_global_mem.gen_sram_banks[1].mems[ADDR_L1_OUT + i];
                    2: val = u_dut.u_global_mem.gen_sram_banks[2].mems[ADDR_L1_OUT + i];
                    3: val = u_dut.u_global_mem.gen_sram_banks[3].mems[ADDR_L1_OUT + i];
                    4: val = u_dut.u_global_mem.gen_sram_banks[4].mems[ADDR_L1_OUT + i];
                    5: val = u_dut.u_global_mem.gen_sram_banks[5].mems[ADDR_L1_OUT + i];
                endcase

                $fwrite(f, "%d ", val);
            end
            $fwrite(f, "\n");
        end
        $fclose(f);
        $display("[TB] Results dumped to 'sim_final_result.txt'.");
    endtask

endmodule
