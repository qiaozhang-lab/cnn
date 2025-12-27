/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-27 12:44:32
 * @LastEditTime: 2025-12-27 23:12:29
 * @LastEditors: Qiao Zhang
 * @Description: LeNet-5 Controller.
 *               Sequences the execution of Conv1 -> Conv2 -> FC layers.
 * @FilePath: /cnn/hardware/rtl/control/lenet5_controller.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module lenet_controller(
    input   logic               clk_i           ,
    input   logic               rst_async_n_i   ,

    // --- Interaction with Host/Testbench --
    input   logic               host_start_i    ,
    output  logic               host_done_o     ,

    // Weight Load Handshake
    output  logic               req_load_weight_o   ,
    output  logic[3 : 0]        layer_id_o      ,
    input   logic               weight_loaded_i ,

    // --- Interaction with Systolic Wrapper (Core) ---
    // Config
    output  logic [31 : 0]      cfg_img_w_o,
    output  logic [31 : 0]      cfg_img_h_o,
    output  logic [3 : 0]       cfg_kernel_r_o,
    output  logic               cfg_do_bias_o,
    output  logic               cfg_do_relu_o,
    output  logic               cfg_do_pool_o,
    output  logic               cfg_do_quant_o,
    output  logic [4 : 0]       cfg_quant_shift_o,
    output  logic [31 : 0]      cfg_read_base_o,
    output  logic [31 : 0]      cfg_write_base_o,
    output  logic [15 : 0]      cfg_num_input_channels_o,
    // Control
    output  logic               core_start_o,
    input   logic               core_done_i
);

    typedef enum logic[3 : 0] {
        IDLE,
        // Layer 1: Conv 1x6 (28x28 -> 24x24 -> Pool 12x12)
        L1_REQ_LOAD,
        L1_RUN,
        L1_WAIT,

        // Layer 2: Conv 6x16 (12x12 -> 8x8 -> Pool 4x4)
        L2_REQ_LOAD,
        L2_RUN,
        L2_WAIT,

        DONE
    } state_t;

    state_t state, next_state;

    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin : fsm_trans
        if(!rst_async_n_i) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end : fsm_trans

    always_comb begin : fsm_update
        next_state = state;

        req_load_weight_o   = 1'b0  ;
        layer_id_o          = '0    ;
        core_start_o        = '0    ;
        host_done_o         = '0    ;

        cfg_img_w_o         = 28+2*2;
        cfg_img_h_o         = 28+2*2;
        cfg_kernel_r_o      = 5;
        cfg_do_bias_o       = 1'b0;
        cfg_do_relu_o       = 1'b0;
        cfg_do_pool_o       = 1'b0;
        cfg_do_quant_o      = 1'b0;
        cfg_quant_shift_o   = '0;
        cfg_num_input_channels_o  = '0;
        cfg_read_base_o     = '0;
        cfg_write_base_o    = '0;

        unique case(state)
            IDLE        :   if(host_start_i)    next_state = L1_REQ_LOAD;
            // ================= LAYER 1 =================
            L1_REQ_LOAD : begin
                        req_load_weight_o = 1'b1;
                        layer_id_o        = 1;
                        if(weight_loaded_i) next_state = L1_RUN;
                    end

            L1_RUN      : begin
                        cfg_img_w_o         = 28+2*2;
                        cfg_img_h_o         = 28+2*2;
                        cfg_kernel_r_o      = 5;
                        cfg_do_bias_o       = 1'b1;
                        cfg_do_relu_o       = 1'b1;
                        cfg_do_pool_o       = 1'b1; // turn on pooling
                        cfg_do_quant_o      = 1'b1;
                        cfg_quant_shift_o   = 8;
                        cfg_num_input_channels_o = 1;
                        cfg_read_base_o     = 32'h0000_0000; // assume the address of input image is SRAM blank0
                        cfg_write_base_o    = 32'h0000_0400; // write to 0x0400=>1024

                        core_start_o        = 1'b1;// pulse
                        next_state          = L1_WAIT;
                    end

            L1_WAIT     : begin
                        // keep cfg
                        cfg_img_w_o         = 28+2*2;
                        cfg_img_h_o         = 28+2*2;
                        cfg_kernel_r_o      = 5;
                        cfg_do_bias_o       = 1'b1;
                        cfg_do_relu_o       = 1'b1;
                        cfg_do_pool_o       = 1'b1; // turn on pooling
                        cfg_do_quant_o      = 1'b1;
                        cfg_quant_shift_o   = 8;
                        cfg_num_input_channels_o = 1;
                        cfg_read_base_o     = 32'h0000_0000;
                        cfg_write_base_o    = 32'h0000_0400;

                        if (core_done_i) next_state = L2_REQ_LOAD;
                    end

            // ================= LAYER 2 =================
            L2_REQ_LOAD : begin
                        req_load_weight_o   = 1;
                        layer_id_o          = 2; // ID 2 = Conv2
                        if (weight_loaded_i) next_state = L2_RUN;
                    end

            L2_RUN: begin
                        cfg_img_w_o         = 12+2; // the output of layer's pooling
                        cfg_img_h_o         = 12+2;
                        cfg_kernel_r_o      = 5;
                        cfg_do_bias_o       = 1'b1;
                        cfg_do_relu_o       = 1'b1;
                        cfg_do_pool_o       = 1'b1; // turn on pooling
                        cfg_do_quant_o      = 1'b1;
                        cfg_quant_shift_o   = 8;
                        cfg_num_input_channels_o = 6;
                        cfg_read_base_o     = 32'h0000_0400;
                        cfg_write_base_o    = 32'h0000_0800;

                        core_start_o        = 1;
                        next_state          = L2_WAIT;
                    end

            L2_WAIT: begin
                        cfg_img_w_o        = 12+2;
                        cfg_img_h_o        = 12+2;
                        cfg_kernel_r_o     = 5;
                        cfg_do_bias_o       = 1'b1;
                        cfg_do_relu_o       = 1'b1;
                        cfg_do_pool_o       = 1'b1; // turn on pooling
                        cfg_do_quant_o      = 1'b1;
                        cfg_quant_shift_o   = 8;
                        cfg_num_input_channels_o = 6;
                        cfg_read_base_o    = 32'h0000_0400;
                        cfg_write_base_o   = 32'h0000_0800;

                        if (core_done_i) next_state = DONE;
                    end

            DONE: begin
                        host_done_o        = 1;
                        if (!host_start_i) next_state = IDLE;
                    end
            default     :;
        endcase
    end : fsm_update
endmodule : lenet_controller
