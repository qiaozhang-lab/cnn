/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-18 23:27:57
 * @LastEditTime: 2025-12-19 21:37:09
 * @LastEditors: Qiao Zhang
 * @Description:  Im2Col Address Generator for Conv2D
 *               Generates sequence for Matrix B (Input Patch Stream)
 * @FilePath: /cnn/hardware/rtl/control/img2col_addr_gen.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module img2col_addr_gen(
    // system inputs
    input   logic                       clk_i           ,
    input   logic                       rst_async_n_i   ,

    // top model FSM interface
    input   logic[SRAM_ADDR_W-1 : 0]    base_addr_i     ,// the base address of current image which is controlled by top FSM
    // systolic arrays interface
    input   logic                       systolic_ready_i,
    input   logic                       start_i         ,// Start processing a whole image

    // SRAM interface
    output  logic                       valid_o         ,
    output  logic[SRAM_ADDR_W-1 : 0]    sram_rd_addr_o  ,
    output  logic                       last_out_o       // end of image
);

    // =============================================================
    // 1. Output Feature Map Dimensions
    // =============================================================
        // activate slip windows position coordinate(top left corner)
    localparam int OUT_W = IMG_W - K_R + 1;// 28-5+1=24
    localparam int OUT_H = IMG_H - K_S + 1;// 28-5+1=24

        // register
    logic[SRAM_ADDR_W-1 : 0]    curr_addr;
    logic[SRAM_ADDR_W-1 : 0]    win_base_addr;// the top left address of the current slip windows

    logic   active;// internal FSM state
    logic[3:0]  count_r, count_s;// max to 15 for kernel
    logic[7:0]  count_w, count_h;// max to 255 for image
    // =============================================================
    // 2. Counters (State Machine)
    // =============================================================

        /*
            We always keeps the window base address is the top left address of the current slip windows.
            For other pixel, we get there positions by add the 'S' and 'R'*IMG_W, which won't synthesize
            multiplier
        */
    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin : blockName
        if(!rst_async_n_i) begin : reset_logic
            count_w         <= '0;
            count_h         <= '0;
            count_r         <= '0;
            count_s         <= '0;
            active          <= 1'b0;
            win_base_addr   <= '0;
            curr_addr       <= '0;
            last_out_o      <= 1'b0;
        end : reset_logic
        else begin : normal_operation
            // Pulse Start Handling
            if (start_i) begin
                active         <= 1'b1;// monitor the pulse signal : start_i
                win_base_addr  <= base_addr_i;
                curr_addr      <= base_addr_i;
                count_r        <= '0;
                count_s        <= '0;
                count_w        <= '0;
                count_h        <= '0;
                last_out_o     <= 1'b0;
            end

            // FSM running
            if(systolic_ready_i && active) begin
                // pixel arrives the far right of current row -> skip to next column of current window -> count_s + 1
                // inter loop: kernel weight(s)
                if(32'(count_s) == K_S-1) begin
                    count_s <= '0;
                    // pixel arrives the bottom right of current windows -> window move to next window -> count_w + 1
                    // inter loop: kernel height(r)
                    if(32'(count_r) == K_R-1) begin
                        count_r <= '0;
                        // slip window arrives the far right -> slip window need to next col -> count_h + 1
                        // outer loop: window X
                        if(32'(count_w) == OUT_W-1) begin
                            count_w <= '0;
                            // slip window arrives the last window
                            // outer loop: window Y
                            if(32'(count_h) == OUT_H-1) begin// FSM done
                                count_h    <= '0;
                                last_out_o <= 1'b1;
                                active     <= 1'b0;
                            end
                            else begin : outer_loop_win_y
                                count_h         <= count_h + 1'b1;
                                win_base_addr   <= win_base_addr + K_S;
                                curr_addr       <= win_base_addr + K_S;
                            end : outer_loop_win_y
                        end
                        else begin : outer_loop_win_x
                            count_w         <= count_w + 1'b1;
                            win_base_addr   <= win_base_addr + 1'b1;
                            curr_addr       <= win_base_addr + 1'b1;
                        end : outer_loop_win_x
                    end
                    else begin : inter_loop_kernel_height
                        count_r     <= count_r + 1'b1;
                        curr_addr   <=  curr_addr + (IMG_W - K_S + 1);
                    end : inter_loop_kernel_height
                end
                else begin : inter_loop_kernel_weight
                    count_s     <= count_s + 1'b1   ;
                    curr_addr   <=  curr_addr + 1'b1;
                end : inter_loop_kernel_weight
            end


            // pulse signal last_out
            if(last_out_o) last_out_o <= 1'b0;
        end : normal_operation
    end
        // update the current address(curr_addr) due to we have arrive the last pixel of current slip windows
    assign  sram_rd_addr_o = curr_addr;
    assign  valid_o = active;
endmodule
