/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-24 20:17:52
 * @LastEditTime: 2025-12-28 01:02:10
 * @LastEditors: Qiao Zhang
 * @Description: Max Pooling Core (2x2, Stride 2).
 *               - Uses Line Buffer to store the previous row's results.
 *               - Streaming interface: Accepts 1 pixel/clk, outputs 1 pixel every 4 clks.
 * @FilePath: /cnn/hardware/rtl/post_process/pooling_core.sv
 */

/*
    Design Thoughts:
        - Even Rows: store  the horizontal max value calculated into line buffer
        - Odd Rows: compare the horizontal max value calculated with the value which is the corresponding position(max value in the last row) -> find the max value
*/

`timescale 1ns/1ps
`include "definitions.sv"

module pooling_core #(
    parameter int WIDTH = ACC_WIDTH,
    parameter int DEPTH = MAX_LINE_W/2
)(
    // system input
    input   logic               clk_i           ,
    input   logic               rst_async_n_i   ,

    // Config
    input   logic[31 : 0]       feature_map_w_i ,

    // Input Stream
    input   logic               valid_i         ,
    output  logic               ready_o         ,
    input   logic[WIDTH-1 : 0]  data_i          ,

    // Output   Stream
    output  logic               valid_o         ,
    input   logic               ready_i         ,
    output  logic[WIDTH-1 : 0]  data_o
);

    // =========================================================
    // 1. Internal State & Counters
    // =========================================================
    logic [31:0]            x_cnt;// Column counter(0 ... W-1)
    logic                   even_row;// 0: Even Row(Store), 1: Odd Row(Output)

    logic [WIDTH-1 : 0]     pixel_even_col;// Register to store the first pixel of a 2x1 block
    logic [WIDTH-1 : 0]     h_max;// Horizontal Max (Combinational)

    logic                   fire  ;
    logic                   valid_reg;

    assign                  ready_o = !valid_o || ready_i;
    assign                  fire = ready_o && valid_i;
    // =========================================================
    // 2. Line Buffer (Stores one row of Horizontal Max values)
    // =========================================================
        /*
            Depth = Max Width / 2 (Stride is 2)
            For LeNet 28 width -> Depth 14.     For 1920 -> 960.
            Using Logic RAM (Distributed RAM or Block RAM inferred)
        */
    logic [WIDTH-1 : 0]         line_buffer     [DEPTH] ;
    logic [$clog2(DEPTH)-1 : 0] lb_addr                 ;

    assign  lb_addr = $clog2(DEPTH)'(x_cnt[31:1])   ;

    // =========================================================
    // 3. Logic Implementation
    // =========================================================
        // Compare Logic (Signed)

    function automatic logic signed [WIDTH-1 : 0] max(
        input   logic signed [WIDTH-1 : 0]   a,
        input   logic signed [WIDTH-1 : 0]   b
    );
        return (a > b) ? a : b;
    endfunction

    always_comb begin
        h_max = '0;// default value
        if(x_cnt[0]) begin
            h_max = max(pixel_even_col, data_i);//even col
        end
    end

    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin : output_logic
        if(!rst_async_n_i) begin : reset_logic
            data_o          <= '0;
            valid_o         <= 1'b0;
            even_row        <= 1'b0 ;
            pixel_even_col  <= '0;
            x_cnt           <= '0;
        end : reset_logic
        else begin : normal_operation
            if(valid_o && ready_i) valid_o <= 1'b0;

            if(fire) begin : fire_succeed_logic
                priority if(!x_cnt[0]) begin// even col(0,2...)
                    pixel_even_col <= data_i;
                end else begin// odd col(1,3...)
                    if(!even_row) begin// even row(0,2...)
                        line_buffer[lb_addr] <= h_max;
                    end else begin// odd row(1,3...)
                        valid_o <= 1'b1;
                        data_o <= max(h_max, line_buffer[lb_addr]);
                    end
                end

                if(x_cnt == feature_map_w_i-1'b1) begin
                    x_cnt <= '0;
                    even_row <= !even_row;
                end else
                    x_cnt <= x_cnt + 1'b1;

            end : fire_succeed_logic
        end : normal_operation
    end : output_logic
endmodule : pooling_core
