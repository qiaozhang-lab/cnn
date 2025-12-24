/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-19 20:05:23
 * @LastEditTime: 2025-12-21 03:58:05
 * @LastEditors: Qiao Zhang
 * @Description: Wide ROM for Weights.
 *               Reads 6 weights in parallel for Conv1 (K=6).
 *               File format: Each line contains 6 bytes (48 bits).
 *               Example hex line: 010203040506 (w5, w4, w3, w2, w1, w0)
 * @FilePath: /cnn/hardware/rtl/memory/rom_weights.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module rom_weights #(
    parameter int       WIDTH       = ROM_WEIGHTS_WIDTH ,
    parameter int       DEPTH       = ROM_WEIGHTS_DEPTH ,
    parameter int       WIDTH_W     = $clog2(WIDTH)     ,
    parameter int       DEPTH_W     = $clog2(DEPTH)     ,
    parameter string    INIT_FILE   = ROM_WEIGHTS_INIT_FILE
) (
    input   logic                                   clk_i           ,
    input   logic                                   rd_en_i         ,
    input   logic[DEPTH_W-1 : 0]                    addr_i          ,
    output  logic[K_CHANNELS-1 : 0][WIDTH-1 : 0]    rd_o
);

    var logic[K_CHANNELS-1 : 0][WIDTH-1 : 0]   mems[DEPTH] ;

    initial begin
        if(INIT_FILE == "")     $display("Warning, no initial files is specified");
            else begin
                $display("ROM_WEIGHTS: Loading model... \n from %s",INIT_FILE);
                $readmemh(INIT_FILE,mems);
            end
    end
    always_ff @( posedge clk_i) begin
            if(rd_en_i) rd_o <= mems[addr_i];
    end
endmodule : rom_weights
