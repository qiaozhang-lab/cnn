/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-19 23:11:52
 * @LastEditTime: 2025-12-24 16:39:44
 * @LastEditors: Qiao Zhang
 * @Description: Systolic Wrapper (Final Integration).
 *               - Integrates Input Buffer, ARR, Weight Scheduler, Weight ROM, and Systolic Array.
 *               - Implements Global Control Logic for multi-row processing.
 * @FilePath: /cnn/hardware/rtl/wrapper/systolic_wrapper.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module systolic_wrapper #(
    parameter int PTR_WIDTH = 32  // enough to hold 1920
)(
    input   logic           clk_i           ,
    input   logic           rst_async_n_i   ,

    // ===================================
    // 1. Runtime Configuration
    // ===================================
        // Logical Width: 28 (LeNet) or 1920 (HD)
        // This tells the pointers when to stop and the buffer when to wrap.
    input   logic[PTR_WIDTH-1 : 0]  cfg_img_w_i     ,// Logical Image Size: LeNet5 -> 28
    input   logic[PTR_WIDTH-1 : 0]  cfg_img_h_i     ,// Logical Image Size: LeNet5 -> 28
    input   logic[3 : 0]            cfg_kernel_r_i  ,// Logical Kernel Size: LeNet5 -> 5

    // ===================================
    // 2. Global Control & Status
    // ===================================
    input   logic                   start_i         ,
    output  logic                   busy_o          ,
    output  logic                   done_o          ,

    // ===================================
    // 3. SRAM Interface (Write Side)
    // ===================================
    output  logic                               rom_rd_en_o    ,
    output  logic[ROM_IMAGE_DEPTH_W-1 : 0]      rom_addr_o     ,
    input   logic[INT_WIDTH-1 : 0]              rom_data_i     ,

    // ===================================
    // 4. Systolic Interface (Read Side)
    // ===================================
        // Output dimensions automatically adapt to definitions.sv
    output  logic[ACC_WIDTH-1 : 0]  result_o[MATRIX_A_ROW][MATRIX_B_COL]

);

    // =========================================================
    // Internal Signals
    // =========================================================
    // --- Input Buffer <-> ARR ---
    logic [MAX_LINE_W-1 : 0]                    ib_pop;
    logic [MAX_LINE_W-1 : 0][INT_WIDTH-1 : 0]   ib_data_out;
    logic                                       ib_ready;

    // --- ARR control ---
    logic                                       arr_row_done;
    logic                                       arr_busy;
    logic                                       arr_start_trigger;// wrapper -> arr

    // --- ARR -> SA ---
    logic [MATRIX_B_COL-1 : 0]                  north_valid ;
    logic [MATRIX_B_COL-1 : 0][INT_WIDTH-1 : 0] north_data  ;

    // --- Weights Scheduler -> SA ---
    logic [MATRIX_A_ROW-1 : 0]                  west_valid  ;
    logic [MATRIX_A_ROW-1 : 0][INT_WIDTH-1 : 0] west_data   ;

    // --- Weights Scheduler -> ROM ---
    logic                                       rom_weights_en;
    logic [ROM_WEIGHTS_DEPTH_W-1 : 0]           rom_weights_addr;
    logic [K_CHANNELS-1 : 0][INT_WIDTH-1 : 0]   rom_weights_data;

    // --- Bias Signals ---
    logic [K_CHANNELS-1 : 0][ACC_WIDTH-1 : 0]   bias_data       ;

    // --- Global counter ---
    logic [PTR_WIDTH-1 : 0]                     output_rows_done_cnt; // the rows number of having output
    logic [PTR_WIDTH-1 : 0]                     total_output_rows; // all the rows which are needed to output
    logic                                       all_rows_finished; // a flag

    // --- Result Handle <-> SA ---
    logic [MATRIX_B_COL-1 : 0] pe_clear_cols;

    // --- SA <-> Result Handler ---
    logic signed [ACC_WIDTH-1 : 0] finial_result [MATRIX_A_ROW-1 : 0][MATRIX_B_COL-1 : 0];

    // =========================================================
    // 1. Global Control Logic
    // =========================================================
    assign total_output_rows = cfg_img_h_i - cfg_kernel_r_i + 1;

    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin : row_cnt_and_done_handle
        if(!rst_async_n_i) begin
            output_rows_done_cnt <= '0;
            // all_rows_finished    <= 1'b0;
            done_o               <= 1'b0;
        end else begin : normal_operation
            if(start_i) begin
                output_rows_done_cnt <= '0;
                // all_rows_finished    <= '0;
                done_o               <= '0;
            end else if(arr_row_done) begin
                output_rows_done_cnt <= output_rows_done_cnt + 1'b1;

                if(output_rows_done_cnt+1'b1 == total_output_rows) begin
                    // all_rows_finished <= 1'b1;
                    done_o            <= 1'b1;
                end

            end
        end : normal_operation
    end : row_cnt_and_done_handle

    assign all_rows_finished = (output_rows_done_cnt+1'b1 == total_output_rows);

    // arr auto-trigger signal as long as we don't finished, then we trigger arr
    // make arr works continue
    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin : arr_trigger_logic
        if(!rst_async_n_i) begin
            arr_start_trigger <= 1'b0;
        end else begin
            if(start_i)
                arr_start_trigger <= 1'b1;
            else if(all_rows_finished)
                arr_start_trigger <= 1'b0;
        end
    end : arr_trigger_logic

    assign busy_o = arr_busy || arr_start_trigger;

    // =========================================================
    // 2. Instantiations
    // =========================================================
        // A. Input buffer
    input_buffer_bank u_ib(
        .clk_i(clk_i),
        .rst_async_n_i(rst_async_n_i),
        .start_i(start_i),// trigger prefetch

        // configuration
        .cfg_img_w_i(cfg_img_w_i),
        .cfg_img_h_i(cfg_img_h_i),
        .cfg_kernel_r_i(cfg_kernel_r_i),

        // control
        .sa_done_i(done_o),
        .pre_wave_done_i(arr_row_done),
        .ib_ready_o(ib_ready),

        // ROM interface
        .rom_rd_en_o(rom_rd_en_o),
        .rom_data_i(rom_data_i),
        .rom_addr_o(rom_addr_o),

        // ARR interface
        .pop_i(ib_pop),
        .data_out_o(ib_data_out)
    );

        // B. ARR
    active_row_register u_arr (
        .clk_i          (clk_i),
        .rst_async_n_i  (rst_async_n_i),

        // auto-reset trigger
        .start_i        (arr_start_trigger),

        .cfg_img_w_i    (cfg_img_w_i),
        .cfg_kernel_r_i (cfg_kernel_r_i),

        .ib_ready_i     (ib_ready),
        .busy_o         (arr_busy),
        .row_done_o     (arr_row_done),

        .ib_pop_o       (ib_pop),
        .ib_data_i      (ib_data_out),

        .north_valid_o  (north_valid),
        .north_data_o   (north_data)
    );

    // C. Weights Scheduler
    weight_scheduler u_weight_sched (
        .clk_i          (clk_i),
        .rst_async_n_i  (rst_async_n_i),

        // Sync Machanism
        .enable_i       (arr_busy),       // ROM pre-read as lang as ARR busy
        .sync_i         (north_valid[0]), // Input weights as long as ARR begin working(PE0)
        .cfg_kernel_r_i (cfg_kernel_r_i),

        // ROM Interface
        .rom_rd_en_o    (rom_weights_en),
        .rom_addr_o     (rom_weights_addr),
        .rom_data_i     (rom_weights_data),

        // SA interface
        .west_valid_o   (west_valid),
        .west_data_o    (west_data)
    );

    // D. ROM weights
    rom_weights u_rom_weights(
        .clk_i          (clk_i),
        .rd_en_i        (rom_weights_en),
        .addr_i         (rom_weights_addr),
        .rd_o           (rom_weights_data)
    );

    // E. Systolic Arrays
    systolic_top u_systolic_top(
        .clk_i          (clk_i),
        .rst_async_n_i  (rst_async_n_i),
        .pe_clear_col_i(pe_clear_cols),

        // Weights Inputs
        .west_valid_i   (west_valid),
        .west_data_i    (west_data),
        .west_ready_o   (), // Open loop

        // North Inputs
        .north_valid_i  (north_valid),
        .north_data_i   (north_data),
        .north_ready_o  (), // Open loop

        // Result output
        .result_o       (result_o)
    );

    // F. ROM Bias
    rom_bias u_rom_bias(
        .clk_i(clk_i),
        .data_o(bias_data)
    );

    // =========================================================
    // H. Post-Processing: Bias Addition
    // =========================================================
    generate
        for(genvar r=0; r<MATRIX_A_ROW; r++) begin : gen_row_finial_result
            for(genvar c=0; c<MATRIX_B_COL; c++) begin : gen_col_finial_result
                assign finial_result[r][c] = signed'(result_o[r][c]) + signed'(bias_data[r]);
            end : gen_col_finial_result
        end : gen_row_finial_result
    endgenerate
    // F. Result Handler
    result_handler u_res_handler (
        .clk_i          (clk_i),
        .rst_async_n_i  (rst_async_n_i),

        // Monitor ARR Valid signal
        .sa_valid_monitor_i (north_valid),
        .sa_result_i        (finial_result),

        // Output Clear Signal
        .pe_clear_o         (pe_clear_cols),

        // FIFO Interface (Stub for now)
        .fifo_valid_o       ()
    );

endmodule : systolic_wrapper
