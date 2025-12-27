/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-12 22:06:02
 * @LastEditTime: 2025-12-23 07:55:45
 * @LastEditors: Qiao Zhang
 * @Description: The processing element unit for systolic arrays.
 * @FilePath: /cnn/hardware/rtl/ip/systolic_arrays/pe.sv
 */

/* we default to think the Matrix A is on the left, the Matrix B is on the top */
`timescale 1ns/1ps
`include "definitions.sv"

module pe (
    // system input
    input logic         clk_i           ,
    input logic         rst_async_n_i   ,
    input logic         clear_acc_i     ,

    stream_if.slave     din_west        ,// data from left(west)
    stream_if.master    dout_east       ,// data output right(east)
    stream_if.slave     din_north       ,// data from top(north)
    stream_if.master    dout_south      ,// data output bottom(south)

    output logic signed [ACC_WIDTH-1 : 0]  result_o
);

    // declare some internal register for latching data
    logic   signed [ACC_WIDTH-1 : 0]   acc_result      ;
    logic   signed [DATA_WIDTH-1 : 0]  matrix_row      ;
    logic   signed [DATA_WIDTH-1 : 0]  matrix_col      ;
    logic                              row_valid_reg   ;
    logic                              col_valid_reg   ;

    // a flag to check if handshake in the row and column direct
    logic                       row_handshake;
    logic                       col_handshake;

    //  ready if pe don't have internal data OR downstream will accept internal data
    assign  din_west.ready  = (~row_valid_reg) || dout_east.ready;
    assign  din_north.ready = (~col_valid_reg) || dout_south.ready;

    assign  row_handshake = din_west.valid && din_west.ready;
    assign  col_handshake = din_north.valid && din_north.ready;
    // a flag for data could be systolic propagation
    logic   fire;

    // fire only when both row and column handshake
    assign fire = row_handshake && col_handshake ;

    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin : update_logic
        if(!rst_async_n_i) begin : reset_logic
            acc_result          <= '0   ;
            matrix_row          <= '0   ;
            matrix_col          <= '0   ;
            row_valid_reg       <= 1'b0 ;
            col_valid_reg       <= 1'b0 ;
        end : reset_logic
        else begin : normal_operation
            if(din_west.ready) begin : row_handle
                if(din_west.valid) begin
                    row_valid_reg <= 1'b1;
                    matrix_row    <= din_west.data;
                end else begin
                    row_valid_reg <= 1'b0;
                end
            end : row_handle

            if(din_north.ready) begin : column_handle
                if(din_north.valid) begin
                    col_valid_reg <= 1'b1;
                    matrix_col    <= din_north.data;
                end else begin
                    col_valid_reg <= 1'b0;
                end
            end : column_handle

            if(clear_acc_i)
                acc_result <= '0;
            else if(fire)
                acc_result <= din_west.data * din_north.data + acc_result;

        end : normal_operation
    end : update_logic

    // output assignment
    assign  dout_east.valid  = row_valid_reg;
    assign  dout_south.valid = col_valid_reg;
    assign  dout_east.data   = matrix_row;
    assign  dout_south.data  = matrix_col;
    assign  result_o         = acc_result;

endmodule
