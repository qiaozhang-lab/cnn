/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-19 23:11:52
 * @LastEditTime: 2025-12-28 01:02:38
 * @LastEditors: Qiao Zhang
 * @Description: Systolic Wrapper (Final Integration).
 *               - Integrates Input Buffer, ARR, Weight Scheduler, Weight ROM, and Systolic Array.
 *               - Implements Global Control Logic for multi-row processing.
 * @FilePath: /cnn/hardware/rtl/top/systolic_wrapper.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module systolic_wrapper #(
    parameter int PTR_WIDTH = 32  // enough to hold 1920
)(
    input   logic           clk_i           ,
    input   logic           rst_async_n_i   ,

    // ===================================
    // 1. External Memory Interface
    // ===================================
        // A. Global Buffer Read Interface (For Input Buffer)
    output  logic[K_CHANNELS-1 : 0]         gb_rd_en_o          ,
    output  logic[SRAM_ADDR_W-1 : 0]        gb_rd_addr_o        ,
    input   logic[K_CHANNELS-1 : 0][INT_WIDTH-1 : 0]    gb_rd_data_i    ,

        // B. Global Buffer Write Interface (For Result Handler)
    output  logic[K_CHANNELS-1 : 0]         gb_wr_en_o          ,
    output  logic[K_CHANNELS-1 : 0] [SRAM_ADDR_W-1 : 0] gb_wr_addr_o    ,
    output  logic[K_CHANNELS-1 : 0] [INT_WIDTH-1 : 0]   gb_wr_data_o    ,

        // C. Weight Buffer Read Interface (For Weight Scheduler)
    output  logic                           wb_rd_en_o          ,
    output  logic[SRAM_ADDR_W-1 : 0]        wb_rd_addr_o        ,
    input   logic[K_CHANNELS-1 : 0][INT_WIDTH-1 : 0]    wb_rd_data_i    ,

        // D. Bias Buffer Input
    input   logic[K_CHANNELS-1 : 0][ACC_WIDTH-1 : 0]    bias_data_i     ,

    // ===================================
    // 2. Runtime Configuration
    // ===================================
        // Logical Width: 28 (LeNet) or 1920 (HD)
        // This tells the pointers when to stop and the buffer when to wrap.
    input   logic[PTR_WIDTH-1 : 0]  cfg_img_w_i     ,// Logical Image Size: LeNet5 -> 28
    input   logic[PTR_WIDTH-1 : 0]  cfg_img_h_i     ,// Logical Image Size: LeNet5 -> 28
    input   logic[3 : 0]            cfg_kernel_r_i  ,// Logical Kernel Size: LeNet5 -> 5
        // TDM Config
    input   logic[15 : 0]           cfg_num_input_channels, // e.g. 1 for Conv1, 6 for Conv2
        // Feature Switches
    input   logic                   do_Pooling_i    ,
    input   logic                   has_bias_i      ,
    input   logic                   do_ReLU_i       ,
    input   logic                   has_quant_i     ,
    input   logic[4 : 0]            quant_shift_i   ,

    // ===================================
    // 3.  (Control & Status)
    // ===================================
    input   logic                   start_i         ,
    output  logic                   busy_o          ,
    output  logic                   done_o

);

    // =========================================================
    // Internal Signals
    // =========================================================
    logic [31 : 0]                              feature_map_w;
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

    // --- SA Output ---
    logic [ACC_WIDTH-1 : 0]                     result [MATRIX_A_ROW][MATRIX_B_COL];

    // --- Result Handler Signals ---
    logic [MATRIX_B_COL-1 : 0]                  rh_pe_clear_req; // RH requested clear
    logic [K_CHANNELS-1 : 0]                    rh_sram_wr_en;

    // --- Gated Signals (Controlled by TDM FSM) ---
    logic [MATRIX_B_COL-1 : 0]                  pe_clear_gated;

    // =========================================================
    // 1. TDM Control Logic (Internal FSM)
    // =========================================================
    typedef enum logic [1:0] {
        IDLE,
        RUN_PASS,
        NEXT_PASS_SETUP,
        DONE_STATE
    } sys_state_t;
    sys_state_t state, next_state;

    logic [15:0]            curr_input_ch_cnt;
    logic [PTR_WIDTH-1 : 0] output_rows_done_cnt; // the rows number of having output
    logic [PTR_WIDTH-1 : 0] total_output_rows; // all the rows which are needed to output
    logic                   pass_done;// One full image pass done
    logic                   is_last_pass;// Is this the final accumulation pass?
    logic                   ib_rst_trig;// Reset IB pointers

    assign total_output_rows = cfg_img_h_i - cfg_kernel_r_i + 1;
    assign is_last_pass      = (curr_input_ch_cnt == cfg_num_input_channels - 1);

    // FSM Update
    always_ff @(posedge clk_i or negedge rst_async_n_i) begin
        if(!rst_async_n_i) state <= IDLE;
        else state <= next_state;
    end

    // FSM Logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE:
                if (start_i) next_state = RUN_PASS;

            RUN_PASS:
                // Wait for ARR to finish all rows for this channel
                if (pass_done) begin
                    if (is_last_pass) next_state = DONE_STATE;
                    else              next_state = NEXT_PASS_SETUP;
                end

            NEXT_PASS_SETUP:
                // Spend 1 cycle to reset counters/pointers
                next_state = RUN_PASS;

            DONE_STATE:
                next_state = IDLE;
        endcase
    end

    // Counters & Control Signals
    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin : row_cnt_and_done_handle
        if(!rst_async_n_i) begin
            curr_input_ch_cnt       <= '0;
            output_rows_done_cnt    <= '0;
            pass_done               <= 1'b0;
            arr_start_trigger       <= 1'b0;
        end else begin : normal_operation
            // Default Pulsed Signals
            pass_done <= 1'b0;

            unique case(state)
                IDLE    : begin
                            curr_input_ch_cnt    <= '0;
                            output_rows_done_cnt <= '0;
                            if (start_i) arr_start_trigger <= 1'b1; // Start first pass
                        end

                RUN_PASS: begin
                            // Auto-restart ARR for next row
                            // If just finished a row (arr_row_done), trigger again unless it was the last row
                            if (arr_row_done) begin
                                output_rows_done_cnt <= output_rows_done_cnt + 1'b1;
                                if (output_rows_done_cnt + 1'b1 == total_output_rows) begin
                                    pass_done <= 1'b1;
                                    arr_start_trigger <= 1'b0; // Stop triggering ARR
                                end else begin
                                    arr_start_trigger <= 1'b1; // Keep triggering
                                end
                            end
                        end

                NEXT_PASS_SETUP: begin
                            // Prepare for next channel pass
                            curr_input_ch_cnt    <= curr_input_ch_cnt + 1'b1;
                            output_rows_done_cnt <= '0;
                            arr_start_trigger    <= 1'b1; // Trigger ARR for new pass
                        end

                DONE_STATE: begin
                            arr_start_trigger <= 1'b0;
                        end
                default :;
            endcase
        end : normal_operation
    end : row_cnt_and_done_handle

    // Output Status
    assign busy_o = (state != IDLE);
    assign done_o = (state == DONE_STATE);

    // IB Reset Trigger: Used to reset IB state machine when switching channels
    assign ib_rst_trig = (state == NEXT_PASS_SETUP) || (state == DONE_STATE);

    // =========================================================
    // 2. Gating Logic (Accumulation Control)
    // =========================================================

    // Only clear PE accumulator on the LAST pass
    assign pe_clear_gated = (is_last_pass) ? rh_pe_clear_req : '0;

    // Only write to SRAM on the LAST pass
    assign gb_wr_en_o     = (is_last_pass) ? rh_sram_wr_en : '0;

    // =========================================================
    // 3. Instantiations
    // =========================================================
        // A. Input buffer
    input_buffer_bank u_ib(
        .clk_i                  (clk_i),
        .rst_async_n_i          (rst_async_n_i),

        .start_i                (arr_start_trigger),// trigger prefetch
        .sa_done_i              (ib_rst_trig),

        // configuration
        .cfg_img_w_i            (cfg_img_w_i),
        .cfg_img_h_i            (cfg_img_h_i),
        .cfg_kernel_r_i         (cfg_kernel_r_i),
        .input_ch_sel_i         (curr_input_ch_cnt[2:0]),

        // global buffer interface
        .sram_rd_en_o           (gb_rd_en_o),
        .sram_rd_addr_o         (gb_rd_addr_o),
        .sram_rd_data_i         (gb_rd_data_i),

        // arr interface
        .pre_wave_done_i        (arr_row_done),
        .ib_ready_o             (ib_ready),
        .pop_i                  (ib_pop),
        .data_out_o             (ib_data_out)
    );

        // B. ARR
    active_row_register u_arr (
        .clk_i          (clk_i),
        .rst_async_n_i  (rst_async_n_i),

        // auto-reset trigger
        .start_i        (arr_start_trigger),

        // configuration
        .cfg_img_w_i    (cfg_img_w_i),
        .cfg_kernel_r_i (cfg_kernel_r_i),

        // arr <-> ib
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

        // SRAM Interface(weights buffer)
        .wb_rd_en_o    (wb_rd_en_o),
        .wb_addr_o     (wb_rd_addr_o),
        .wb_data_i     (wb_rd_data_i),

        // SA interface
        .west_valid_o   (west_valid),
        .west_data_o    (west_data)
    );

    // D. Systolic Arrays
    systolic_top u_systolic_top(
        .clk_i          (clk_i),
        .rst_async_n_i  (rst_async_n_i),
        .pe_clear_col_i (pe_clear_gated),

        // Weights Inputs
        .west_valid_i   (west_valid),
        .west_data_i    (west_data),
        .west_ready_o   (), // Open loop

        // North Inputs
        .north_valid_i  (north_valid),
        .north_data_i   (north_data),
        .north_ready_o  (), // Open loop

        // Result output
        .result_o       (result)
    );

    assign feature_map_w = cfg_img_w_i - cfg_kernel_r_i + 1'b1;

    // E. Result Handler
    result_handler u_res_handler (
        .clk_i                  (clk_i),
        .rst_async_n_i          (rst_async_n_i),

        // cfg & control
        .feature_map_w_i        (feature_map_w),
        .has_bias_i             (has_bias_i),
        .bias_i                 (bias_data_i),
        .do_ReLU_i              (do_ReLU_i),
        .do_Pooling_i           (do_Pooling_i),
        .has_quant_i            (has_quant_i),
        .quant_shift_i          (quant_shift_i),

        // Monitor ARR Valid signal
        .sa_valid_monitor_i (north_valid),
        .sa_result_i        (result),

        // Output Clear Signal
        .pe_clear_o         (rh_pe_clear_req),

        // FIFO Interface (Stub for now)
        .fifo_valid_o       (),

        .sram_wr_en_o       (rh_sram_wr_en),
        .sram_wr_addr_o     (gb_wr_addr_o),
        .sram_wr_data_o     (gb_wr_data_o)
    );

endmodule : systolic_wrapper
