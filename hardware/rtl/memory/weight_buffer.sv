/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-26 21:00:48
 * @LastEditTime: 2025-12-26 21:09:35
 * @LastEditors: Qiao Zhang
 * @Description: Weight Buffer (SRAM). Replaces ROM.
 *               - Loaded by System/TB before layer execution.
 *               - Read by Weight Scheduler during execution.
 * @FilePath: /cnn/hardware/rtl/memory/weight_buffer.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module weight_buffer #(
    parameter   int     DEPTH  =    SRAM_DEPTH,
    parameter   int     ADDR_W = $clog2(SRAM_DEPTH)
) (
    input   logic               clk_i           ,
    input   logic               rst_async_n_i   ,

    // --- Loader Interface (Write) ---
    input   logic               loader_wr_en_i  ,
    input   logic[ADDR_W-1 : 0] loader_wr_addr_i,
    input   logic[K_CHANNELS-1 : 0] [INT_WIDTH-1 : 0]   loader_wr_data_i    ,

    // --- Compute Interface (Read) ---
    input   logic               rd_en_i         ,
    input   logic[ADDR_W-1 : 0] rd_addr_i       ,
    output  logic[K_CHANNELS-1 : 0][INT_WIDTH-1 : 0]    rd_data_o
);

    logic   [K_CHANNELS-1 : 0]  [INT_WIDTH-1 : 0]   mems    [DEPTH] ;

    // write logic
    always_ff @( posedge clk_i ) begin : write_logic
        if(loader_wr_en_i)
            mems[loader_wr_addr_i]  <= loader_wr_data_i;
    end : write_logic

    // read logic
    always_ff @( posedge clk_i ) begin : read_logic
        if(rd_en_i)
            rd_data_o <= mems[rd_addr_i];
    end : read_logic
endmodule : weight_buffer
