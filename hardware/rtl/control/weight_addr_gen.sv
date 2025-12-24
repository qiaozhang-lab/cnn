/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-20 00:33:55
 * @LastEditTime: 2025-12-20 00:43:31
 * @LastEditors: Qiao Zhang
 * @Description: Im2Col Address Generator for Conv2D
 *               Generates sequence for Matrix A (Weights Patch Stream)
 * @FilePath: /cnn/hardware/rtl/control/weight_addr_gen.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module weight_addr_gen (
    input  logic                        clk_i           ,
    input  logic                        rst_async_n_i   ,
    input  logic                        enable          ,
    output logic[$clog2(K_R*K_S) : 0]   addr_o
);

    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin
        if(!rst_async_n_i) begin
            addr_o <= '0;
        end else begin
            if(enable) begin
                if(32'(addr_o) == (K_R*K_S-1))   addr_o <= '0;
                else                             addr_o <= addr_o + 1'b1;
            end
        end
    end
endmodule : weight_addr_gen
