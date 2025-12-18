/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-18 23:27:57
 * @LastEditTime: 2025-12-19 00:19:08
 * @LastEditors: Qiao Zhang
 * @Description:  Im2Col Address Generator for Conv2D
 *               Generates sequence for Matrix B (Input Patch Stream)
 * @FilePath: /cnn/hardware/rtl/control/img2col_addr_gen.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module img2col_addr_gen(
    // system inputs
    input   logic           clk_i           ,
    input   logic           rst_async_n_i   ,

    // systolic arrays interface
    input   logic                       systolic_ready_i,
    input   logic                       start_i         ,// Start processing a whole image

    // SRAM interface
    output  logic                       valid_o         ,
    output  logic[SRAM_ADDR_W-1 : 0]    sram_rd_addr_o  ,
    output  logic                       last_out_o       // end of image
);

    // =============================================================
    // 1. Output Feature Map Dimensions
    // =============================================================
        // activate slip windows position coordinate(top left corner)
    localparam int OUT_W = IMG_W - K_R + 1;// 28-5+1=24
    localparam int OUT_H = IMG_H - K_S + 1;// 28-5+1=24

    // =============================================================
    // 2. Counters (State Machine)
    // =============================================================

endmodule
