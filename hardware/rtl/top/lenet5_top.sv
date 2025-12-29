/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-27 02:15:22
 * @LastEditTime: 2025-12-28 21:55:33
 * @LastEditors: Qiao Zhang
 * @Description: LeNet-5 Accelerator Top Level.
 *               - Instantiates Systolic Core, Global Buffer, Weight Buffer, Bias Buffer.
 *               - Exposes AXI-like or simple Host Interface for control.
 * @FilePath: /cnn/hardware/rtl/top/lenet5_top.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module lenet5_top (
    input   logic               clk_i           ,
    input   logic               rst_async_n_i   ,

    // ==========================================
    // 1. Host Control Interface (Register File)
    // ==========================================
        // A. configuration register
    input   logic[31 : 0]               cfg_img_w_i     ,
    input   logic[31 : 0]               cfg_img_h_i     ,
    input   logic[3 : 0]                cfg_kernel_r_i  ,

        // B. features key
    input   logic[2 : 0]                cfg_input_ch_sel_i  ,
    input   logic                       cfg_do_pool_i   ,
    input   logic                       cfg_has_bias_i  ,
    input   logic                       cfg_do_relu_i   ,
    input   logic[4 : 0]                cfg_quant_shift_i   ,

        // C. read/write address offset
    input   logic[SRAM_ADDR_W-1 : 0]    cfg_read_base_addr_i    ,
    input   logic[SRAM_ADDR_W-1 : 0]    cfg_write_base_addr_i   ,

        // D. instruction control
    input   logic                       host_start_i    ,
    input   logic                       host_weight_loaded_i,
    output  logic                       accelerator_busy_o  ,
    output  logic                       accelerator_done_o  ,

    // ==========================================
    // 2. Host Data(image, weights, bias) Interface (DMA / Loader)
    // ==========================================
        // 0: Global Buffer (Bank 0 only for Image)
        // 1: Weight Buffer
        // 2: Bias Buffer
    input   logic[1 : 0]        loader_target_sel_i ,
    input   logic               loader_wr_en_i      ,
    input   logic[31 : 0]       loader_wr_addr_i    ,
    input   logic[K_CHANNELS-1 : 0][31 : 0]       loader_wr_data_i
);
    // ==========================================
    // 1. Internal Signal Connect
    // ==========================================
        // --- Systolic Wrapper <-> Buffers ---
            //Global Buffer
    logic [K_CHANNELS-1 : 0]                    gb_rd_en;
    logic [SRAM_ADDR_W-1 : 0]                   gb_rd_addr;
    logic [K_CHANNELS-1 : 0][INT_WIDTH-1 : 0]   gb_rd_data;

    logic [K_CHANNELS-1 : 0]                    gb_wr_en;
    logic [K_CHANNELS-1 : 0][SRAM_ADDR_W-1 : 0] gb_wr_addr;
    logic [K_CHANNELS-1 : 0][INT_WIDTH-1 : 0]   gb_wr_data;

            // Weight Buffer
    logic                                       wb_rd_en;
    logic[SRAM_ADDR_W-1 : 0]                    wb_rd_addr;
    logic[K_CHANNELS-1 : 0][INT_WIDTH-1 : 0]    wb_rd_data;

            // Bias Buffer (Assuming Bias is pre-loaded per layer)
    logic[K_CHANNELS-1 : 0][ACC_WIDTH-1 : 0]    bias_data;

    // --- Loader Logic Signals ---
    logic[K_CHANNELS-1 : 0]                     gb_wr_en_loader;
    logic[SRAM_ADDR_W-1 : 0]                    gb_wr_addr_loader;
    logic[INT_WIDTH-1 : 0]                      gb_wr_data_loader;

    logic                                       wb_wr_en_loader;
    logic[SRAM_ADDR_W-1 : 0]                    wb_wr_addr_loader;
    logic[K_CHANNELS-1 : 0][INT_WIDTH-1 : 0]    wb_wr_data_loader;

    logic                                       bb_wr_en_loader;
    logic[5 : 0]                                bb_wr_addr_loader;
    logic[K_CHANNELS-1 : 0][ACC_WIDTH-1 : 0]    bb_wr_data_loader;

    // --- LeNet5 Controller
    logic                                       ctrl_start_core;
    logic                                       ctrl_done_core;

    logic [31 : 0]                              cfg_w;
    logic [31 : 0]                              cfg_h;
    logic [3 : 0]                               cfg_k;
    logic [15 : 0]                              cfg_num_ch;
    logic                                       cfg_do_pool;
    logic                                       cfg_do_bias;
    logic                                       cfg_do_relu;
    logic                                       cfg_do_quant;
    logic [4 : 0]                               cfg_quant_shift;
    logic [31 : 0]                              cfg_read_base;
    logic [31 : 0]                              cfg_write_base;
        // Handshake
    logic                                       req_load_weight;
    logic [3 : 0]                               layer_id    ;
    logic                                       weight_loaded_ack;

    // =========================================================
    // 1. Loader Demux Logic
    // =========================================================
    always_comb begin : loader_demux_logic
        gb_wr_en_loader = '0;
        wb_wr_en_loader = '0;
        bb_wr_en_loader = '0;

        // Data mapping
        // Global Buffer: write only Bank 0
        gb_wr_addr_loader = loader_wr_addr_i[SRAM_ADDR_W-1 : 0] ;
        gb_wr_data_loader = loader_wr_data_i[0][INT_WIDTH-1 : 0];

        case (loader_target_sel_i)
            2'b00  : gb_wr_en_loader[0] = loader_wr_en_i;
            2'b01  : wb_wr_en_loader    = loader_wr_en_i;
            2'b10  : bb_wr_en_loader    = loader_wr_en_i;
            default: ;// keep do nothing
        endcase
    end : loader_demux_logic

    always_comb begin : wb_wr_data_preprocess
        wb_wr_addr_loader = loader_wr_addr_i[SRAM_ADDR_W-1:0];
        for(int k=0; k<K_CHANNELS; k++)
            wb_wr_data_loader[k] = loader_wr_data_i[k][INT_WIDTH-1 : 0];
    end : wb_wr_data_preprocess

    always_comb begin : bb_wr_data_preprocess
        bb_wr_addr_loader = loader_wr_addr_i[5:0];
        for(int k=0; k<K_CHANNELS; k++)
            bb_wr_data_loader[k] = loader_wr_data_i[k];
    end : bb_wr_data_preprocess

    // =========================================================
    // 2. Address Translation (Base + Offset)
    // =========================================================
    logic [K_CHANNELS-1 : 0][SRAM_ADDR_W-1 : 0] gb_wr_addr_phys;
    logic [K_CHANNELS-1 : 0][SRAM_ADDR_W-1 : 0] gb_rd_addr_phys;

    generate
        for(genvar k=0; k<K_CHANNELS; k++) begin
            // Read: Base + Wrapper Addr
            // assign gb_rd_addr_phys[k] = cfg_read_base_addr_i + gb_rd_addr;
            assign gb_rd_addr_phys[k] = cfg_read_base + gb_rd_addr;

            // Write: Base + Wrapper Addr (Truncate 32-bit addr from handler)
            // assign gb_wr_addr_phys[k] = cfg_write_base_addr_i + gb_wr_addr[k][SRAM_ADDR_W-1 : 0];
            assign gb_wr_addr_phys[k] = cfg_write_base + gb_wr_addr[k][SRAM_ADDR_W-1 : 0];
        end
    endgenerate

    // =========================================================
    // 3. Buffer Instantiations
    // =========================================================

    // A. Global Buffer (Unified Memory)
        // Muxing between Loader (Write) and Core (Write)
    logic [K_CHANNELS-1 : 0]                    final_gb_wr_en;
    logic [K_CHANNELS-1 : 0][SRAM_ADDR_W-1 : 0] final_gb_wr_addr;
    logic [K_CHANNELS-1 : 0][INT_WIDTH-1 : 0]   final_gb_wr_data;

    always_comb begin : gb_mux_sel
        final_gb_wr_en   = '0;
        final_gb_wr_addr = '0;
        final_gb_wr_data = '0;

        if(loader_wr_en_i && (loader_target_sel_i == 2'd00)) begin
            // Loader Mode
            final_gb_wr_en   = gb_wr_en_loader;// Only Bank 0 active
            final_gb_wr_addr = (K_CHANNELS*SRAM_ADDR_W)'(gb_wr_addr_loader);
            final_gb_wr_data = (K_CHANNELS*INT_WIDTH)'(gb_wr_data_loader);
        end else begin
            // Core Mode
            final_gb_wr_en   = gb_wr_en;
            final_gb_wr_addr = gb_wr_addr_phys;
            final_gb_wr_data = gb_wr_data;
        end
    end : gb_mux_sel

    global_buffer #(
        .DEPTH(SRAM_DEPTH)
    ) u_global_mem (
        .clk_i              (clk_i),
        .rst_async_n_i      (rst_async_n_i),

        .wr_en_i            (final_gb_wr_en),
        .wr_addr_i          (final_gb_wr_addr),
        .wr_data_i          (final_gb_wr_data),

        .rd_en_i            (gb_rd_en),
        .rd_addr_i          (gb_rd_addr_phys),
        .rd_data_o          (gb_rd_data)
    );


    // B. Weight Buffer
    weight_buffer u_weight_buf(
        .clk_i              (clk_i),
        .rst_async_n_i      (rst_async_n_i),

        .loader_wr_en_i     (wb_wr_en_loader),
        .loader_wr_addr_i   (wb_wr_addr_loader),
        .loader_wr_data_i   (wb_wr_data_loader),

        .rd_en_i            (wb_rd_en),
        .rd_addr_i          (wb_rd_addr),
        .rd_data_o          (wb_rd_data)
    );


    // C. Bias Buffer
    bias_buffer u_bias_buf(
        .clk_i                  (clk_i),
        .rst_async_n_i          (rst_async_n_i),

        .loader_wr_en_i         (bb_wr_en_loader),
        .loader_wr_addr_i       (bb_wr_addr_loader),
        .loader_wr_data_i       (bb_wr_data_loader),

        .rd_en_i                (1'b1),
        .rd_addr_i              (6'b0),
        .rd_data_o              (bias_data)
    );

    // =========================================================
    // 4. LeNet5 Controller and Core
    // =========================================================

    lenet_controller u_ctrl (
        .clk_i                  (clk_i),
        .rst_async_n_i          (rst_async_n_i),

        .host_start_i           (host_start_i),
        .host_done_o            (accelerator_done_o),
        .req_load_weight_o      (req_load_weight),
        .layer_id_o             (layer_id),
        .weight_loaded_i        (host_weight_loaded_i),

        .cfg_img_w_o            (cfg_w),
        .cfg_img_h_o            (cfg_h),
        .cfg_kernel_r_o         (cfg_k),
        .cfg_do_bias_o          (cfg_do_bias),
        .cfg_do_relu_o          (cfg_do_relu),
        .cfg_do_pool_o          (cfg_do_pool),
        .cfg_do_quant_o         (cfg_do_quant),
        .cfg_quant_shift_o      (cfg_quant_shift),
        .cfg_num_input_channels_o(cfg_num_ch),
        .cfg_read_base_o        (cfg_read_base),
        .cfg_write_base_o       (cfg_write_base),

        .core_start_o           (ctrl_start_core),
        .core_done_i            (ctrl_done_core)
    );

    systolic_wrapper u_core(
        .clk_i                  (clk_i),
        .rst_async_n_i          (rst_async_n_i),

        .gb_rd_en_o             (gb_rd_en),
        .gb_rd_addr_o           (gb_rd_addr),
        .gb_rd_data_i           (gb_rd_data),

        .gb_wr_en_o             (gb_wr_en),
        .gb_wr_addr_o           (gb_wr_addr),
        .gb_wr_data_o           (gb_wr_data),

        .wb_rd_en_o             (wb_rd_en),
        .wb_rd_addr_o           (wb_rd_addr),
        .wb_rd_data_i           (wb_rd_data),
        .bias_data_i            (bias_data),

        .cfg_img_w_i            (cfg_w),
        .cfg_img_h_i            (cfg_h),
        .cfg_kernel_r_i         (cfg_k),
        .cfg_num_input_channels (cfg_num_ch),
        .do_Pooling_i           (cfg_do_pool),
        .has_bias_i             (cfg_do_bias),
        .do_ReLU_i              (cfg_do_relu),
        .has_quant_i            (cfg_do_quant),
        .quant_shift_i          (cfg_quant_shift),

        .start_i                (ctrl_start_core),
        .busy_o                 (accelerator_busy_o),
        .done_o                 (ctrl_done_core)
        // .ib_weight_loaded_o     (weight_loaded_ack)
    );
endmodule : lenet5_top
