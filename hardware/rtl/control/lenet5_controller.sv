/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-27 12:44:32
 * @LastEditTime: 2026-01-01 20:59:20
 * @LastEditors: Qiao Zhang
 * @Description: LeNet-5 Controller - Sequences the execution of Conv1 -> Conv2 -> FC layers.
 *               - Replaces hardcoded states with an "Output Group Counter".
 *               - Calculates address offsets dynamically.
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

    parameter int       ADDR_IMG_IN = 32'h0000;
    parameter int       ADDR_L1_OUT = 32'h0400;
    parameter int       ADDR_L2_OUT = 32'h0800;

    // Constant: Size of one output feature map channel for L2 (bytes)
    // L2 Output is 5x5 (after pooling) = 25 bytes
    localparam int L2_OUT_CH_SIZE = 25;

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

    logic [2 : 0]   out_group_cnt;// output loop group counter

    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin : fsm_trans
        if(!rst_async_n_i) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end : fsm_trans

    // Counter Management
    always_ff @(posedge clk_i or negedge rst_async_n_i) begin
        if(!rst_async_n_i) begin
            out_group_cnt <= '0;
        end else begin
            // Reset before L2 starts
            if (state == IDLE || state == L1_WAIT) begin
                out_group_cnt <= '0;
            end
            // If L2 pass finished, increment counter
            else if (state == L2_WAIT && core_done_i) begin
                if (out_group_cnt < 2) // 0, 1 -> 2
                    out_group_cnt <= out_group_cnt + 1'b1;
            end
        end
    end

    always_comb begin : fsm_update
        next_state = state;
        unique case(state)
            IDLE        :   if(host_start_i)    next_state = L1_REQ_LOAD;
            // ================= LAYER 1 =================
            L1_REQ_LOAD :   if(weight_loaded_i) next_state = L1_RUN;

            L1_RUN      :   next_state          = L1_WAIT;

            L1_WAIT     :   if (core_done_i)    next_state = L2_REQ_LOAD;

            // ================= LAYER 2 =================
            L2_REQ_LOAD :   if (weight_loaded_i) next_state = L2_RUN;

            L2_RUN      :   next_state          = L2_WAIT;

            // Loop Logic: Finished Group 0, 1, 2
            L2_WAIT     :   if(core_done_i)
                                if (out_group_cnt == 2) next_state = DONE;
                                else                    next_state = L2_REQ_LOAD; // Load next group weights

            DONE        :   if (!host_start_i)      next_state = IDLE;

            default     : next_state = IDLE;
        endcase
    end : fsm_update

    always_comb begin : fsm_output
        // default value avoid latch
        req_load_weight_o           = 1'b0  ;
        layer_id_o                  = '0    ;
        core_start_o                = '0    ;
        host_done_o                 = '0    ;

        cfg_img_w_o                 = 28+2*2;
        cfg_img_h_o                 = 28+2*2;
        cfg_kernel_r_o              = 5;
        cfg_do_bias_o               = 1'b0;
        cfg_do_relu_o               = 1'b0;
        cfg_do_pool_o               = 1'b0;
        cfg_do_quant_o              = 1'b0;
        cfg_quant_shift_o           = '0;
        cfg_num_input_channels_o    = '0;
        cfg_read_base_o             = '0;
        cfg_write_base_o            = '0;

        unique case (state)
            IDLE        : ;//do nothing

            // ================= LAYER 1 =================
            L1_REQ_LOAD : begin
                            req_load_weight_o   = 1'b1;
                            layer_id_o          = 1;
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
                            cfg_read_base_o     = ADDR_IMG_IN; // assume the address of input image is SRAM blank0
                            cfg_write_base_o    = ADDR_L1_OUT; // write to 0x0400=>1024
                            core_start_o        = 1'b1;// pulse
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
                            cfg_read_base_o     = ADDR_IMG_IN;
                            cfg_write_base_o    = ADDR_L1_OUT;
                        end

            // ================= LAYER 2 =================
            L2_REQ_LOAD : begin
                            req_load_weight_o   = 1;
                            layer_id_o          = 4'd2 + {1'b0, out_group_cnt};
                        end
            L2_RUN      : begin
                            cfg_img_w_o         = 12+2; // the output of layer's pooling
                            cfg_img_h_o         = 12+2;
                            cfg_kernel_r_o      = 5;
                            cfg_do_bias_o       = 1'b1;
                            cfg_do_relu_o       = 1'b1;
                            cfg_do_pool_o       = 1'b1; // turn on pooling
                            cfg_do_quant_o      = 1'b1;
                            cfg_quant_shift_o   = 8;
                            cfg_num_input_channels_o = 6;
                            cfg_read_base_o     = ADDR_L1_OUT;
                            cfg_write_base_o    = ADDR_L2_OUT + out_group_cnt * L2_OUT_CH_SIZE;

                            core_start_o        = 1;
                        end
            L2_WAIT     : begin
                            cfg_img_w_o        = 12+2;
                            cfg_img_h_o        = 12+2;
                            cfg_kernel_r_o     = 5;
                            cfg_do_bias_o       = 1'b1;
                            cfg_do_relu_o       = 1'b1;
                            cfg_do_pool_o       = 1'b1; // turn on pooling
                            cfg_do_quant_o      = 1'b1;
                            cfg_quant_shift_o   = 8;
                            cfg_num_input_channels_o = 6;
                            cfg_read_base_o     = ADDR_L1_OUT;
                            cfg_write_base_o    = ADDR_L2_OUT + out_group_cnt * L2_OUT_CH_SIZE;
                        end
            DONE        :   host_done_o        = 1'b1;
            default     : ;// do nothing
        endcase
    end : fsm_output

endmodule : lenet_controller
