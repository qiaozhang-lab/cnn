/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-23 08:12:52
 * @LastEditTime: 2025-12-29 07:00:26
 * @LastEditors: Qiao Zhang
 * @Description: Result Handler - Result Handler - With Quantization & SRAM Interface.
 * @FilePath: /cnn/hardware/rtl/post_process/result_handler.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module result_handler (
    input   logic                                       clk_i           ,
    input   logic                                       rst_async_n_i   ,
    input   logic                                       flush_i         ,

    // Config & Control
    input   logic[31 : 0]                               feature_map_w_i ,
    input   logic                                       has_bias_i  ,
    input   logic                                       do_ReLU_i   ,
    input   logic                                       do_Pooling_i,
    input   logic                                       has_quant_i ,
    input   logic[4 : 0]                                quant_shift_i,

    // Monitor North Valid falling edge
    input   logic[MATRIX_B_COL-1 : 0]                   acc_valid_i ,
    input   logic[ACC_WIDTH-1 : 0]                      acc_result_i[MATRIX_A_ROW][MATRIX_B_COL]  ,

    // bias input
    input   logic[K_CHANNELS-1 : 0][ACC_WIDTH-1 : 0]    bias_i  ,

    // Debug
    output  logic                                       fifo_valid_o ,

    // SRAM Write Interface (To Global Buffer)
    output  logic[K_CHANNELS-1 : 0]                     sram_wr_en_o                ,
    output  logic[K_CHANNELS-1 : 0][SRAM_ADDR_W-1 : 0]  sram_wr_addr_o ,
    output  logic[K_CHANNELS-1 : 0][INT_WIDTH-1 : 0]    sram_wr_data_o
);

    // =========================================================
    // 1. Edge Detection
    // =========================================================

    logic [MATRIX_B_COL-1 : 0] trigger_base;

    assign trigger_base = acc_valid_i;
    assign fifo_valid_o = |trigger_base;

    // =========================================================
    // 2. Skewed Capture Logic
    // =========================================================
    // We need to create a delay chain as different Channel has different clear trigger signal
    // capture_trig[channel][column]
    logic [MATRIX_B_COL-1 : 0] capture_trig [MATRIX_A_ROW];

    // Channel 0 has no-delay, directly trigger_base
    assign capture_trig[0] = trigger_base;

    // Channel 1..5: delay row(channel) by row
    genvar r;
    generate
        for (r = 1; r < MATRIX_A_ROW; r++) begin : gen_capture_skew
            always_ff @(posedge clk_i or negedge rst_async_n_i) begin
                if (!rst_async_n_i)
                    capture_trig[r] <= '0;
                else
                    // delay a cycle for Ch[r-1] -> Ch[r]
                    capture_trig[r] <= capture_trig[r-1];
            end
        end : gen_capture_skew
    endgenerate

    // =========================================================
    // 3. Serialization + Arithmetic (Combinational Pre-Processing)
    // =========================================================
    logic [K_CHANNELS-1 : 0]    stream_valid_raw    ;
    logic [ACC_WIDTH-1 : 0]     stream_data_raw [K_CHANNELS] ;

    always_comb begin : bias_ReLU_handle
        stream_valid_raw = '0;
        stream_data_raw  = '{default: '0};

        for(int k=0; k<K_CHANNELS; k++) begin
            for(int c=0; c< MATRIX_B_COL; c++) begin
                if(capture_trig[k][c]) begin : sa_done_trigger_preprocess
                    logic signed [ACC_WIDTH-1 : 0]  val_biased;

                    stream_valid_raw[k] = 1'b1;
                    // Bias handle
                    val_biased = (has_bias_i) ? (signed'(acc_result_i[k][c]) + signed'(bias_i[k])) : signed'(acc_result_i[k][c]);
                    // ReLU handle
                    stream_data_raw[k] = (do_ReLU_i && val_biased[ACC_WIDTH-1]) ? '0 : val_biased ;
                end : sa_done_trigger_preprocess
            end
        end
    end : bias_ReLU_handle

    // =========================================================
    // 4. Pooling Module Instantiation
    // =========================================================

    logic [K_CHANNELS-1 : 0]    pooling_valid_out   ;
    logic [ACC_WIDTH-1 : 0]     pooling_data_out[K_CHANNELS];

    logic [K_CHANNELS-1:0]      pool_ready_dummy; // we always assume the pooling input is ready

    pooling_top #(
        .WIDTH(ACC_WIDTH),
        .DEPTH(MAX_LINE_W/2)
    ) u_pooling (
        .clk_i(clk_i),
        .rst_async_n_i(rst_async_n_i),

        .feature_map_w_i(feature_map_w_i),

        .valid_i(stream_valid_raw),
        .ready_o(pool_ready_dummy),// we assume we could handle this pooling fast enough
        .data_i(stream_data_raw),

        .valid_o(pooling_valid_out),
        .ready_i({K_CHANNELS{1'b1}}),// assume we always ready to handle the pooling data
        .data_o(pooling_data_out)
    );

    // =========================================================
    // 5. Output Mux & Quantization & SRAM Write
    // =========================================================

    // different channels need independent write pointer:
    // because their ending moments are different so they need different write pointer
    logic [SRAM_ADDR_W-1 : 0]   wr_ptrs [K_CHANNELS]    ;

    function automatic logic signed [INT_WIDTH-1 : 0] saturate_cast(
        input   logic signed [ACC_WIDTH-1 : 0]  val
    );
        if(val > 127)
            return 8'd127;
        else if(val < -128)
            return -8'd128;
        else
            return val[INT_WIDTH-1 : 0];
    endfunction

    always_ff @(posedge clk_i or negedge rst_async_n_i) begin : mem_write_logic
        if(!rst_async_n_i) begin : reset_logic
            for(int k=0; k<K_CHANNELS; k++) begin
                wr_ptrs[k]          <= '0;
                sram_wr_en_o[k]     <= 1'b0;
                sram_wr_addr_o[k]   <= '0;
                sram_wr_data_o[k]   <= '0;
            end
        end : reset_logic
        else if(flush_i) begin
            wr_ptrs        <= '{default: '0};
            sram_wr_en_o   <= '0;
            sram_wr_addr_o <= '0;
            sram_wr_data_o <= '0;
        end
        else begin : normal_operation
            for (int k = 0; k < K_CHANNELS; k++) begin
                    logic                           final_wr_en     ;
                    logic        [ACC_WIDTH-1 : 0]  final_wr_data   ;
                    logic signed [ACC_WIDTH-1 : 0]  shifted_val     ;

                    // 1. Mux Selection
                    if(do_Pooling_i) begin
                        final_wr_en   = pooling_valid_out[k]  ;
                        final_wr_data = pooling_data_out[k]   ;
                    end else begin
                        final_wr_en   = stream_valid_raw[k]   ;
                        final_wr_data = stream_data_raw[k]    ;
                    end

                    // 2. Quantization (Right Shift + Saturate)
                    // Shift first
                    shifted_val = (has_quant_i) ? signed'(final_wr_data) >>> quant_shift_i :
                                                    final_wr_data;

                    // 3. Drive SRAM Interface
                    sram_wr_en_o[k]     <= final_wr_en  ;
                    sram_wr_addr_o[k]   <= wr_ptrs[k]  ;
                    sram_wr_data_o[k]   <= saturate_cast(shifted_val);

                    // 4. Update Pointer
                    if(final_wr_en) begin// write and move to next col
                        wr_ptrs[k] <= wr_ptrs[k] + 1'b1;
                    end
            end
        end : normal_operation
    end : mem_write_logic
endmodule : result_handler
