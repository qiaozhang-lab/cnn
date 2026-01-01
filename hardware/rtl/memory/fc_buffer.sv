/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-31 10:22:19
 * @LastEditTime: 2026-01-01 19:44:36
 * @LastEditors: Qiao Zhang
 * @Description: Local Buffer for FC layers. Acts as Ping-Pong storage.
 * @FilePath: /cnn/hardware/rtl/memory/fc_buffer.sv
 */

`timescale 1ns/1ps
module fc_buffer #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 1024
)(
    input   logic               clk_i,
    input   logic               wr_en_i,
    input   logic [9:0]         wr_addr_i,
    input   logic [WIDTH-1:0]   wr_data_i,

    input   logic               rd_en_i,
    input   logic [9:0]         rd_addr_i,
    output  logic [WIDTH-1:0]   rd_data_o
);

    logic [WIDTH-1:0] mem [DEPTH];

    always_ff @(posedge clk_i) begin
        if(wr_en_i)
            mem[wr_addr_i] <= wr_data_i;
    end

    // Read Logic (1 cycle latency standard)
    always_ff @(posedge clk_i) begin
        if(rd_en_i)
            rd_data_o <= mem[rd_addr_i];
    end

endmodule
