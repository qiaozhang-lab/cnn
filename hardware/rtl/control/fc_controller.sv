/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-31 12:49:24
 * @LastEditTime: 2026-01-01 20:51:18
 * @LastEditors: Qiao Zhang
 * @Description:
 * @FilePath: /cnn/hardware/rtl/control/fc_controller.sv
 */

/**
 * @Description: FC Controller - Phase 1: Load & Flatten.
 *               - Reads Conv2 output (scattered in Global SRAM).
 *               - Writes linear stream to FC Buffer.
 */
`timescale 1ns/1ps
`include "definitions.sv"

module fc_controller (
    input   logic               clk_i                                       ,
    input   logic               rst_async_n_i                               ,

    // --- Control Interface ---
        // handshake
    input   logic                                   start_i                 ,// Triggered by lenet_controller's host_done_o
    input   logic                                   fc_buffer_load_done_i   ,
    input   logic                                   fc_core_done_i          ,

    output  logic                                   fc_running_o            ,// output to lenet_top for global buffer read mux
        // fc compute core config
    output  logic                                   fc_core_start_o         ,// trigger fc compute core to start
    output  logic                                   fc_calc_start_o         ,
    output  logic                                   fc_load_from_sram_o     ,
    output  logic [SRAM_ADDR_W-1 : 0]               fc_sram_load_addr_o     ,
    output  logic [31 : 0]                          fc_load_len_o           ,
    output  logic [31 : 0]                          fc_calc_len_o           ,
    output  logic                                   fc_do_bias_o            ,
    output  logic                                   fc_do_relu_o            ,
    output  logic                                   fc_do_quant_o           ,
    output  logic [4 : 0]                           fc_quant_shift_o        ,
    output  logic [9 : 0]                           fc_buffer_rd_addr_o     ,
    output  logic [9 : 0]                           fc_buffer_wr_addr_o     ,

    // --- Status ---
    output  logic                                   done_o                   // Indicates FC Complete (for now)
);

    // =========================================================
    // Parameters (Must match Conv2 Output Layout)
    // =========================================================
    parameter int L2_SRAM_BASE      = 32'h0800;
    parameter int FC1_IN_LEN        = 400; // 16ch * 5 * 5
    parameter int FC1_OUT_LEN       = 120;
    parameter int FC2_IN_LEN        = FC1_OUT_LEN;
    parameter int FC2_OUT_LEN       = 84;
    parameter int FC3_IN_LEN        = FC2_OUT_LEN;
    parameter int FC3_OUT_LEN       = 10;

    parameter int FC1_FB_RD_ADDR    =   0;
    parameter int FC1_FB_WR_ADDR    =   400;
    parameter int FC2_FB_RD_ADDR    =   FC1_FB_WR_ADDR;
    parameter int FC2_FB_WR_ADDR    =   FC1_FB_RD_ADDR;
    parameter int FC3_FB_RD_ADDR    =   FC2_FB_WR_ADDR;
    parameter int FC3_FB_WR_ADDR    =   FC2_FB_RD_ADDR;
    // =========================================================
    // FSM
    // =========================================================
    typedef enum logic [3:0] {
        IDLE        ,
        LOAD_SRAM   , // Reading from SRAM, Writing to Buffer
        FC1_RUN     ,
        FC1_WAIT    ,
        FC2_RUN     ,
        FC2_WAIT    ,
        FC3_RUN     ,
        FC3_WAIT    ,
        DONE
    } state_t;

    state_t state, next_state;

    // =========================================================
    // 1. Main FSM & Counters
    // =========================================================
    always_ff @(posedge clk_i or negedge rst_async_n_i) begin
        if(!rst_async_n_i)      state <= IDLE;
        else                    state <= next_state;
    end

    // Next State Logic
    always_comb begin
        next_state = state;
        case(state)
            IDLE        :   if(start_i)                 next_state = LOAD_SRAM;

            LOAD_SRAM   :   if(fc_buffer_load_done_i)   next_state = FC1_RUN;

            FC1_RUN     :   next_state  = FC1_WAIT;

            FC1_WAIT    :   if(fc_core_done_i)          next_state  = FC2_RUN  ;

            FC2_RUN     :   next_state  = FC2_WAIT;

            FC2_WAIT    :   if(fc_core_done_i)          next_state  = FC3_RUN ;

            FC3_RUN     :   next_state  =   FC3_WAIT ;

            FC3_WAIT    :   if(fc_core_done_i)          next_state  = DONE;

            DONE        :   next_state = IDLE; // Stay done, or wait for reset

            default     :   next_state = IDLE;
        endcase
    end

    always_comb begin : fsm_output
        // default value: avoid latch
        fc_core_start_o         = 1'b0;
        fc_calc_start_o         = 1'b0;
        fc_load_from_sram_o     = 1'b0;
        fc_sram_load_addr_o     = '0;
        fc_load_len_o           = '0;
        fc_calc_len_o           = '0;
        fc_do_bias_o            = 1'b0;
        fc_do_relu_o            = 1'b0;
        fc_do_quant_o           = 1'b0;
        fc_quant_shift_o        = '0;
        fc_buffer_rd_addr_o     = '0;
        fc_buffer_wr_addr_o     = '0;

        unique case(state)
            IDLE                :   ;// do nothing

            LOAD_SRAM           : begin
                                    fc_core_start_o         = 1'b1;
                                    fc_load_from_sram_o     = 1'b1;
                                    fc_sram_load_addr_o     = SRAM_ADDR_W'(L2_SRAM_BASE);
                                    fc_load_len_o           = FC1_IN_LEN;
                                    fc_buffer_rd_addr_o     = 10'(FC1_FB_RD_ADDR);
                                end

            FC1_RUN, FC1_WAIT   : begin
                                    fc_core_start_o         = 1'b1;
                                    fc_buffer_rd_addr_o     = 10'(FC1_FB_RD_ADDR);
                                    fc_buffer_wr_addr_o     = 10'(FC1_FB_WR_ADDR);
                                    fc_load_len_o           = FC1_IN_LEN;
                                    fc_calc_len_o           = FC1_OUT_LEN;
                                    fc_do_bias_o            = 1'b1;
                                    fc_do_relu_o            = 1'b1;
                                    fc_do_quant_o           = 1'b1;
                                    fc_quant_shift_o        = 5'd8;
                                    fc_calc_start_o         = 1'b1;
                                end

            FC2_RUN, FC2_WAIT   : begin
                                    if(state == FC2_RUN)     fc_core_start_o = 1'b1;
                                    fc_buffer_rd_addr_o     = 10'(FC2_FB_RD_ADDR);
                                    fc_buffer_wr_addr_o     = 10'(FC2_FB_WR_ADDR);
                                    fc_load_len_o           = FC2_IN_LEN;
                                    fc_calc_len_o           = FC2_OUT_LEN;
                                    fc_do_bias_o            = 1'b1;
                                    fc_do_relu_o            = 1'b1;
                                    fc_do_quant_o           = 1'b1;
                                    fc_quant_shift_o        = 5'd8;
                                    fc_calc_start_o         = 1'b1;
                                end

            FC3_RUN, FC3_WAIT   : begin
                                    if(state == FC3_RUN)     fc_core_start_o = 1'b1;
                                    fc_buffer_rd_addr_o     = 10'(FC3_FB_RD_ADDR);
                                    fc_buffer_wr_addr_o     = 10'(FC3_FB_WR_ADDR);
                                    fc_load_len_o           = FC3_IN_LEN;
                                    fc_calc_len_o           = FC3_OUT_LEN;
                                    fc_do_bias_o            = 1'b1;
                                    fc_do_relu_o            = 1'b0;
                                    fc_do_quant_o           = 1'b1;
                                    fc_quant_shift_o        = 5'd8;
                                    fc_calc_start_o         = 1'b1;
                                end
            DONE                : ;// do nothing
            default     : ;// do nothing
        endcase
    end : fsm_output

    // state output
    assign fc_running_o = (state != IDLE);
    assign done_o       = (state == DONE);

endmodule : fc_controller
