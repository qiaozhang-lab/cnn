/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-25 23:41:48
 * @LastEditTime: 2026-01-01 02:39:12
 * @LastEditors: Qiao Zhang
 * @Description: Global Buffer - 6 Banks of SRAM.
 *               - Stores Feature Maps (8-bit Quantized).
 *               - Banked structure allows parallel access.
 * @FilePath: /cnn/hardware/rtl/memory/global_buffer.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module global_buffer #(
    parameter   int     DEPTH   =   SRAM_DEPTH,
    parameter   int     ADDR_W  =   $clog2(DEPTH)
) (
    input   logic               clk_i           ,
    input   logic               rst_async_n_i   ,

    // write ports
    input   logic[K_CHANNELS-1 : 0] wr_en_i                       ,
    input   logic[K_CHANNELS-1 : 0][ADDR_W-1 : 0]     wr_addr_i   ,
    input   logic[K_CHANNELS-1 : 0][INT_WIDTH-1 : 0]  wr_data_i   ,

    // read ports
    input   logic[K_CHANNELS-1 : 0] rd_en_i                       ,
    input   logic[K_CHANNELS-1 : 0][ADDR_W-1 : 0]     rd_addr_i   ,
    output  logic[K_CHANNELS-1 : 0][INT_WIDTH-1 : 0]  rd_data_o
);

    generate
        for(genvar k=0; k<K_CHANNELS; k++) begin : gen_sram_banks
            var logic [INT_WIDTH-1 : 0]     mems [DEPTH];

            always_ff @( posedge clk_i ) begin : write_logic
                if(wr_en_i[k])
                    mems[wr_addr_i[k]] <= wr_data_i[k]   ;
            end : write_logic

            always_ff @( posedge clk_i ) begin : read_logic
                if(rd_en_i[k])
                    rd_data_o[k] <= mems[rd_addr_i[k]]  ;
                else
                    rd_data_o[k] <= '0  ;
            end : read_logic
        end : gen_sram_banks
    endgenerate

endmodule : global_buffer
