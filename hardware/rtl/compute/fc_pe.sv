/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-31 03:50:28
 * @LastEditTime: 2025-12-31 03:50:29
 * @LastEditors: Qiao Zhang
 * @Description:
 * @FilePath: /cnn/hardware/rtl/compute/fc_pe.sv
 */
`timescale 1ns/1ps
`include "definitions.sv"

module fc_pe (
    input   logic               clk_i,
    input   logic               rst_async_n_i,
    input   logic               clear_acc_i,
    input   logic               enable_i,

    input   logic signed [7:0]  pixel_i,
    input   logic signed [7:0]  weight_i,

    output  logic signed [31:0] result_o
);

    logic signed [31:0] acc;

    always_ff @(posedge clk_i or negedge rst_async_n_i) begin
        if(!rst_async_n_i) begin
            acc <= '0;
        end else begin
            if(clear_acc_i) begin
                acc <= '0;
            end else if(enable_i) begin
                acc <= acc + (pixel_i * weight_i);
            end
        end
    end

    assign result_o = acc;

endmodule
