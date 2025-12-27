/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-25 00:19:06
 * @LastEditTime: 2025-12-28 01:01:39
 * @LastEditors: Qiao Zhang
 * @Description: Pooling Top - Instantiates 6 parallel pooling cores.
 * @FilePath: /cnn/hardware/rtl/post_process/pooling_top.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module pooling_top #(
    parameter   int     WIDTH = ACC_WIDTH,
    parameter   int     DEPTH = MAX_LINE_W/2
) (
    // system input
    input   logic                   clk_i           ,
    input   logic                   rst_async_n_i   ,

    input   logic[31 : 0]           feature_map_w_i ,

    input   logic[K_CHANNELS-1 : 0] valid_i         ,
    output  logic[K_CHANNELS-1 : 0] ready_o         ,
    input   logic[WIDTH-1 : 0]      data_i[K_CHANNELS]   ,

    output  logic[K_CHANNELS-1 : 0] valid_o         ,
    input   logic[K_CHANNELS-1 : 0] ready_i         ,
    output  logic[WIDTH-1 : 0]      data_o[K_CHANNELS]
);

    generate
        for(genvar k=0; k<K_CHANNELS; k++) begin : gen_pooling_row
            pooling_core #(
                .WIDTH(WIDTH),
                .DEPTH(DEPTH)
            ) u_pooling_core (
                .clk_i(clk_i),
                .rst_async_n_i(rst_async_n_i),

                .feature_map_w_i(feature_map_w_i),

                .valid_i(valid_i[k]),
                .ready_o(ready_o[k]),
                .data_i(data_i[k]),

                .valid_o(valid_o[k]),
                .ready_i(ready_i[k]),
                .data_o(data_o[k])
            );
        end : gen_pooling_row
    endgenerate
endmodule : pooling_top
