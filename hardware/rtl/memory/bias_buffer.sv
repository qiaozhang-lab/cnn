/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-26 21:10:28
 * @LastEditTime: 2025-12-27 16:09:41
 * @LastEditors: Qiao Zhang
 * @Description: Bias Buffer. Replaces ROM.
 * @FilePath: /cnn/hardware/rtl/memory/bias_buffer.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module bias_buffer #(
    parameter int DEPTH = 64,
    parameter int ADDR_W = $clog2(DEPTH)
)(
    input   logic               clk_i           ,
    input   logic               rst_async_n_i   ,

    // Loader Interface
    input   logic               loader_wr_en_i  ,
    input   logic[ADDR_W-1 : 0] loader_wr_addr_i,
    input   logic[K_CHANNELS-1 : 0] [ACC_WIDTH-1 : 0]   loader_wr_data_i    ,

    // Compute Interface (Result Handler)
    input   logic               rd_en_i         ,
    input   logic[ADDR_W-1 : 0] rd_addr_i       ,
    output  logic[K_CHANNELS-1 : 0] [ACC_WIDTH-1 : 0]   rd_data_o
);

    var logic [K_CHANNELS-1 : 0] [ACC_WIDTH-1 : 0]  mems    [DEPTH ]    ;

    always_ff @( posedge clk_i ) begin : write_logic
        if(loader_wr_en_i)
            mems[loader_wr_addr_i] <= loader_wr_data_i;
    end : write_logic

    assign  rd_data_o = mems[rd_addr_i];

endmodule : bias_buffer
