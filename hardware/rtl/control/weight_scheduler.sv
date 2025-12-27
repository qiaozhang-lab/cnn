/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-23 05:37:55
 * @LastEditTime: 2025-12-27 01:06:37
 * @LastEditors: Qiao Zhang
 * @Description: Weight Scheduler (West Controller) - Slave Mode.
 *              - Master-Slave Sync: follow the north-valid[0] signal of arr
 *              - Gap Reset: reset address to 0 and pre-read w0 when PE0 is idle
 *              - Skew: generate the stepped signals which are the valid and data of west ports
 * @FilePath: /cnn/hardware/rtl/control/weight_scheduler.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module weight_scheduler (
    input   logic                   clk_i           ,
    input   logic                   rst_async_n_i   ,

    // control signal from wrapper/arr
    input   logic                   enable_i        ,// once arr is busy, then pre-read rom
    input   logic                   sync_i          ,// high: PE0 is coming to running, low: PE0 is idle
    input   logic[3 : 0]            cfg_kernel_r_i  ,

    // SRAM(weights buffer) interface
    output  logic                                       wb_rd_en_o      ,
    output  logic[SRAM_ADDR_W-1 : 0]                    wb_addr_o       ,
    input   logic[K_CHANNELS-1 : 0] [INT_WIDTH-1 : 0]   wb_data_i       ,

    // systolic arrays west port
    output  logic[MATRIX_A_ROW-1 : 0]                   west_valid_o    ,
    output  logic[MATRIX_A_ROW-1 : 0][INT_WIDTH-1 : 0]  west_data_o
);

    logic[SRAM_ADDR_W-1 : 0]    curr_addr;
    logic[SRAM_ADDR_W-1 : 0]    next_addr_calc;

    assign  wb_rd_en_o = enable_i;

    always_comb begin
        if(curr_addr < (cfg_kernel_r_i*cfg_kernel_r_i)-1)
            next_addr_calc = curr_addr + 1'b1;
        else
            next_addr_calc = '0;
    end

    assign wb_addr_o = (sync_i) ? next_addr_calc : '0;

    // address generate logic
    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin : addr_gen_logic
        if(!rst_async_n_i) begin
            curr_addr <= '0;
        end else begin
            if(!enable_i)   begin
                curr_addr <= '0;
            end else if(sync_i) begin
                if(curr_addr < (cfg_kernel_r_i*cfg_kernel_r_i)-1)
                    curr_addr <= next_addr_calc;
                else
                    curr_addr <= '0;// we have calculated (cfg_kernel_r_i*cfg_kernel_r_i) pixel
            end else begin
                // PE0 is resting when the PE24-PE63 is calculating
                // back to address w0 make sure that we could get w0 when warps
                curr_addr <= '0;
            end
        end
    end : addr_gen_logic

    // skew valid and data
    genvar r;
    generate
        for(r=0; r<MATRIX_A_ROW; r++)   begin : gen_west_skew
            if(r == 0)  begin
                assign west_valid_o[r] = sync_i;
                assign west_data_o[r]  = wb_data_i[r];
            end else if(r == 1)begin
                logic                   delay_valid;
                logic [INT_WIDTH-1 : 0] delay_data;

                always_ff @( posedge clk_i, negedge rst_async_n_i ) begin
                    if(!rst_async_n_i) begin
                        delay_valid <= '0;
                        delay_data  <= '0;
                    end else if(enable_i) begin
                        delay_valid <= sync_i;
                        delay_data  <= (sync_i) ? wb_data_i[r] : INT_WIDTH'(0);
                    end
                end
                assign west_valid_o[r] = delay_valid;
                assign west_data_o[r]  = delay_data;
            end else begin : delay_chain
                logic[r-1 : 0]            delay_valid;
                logic[r-1 : 0][INT_WIDTH-1 : 0]  delay_data;

                always_ff @( posedge clk_i, negedge rst_async_n_i ) begin
                    if(!rst_async_n_i) begin
                        delay_valid <= '0;
                        delay_data  <= '{default: '0};
                    end else if(enable_i) begin
                        delay_valid <= {delay_valid[r-2 : 0], sync_i};
                        delay_data  <= {delay_data[r-2 : 0], (sync_i)? wb_data_i[r] : INT_WIDTH'(0)};
                    end
                end
                assign west_valid_o[r] = delay_valid[r-1];
                assign west_data_o[r]  = delay_data[r-1];
            end : delay_chain
        end : gen_west_skew
    endgenerate
endmodule : weight_scheduler
