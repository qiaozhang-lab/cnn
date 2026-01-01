/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-31 03:51:19
 * @LastEditTime: 2025-12-31 03:52:29
 * @LastEditors: Qiao Zhang
 * @Description:
 * @FilePath: /cnn/hardware/rtl/compute/fc_systolic_array.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module fc_systolic_array #(
    parameter int NUM_PE = 100
)(   input   logic               clk_i,
    input   logic               rst_async_n_i,

    // control
    input   logic               clear_acc_i,
    input   logic               calc_en_i,

    // data stream
    input   logic signed [7:0]  pixel_broadcast_i,

    // weights stream
    input   logic signed [7:0]  weights_vector_i [NUM_PE],

    // result output
    output  logic signed [31:0] results_vector_o [NUM_PE]
);

    genvar i;
    generate
        for(i=0; i<NUM_PE; i++) begin : gen_fc_pes
            fc_pe u_pe (
                .clk_i          (clk_i),
                .rst_async_n_i  (rst_async_n_i),
                .clear_acc_i    (clear_acc_i),
                .enable_i       (calc_en_i),

                .pixel_i        (pixel_broadcast_i),
                .weight_i       (weights_vector_i[i]),

                .result_o       (results_vector_o[i])
            );
        end
    endgenerate

endmodule
