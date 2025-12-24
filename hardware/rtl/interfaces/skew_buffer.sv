/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-19 20:21:55
 * @LastEditTime: 2025-12-19 20:42:42
 * @LastEditors: Qiao Zhang
 * @Description: Skew Buffer to align the inputs for Systolic Arrays
 *              Delay inputs data by "DELAY" cycles
 * @FilePath: /cnn/hardware/rtl/interfaces/skew_buffer.sv
 */
`timescale 1ns/1ps
`include "definitions.sv"

module skew_buffer #(
    parameter int   WIDTH = INT_WIDTH,
    parameter int   DELAY = 0
) (
    input   logic               clk_i           ,
    input   logic               rst_async_n_i   ,
    input   logic[WIDTH-1 : 0]  data_i          ,
    output  logic[WIDTH-1 : 0]  data_o
);

    generate
        if(DELAY == 0)
            // No delay, pass through
            assign data_o = data_i;
        else begin
            var logic[WIDTH-1 : 0]  shift_regs [DELAY];

            always_ff @( posedge clk_i, negedge rst_async_n_i ) begin : update_shift_regs
                if(rst_async_n_i) begin
                    shift_regs <= '{default: '0};
                end else begin
                    shift_regs <= '{shift_regs[DELAY-2:0], data_i};
                end
            end : update_shift_regs

            assign data_o = shift_regs[DELAY-1];
        end

    endgenerate
endmodule : skew_buffer
