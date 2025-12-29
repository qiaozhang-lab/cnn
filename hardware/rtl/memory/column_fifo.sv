/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-20 17:50:54
 * @LastEditTime: 2025-12-28 22:23:24
 * @LastEditors: Qiao Zhang
 * @Description: Smart Column Memory (Circular Buffer).
 *               - Supports Non-Destructive Read (Lookahead) for Convolution Reuse.
 *               - Supports Window Shifting (Base Pointer Update).
 * @FilePath: /cnn/hardware/rtl/memory/column_fifo.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module column_fifo #(
    parameter int WIDTH = INT_WIDTH,
    parameter int DEPTH = COLUMN_FIFO_DEPTH
)(
    input   logic               clk_i           ,
    input   logic               rst_async_n_i   ,
    input   logic               flush_i         ,

    // write interface form SRAM
    input   logic               push_i          ,
    input   logic[WIDTH-1 : 0]  data_i          ,

    // read interface to systolic arrays(SA Wavefront)
    input   logic               pop_i           ,// "Get next row in current window"
    input   logic               shift_window_i  ,// "Window moves down 1 row" (Reuse logic)
    output  logic[WIDTH-1 : 0]  data_o          ,// Always shows the 'Top' pixel

    // status
    output  logic               full_o          ,// Physically full
    output  logic               empty_o          // Physically full
);

    // internal memory
    var  logic[WIDTH-1 : 0] mems [DEPTH]    ;

    logic [$clog2(DEPTH) : 0]    wr_ptr  ;
    // base_ptr: The absolute top row of the current sliding window
    logic [$clog2(DEPTH) : 0]    base_ptr;
    // lookahead_ptr: The temporary pointer for the current wavefront access
    logic [$clog2(DEPTH) : 0]    lookahead_ptr;

    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin : blockName
        priority if(!rst_async_n_i) begin : reset_logic
            wr_ptr          <= '0;
            base_ptr        <= '0;
            lookahead_ptr   <= '0;
            mems            <= '{default: '0};
        end : reset_logic
        else if(flush_i) begin
            wr_ptr          <= '0;
            base_ptr        <= '0;
            lookahead_ptr   <= '0;
            mems            <= '{default: '0};
        end
        else begin
            // 1. Write Logic
            if(push_i & !full_o) begin
                mems[wr_ptr[$clog2(DEPTH)-1 : 0]] <= data_i;
                wr_ptr                            <= wr_ptr + 1'b1;
            end
            // 2. Window Shift Logic (Line Done)
            // When one output row is finished, we discard the top row (base_ptr++)
            // and reset the lookahead pointer to the NEW base.
            if(shift_window_i) begin
                base_ptr      <= base_ptr + 1'b1;
                lookahead_ptr <= base_ptr + 1'b1; // Reset to New Base
            end
            // 3. Read Logic (Wavefront Access)
            // When ARR requests data, we give current lookahead and increment it
            else if(pop_i) begin
                lookahead_ptr <= lookahead_ptr + 1'b1;
            end
        end
    end

    assign data_o  = mems[lookahead_ptr[$clog2(DEPTH)-1 : 0]];
    assign empty_o = (base_ptr == wr_ptr);
    assign full_o  = (base_ptr[$clog2(DEPTH)] != wr_ptr[$clog2(DEPTH)]) &&
                        (base_ptr[$clog2(DEPTH)-1 : 0] == wr_ptr[$clog2(DEPTH)-1 : 0]);
endmodule : column_fifo
