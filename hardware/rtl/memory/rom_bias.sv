/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-24 16:10:16
 * @LastEditTime: 2025-12-24 19:06:04
 * @LastEditors: Qiao Zhang
 * @Description: Bias ROM. Stores 1 bias value per output channel.
 * @FilePath: /cnn/hardware/rtl/memory/rom_bias.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module rom_bias #(
    parameter int DEPTH = ROM_BIAS_DEPTH,
    parameter int WIDTH = ACC_WIDTH,
    parameter string INIT_FILE = ROM_BIAS_INIT_FILE
)(
    input   logic               clk_i           ,
    output  logic[K_CHANNELS-1 : 0][ACC_WIDTH-1 : 0]    data_o
);
    var logic[WIDTH-1 : 0]   bias_mems [DEPTH-1 : 0];

    initial begin
        if(INIT_FILE == "")
            $display("No bias hex files!");
        else
            $readmemh(INIT_FILE, bias_mems);
    end

    genvar k;
    generate
        for(k=0; k<DEPTH; k++) begin : gen_bias_out
            assign data_o[k] = bias_mems[k];
        end : gen_bias_out
    endgenerate
endmodule : rom_bias
