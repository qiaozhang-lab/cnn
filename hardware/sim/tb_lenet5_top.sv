/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-28
 * @Description: System Testbench for LeNet-5 (Full Flow).
 *               - Supports TDM execution (L1 -> L2).
 *               - Implements "Virtual DRAM + DMA" for efficient weight loading.
 */

`timescale 1ns/1ps
`include "definitions.sv"

module tb_lenet5_top;

    // =========================================================
    // 1. Parameters
    // =========================================================
    parameter int CLK_PERIOD = 10;

    // Image Config
    parameter int REAL_IMG_W = 28;
    parameter int PAD_SIZE   = 2;
    parameter int PADDED_W   = 32;

    // Memory Map
    parameter int ADDR_IMG_IN = 32'h0000;
    parameter int ADDR_L2_OUT = 32'h0800; // L2 Result Base

    // =========================================================
    // 2. Virtual DRAM (模拟片外存储)
    // =========================================================
    // Conv2 Weights: 16*6*25 = 2400 lines (packed).
    // Format: 48-bit hex per line. Use 64-bit array.
    logic [63:0] dram_conv2_weights [0:4095];

    // Conv2 Bias: 16 biases.
    // Format: 32-bit hex per line.
    logic [31:0] dram_conv2_bias    [0:63];

    // DMA Pointers (记住搬运进度)
    int ptr_w_conv2;
    int ptr_b_conv2;

    // =========================================================
    // 3. Signals
    // =========================================================
    logic           clk_i;
    logic           rst_async_n_i;
    logic           start_i;

    logic           busy_o;
    logic           done_o;

    logic           host_weight_loaded; // Handshake signal

    // Loader
    logic [1:0]     loader_sel;
    logic           loader_wen;
    logic [31:0]    loader_addr;
    logic [K_CHANNELS-1:0][31:0] loader_data;

    // DUT Config Drivers (Wires)
    logic [31:0]    cfg_w, cfg_h;
    logic [3:0]     cfg_k;
    logic [2:0]     cfg_ch_sel;
    logic           cfg_pool, cfg_bias, cfg_relu;
    logic [4:0]     cfg_shift;
    logic [31:0]    cfg_r_base, cfg_w_base;

    // =========================================================
    // 4. DUT Instantiation
    // =========================================================
    lenet5_top u_dut (
        .clk_i              (clk_i),
        .rst_async_n_i      (rst_async_n_i),

        .host_start_i       (start_i),
        .host_weight_loaded_i(host_weight_loaded), // New Port

        .accelerator_busy_o (busy_o),
        .accelerator_done_o (done_o),

        .loader_target_sel_i(loader_sel),
        .loader_wr_en_i     (loader_wen),
        .loader_wr_addr_i   (loader_addr),
        .loader_wr_data_i   (loader_data),

        // Configs (Driven by Controller internally, but exposed for debug/override if needed)
        // Here we just tie them to open or monitor internal signals if we want
        // For simulation, we let the internal controller drive them.
        .cfg_img_w_i('0), .cfg_img_h_i('0), .cfg_kernel_r_i('0),
        .cfg_input_ch_sel_i('0), .cfg_do_pool_i('0), .cfg_has_bias_i('0),
        .cfg_do_relu_i('0), .cfg_quant_shift_i('0),
        .cfg_read_base_addr_i('0), .cfg_write_base_addr_i('0)
    );

    // =========================================================
    // 5. Main Sequence
    // =========================================================
    initial begin
        clk_i = 0;
        forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end

    initial begin
        // --- Init ---
        rst_async_n_i = 0;
        start_i       = 0;
        host_weight_loaded = 0;
        loader_wen    = 0;

        // Initialize DRAM Pointers
        ptr_w_conv2 = 0;
        ptr_b_conv2 = 0;

        // Initialize Virtual DRAM from Files
        // 注意：这里读取的是 python 生成的大文件
        $readmemh("../rtl/init_files/conv2_weights.hex", dram_conv2_weights);
        $readmemh("../rtl/init_files/conv2_bias.hex",    dram_conv2_bias);

        $display("\n========================================================");
        $display("[TB] LeNet-5 Full System Simulation Start");
        $display("========================================================");

        // Reset
        #(CLK_PERIOD * 10);
        rst_async_n_i = 1;
        #(CLK_PERIOD * 5);

        // ---------------------------------------------------------
        // Phase 1: Pre-load Layer 1 (Image & Weights)
        // ---------------------------------------------------------
        $display("[TB] Phase 1: Loading Layer 1 Data...");

        // 1.1 Image (Software Padding to 32x32)
        load_image_to_sram("../rtl/init_files/input_image.hex");

        // 1.2 Conv1 Weights (Simple Load)
        load_weights_l1("../rtl/init_files/conv1_weights.hex");
        load_bias_l1("../rtl/init_files/conv1_bias.hex");

        $display("[TB] Layer 1 Data Ready. Starting Accelerator...");

        // ---------------------------------------------------------
        // Phase 2: Start & Dynamic Loading Loop
        // ---------------------------------------------------------

        // Trigger Start
        @(negedge clk_i); start_i = 1;
        @(negedge clk_i); start_i = 0;

        // Main Event Loop
        while (!done_o) begin
            // Wait for either a LOAD REQUEST or DONE
            // Accessing internal signal u_dut.u_ctrl.req_load_weight_o
            wait (u_dut.u_ctrl.req_load_weight_o || done_o);

            if (done_o) break;

            if (u_dut.u_ctrl.req_load_weight_o) begin
                logic [3:0] layer_id;
                layer_id = u_dut.u_ctrl.layer_id_o;

                $display("\n[TB] IRQ: Load Request for Layer ID %0d", layer_id);

                case (layer_id)
                    1: begin
                        // L1 Load Request (Usually handled before start, but if requested again)
                        // Skip or reload if needed. Here we assume pre-loaded.
                        $display("[TB] L1 Weights already loaded. Acknowledging...");
                    end

                    // Conv2 Groups (ID 2, 3, 4)
                    2, 3, 4: begin

                        $display("[TB] DMA: Transferring Conv2 Weights (150 lines)...");
                        dma_transfer_weights(150);

                        $display("[TB] DMA: Transferring Conv2 Bias (1 line)...");
                        dma_transfer_bias(1);
                    end
                endcase

                // Handshake: Notify Controller
                @(negedge clk_i);
                host_weight_loaded = 1;

                // Wait for Request to Drop (Controller moves to RUN)
                wait (!u_dut.u_ctrl.req_load_weight_o);

                @(negedge clk_i);
                host_weight_loaded = 0;
                $display("[TB] Handshake Complete. Controller Running...");
            end
        end

        $display("\n[TB] System DONE Signal Received!");

        // ---------------------------------------------------------
        // Phase 3: Verify L2 Results
        // ---------------------------------------------------------
        #(CLK_PERIOD * 20);
        dump_l2_results();

        $finish;
    end

    // =========================================================
    // Loader Tasks
    // =========================================================

    // L1 Image Loader (Padding 28->32)
    task load_image_to_sram(string filename);
        int fd, val, code, r, c, addr;
        logic [7:0] img_buffer [32][32];

        // Zero init
        for (r=0; r<32; r++) for (c=0; c<32; c++) img_buffer[r][c] = 0;

        fd = $fopen(filename, "r");
        if (fd) begin
            for (r=0; r<28; r++) for (c=0; c<28; c++) begin
                code = $fscanf(fd, "%h", val);
                img_buffer[r+2][c+2] = val;
            end
            $fclose(fd);
        end

        // Write
        addr = ADDR_IMG_IN;
        for (r=0; r<32; r++) begin
            for (c=0; c<32; c++) begin
                @(negedge clk_i);
                loader_sel = 0; loader_wen = 1; loader_addr = addr;
                loader_data[0] = img_buffer[r][c]; // Bank 0
                addr++;
            end
        end
        @(negedge clk_i); loader_wen = 0;
    endtask

    // L1 Simple Loaders
    task load_weights_l1(string filename);
        int fd, addr, code;
        logic [63:0] val;
        addr = 0;
        fd = $fopen(filename, "r");
        while (!$feof(fd)) begin
            code = $fscanf(fd, "%h", val);
            if (code == 1) begin
                @(negedge clk_i);
                loader_sel = 1; loader_wen = 1; loader_addr = addr;
                for(int k=0; k<6; k++) loader_data[k] = (val >> (k*8)) & 8'hFF;
                addr++;
            end
        end
        $fclose(fd);
        @(negedge clk_i); loader_wen = 0;
    endtask

    task load_bias_l1(string filename);
        int fd, val, code, k;
        logic [31:0] cache [6];
        k=0;
        fd = $fopen(filename, "r");
        while (!$feof(fd) && k<6) begin
            code = $fscanf(fd, "%h", val);
            if (code == 1) cache[k++] = val;
        end
        $fclose(fd);

        @(negedge clk_i);
        loader_sel = 2; loader_wen = 1; loader_addr = 0;
        for(int j=0; j<6; j++) loader_data[j] = cache[j];
        @(negedge clk_i); loader_wen = 0;
    endtask

    // L2 DMA Loaders (From Virtual DRAM)
    task dma_transfer_weights(int count);
        for (int i = 0; i < count; i++) begin
            @(negedge clk_i);
            loader_sel = 1; loader_wen = 1; loader_addr = i;
            // Unpack 48-bit
            for (int k=0; k<6; k++)
                loader_data[k] = (dram_conv2_weights[ptr_w_conv2] >> (k*8)) & 8'hFF;
            ptr_w_conv2++;
        end
        @(negedge clk_i); loader_wen = 0;
    endtask

    task dma_transfer_bias(int count);
        for (int i = 0; i < count; i++) begin
            @(negedge clk_i);
            loader_sel = 2; loader_wen = 1; loader_addr = 0; // Always addr 0
            // Unpack 192-bit
            for (int k=0; k<6; k++)
                loader_data[k] = (dram_conv2_bias[ptr_b_conv2] >> (k*32)) & 32'hFFFFFFFF;
            ptr_b_conv2++;
        end
        @(negedge clk_i); loader_wen = 0;
    endtask

    // Dump L2 Results
    task dump_l2_results();
        int f, i, k, base_addr;
        logic signed [7:0] val;

        // L2 Out Size: 4x4 per channel. 16 channels total.
        int pixels_per_ch = 5 * 5; // 16 pixels

        f = $fopen("sim_l2_result.txt", "w");

        // Group 1: Ch 0-5 (Addr 0x0800)
        base_addr = 32'h0800;
        for (i = 0; i < pixels_per_ch; i++) begin
            for (k = 0; k < 6; k++) begin
                case(k)
                    0: val = u_dut.u_global_mem.gen_sram_banks[0].mems[base_addr+i];
                    1: val = u_dut.u_global_mem.gen_sram_banks[1].mems[base_addr+i];
                    2: val = u_dut.u_global_mem.gen_sram_banks[2].mems[base_addr+i];
                    3: val = u_dut.u_global_mem.gen_sram_banks[3].mems[base_addr+i];
                    4: val = u_dut.u_global_mem.gen_sram_banks[4].mems[base_addr+i];
                    5: val = u_dut.u_global_mem.gen_sram_banks[5].mems[base_addr+i];
                endcase
                $fwrite(f, "%d ", val);
            end
            $fwrite(f, "\n");
        end

        // Group 2: Ch 6-11 (Addr 0x0819 -> 2048+25)
        base_addr = 32'h0800 + 25; // Offset 25 (L2_OUT_CH_SIZE)
        for (i = 0; i < pixels_per_ch; i++) begin
            for (k = 0; k < 6; k++) begin
                case(k)
                    0: val = u_dut.u_global_mem.gen_sram_banks[0].mems[base_addr+i];
                    1: val = u_dut.u_global_mem.gen_sram_banks[1].mems[base_addr+i];
                    2: val = u_dut.u_global_mem.gen_sram_banks[2].mems[base_addr+i];
                    3: val = u_dut.u_global_mem.gen_sram_banks[3].mems[base_addr+i];
                    4: val = u_dut.u_global_mem.gen_sram_banks[4].mems[base_addr+i];
                    5: val = u_dut.u_global_mem.gen_sram_banks[5].mems[base_addr+i];
                endcase
                $fwrite(f, "%d ", val);
            end
            $fwrite(f, "\n");
        end

        // Group 3: Ch 12-15 (Addr 0x0832 -> 2048+50)
        base_addr = 32'h0800 + 50;
        for (i = 0; i < pixels_per_ch; i++) begin
            for (k = 0; k < 4; k++) begin // Only 4 channels
                case(k)
                    0: val = u_dut.u_global_mem.gen_sram_banks[0].mems[base_addr+i];
                    1: val = u_dut.u_global_mem.gen_sram_banks[1].mems[base_addr+i];
                    2: val = u_dut.u_global_mem.gen_sram_banks[2].mems[base_addr+i];
                    3: val = u_dut.u_global_mem.gen_sram_banks[3].mems[base_addr+i];
                endcase
                $fwrite(f, "%d ", val);
            end
            $fwrite(f, "\n");
        end

        $fclose(f);
        $display("[TB] L2 Results dumped.");
    endtask

endmodule
