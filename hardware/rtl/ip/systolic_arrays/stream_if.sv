/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-13 14:21:26
 * @LastEditTime: 2025-12-13 14:43:00
 * @LastEditors: Qiao Zhang
 * @Description: A stream interface between data source/pe and pe/result output.
 * @FilePath: /systolic_arrays/rtl/stream_if.sv
 */
`ifndef STREAM_IF
    `define STREAM_IF

    `timescale 1ns/1ps
    `include "definitions.sv"

    interface stream_if(
        input logic     clk         ,
        input logic     rst_async_n
    );

    logic                       valid   ;
    logic                       ready   ;
    logic[DATA_WIDTH-1 : 0]     data    ;

    // send valid and data signals to slave, receive ready signal from slave
    modport master (
        input      ready,
        output     valid,
        output     data
    );

    // receive valid signal from master, send data and ready signal to master
    modport slave (
        input      valid,
        input      data ,
        output     ready
    );

    endinterface : stream_if
`endif
