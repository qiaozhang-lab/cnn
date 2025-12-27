/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-13 17:51:49
 * @LastEditTime: 2025-12-23 08:11:20
 * @LastEditors: Qiao Zhang
 * @Description: Systolic Arrays top module
 *  - Instantiate pe.sv
 * @FilePath: /cnn/hardware/rtl/ip/systolic_arrays/systolic_top.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module systolic_top (
    // system inputs
    input   logic           clk_i           ,
    input   logic           rst_async_n_i   ,

    input   logic[MATRIX_B_COL-1 : 0]   pe_clear_col_i  ,// drive by result handler, clear by column

    // west direct interface
    input   logic[MATRIX_A_ROW-1 : 0]   west_valid_i    ,
    output  logic[MATRIX_A_ROW-1 : 0]   west_ready_o    ,
    input   logic[MATRIX_A_ROW-1 : 0] [DATA_WIDTH-1 : 0] west_data_i,

    // north direct interface
    input   logic[MATRIX_B_COL-1 : 0]   north_valid_i   ,
    output  logic[MATRIX_B_COL-1 : 0]   north_ready_o   ,
    input   logic[MATRIX_B_COL-1 : 0] [DATA_WIDTH-1 : 0] north_data_i,

    output  logic[ACC_WIDTH-1 : 0]      result_o[MATRIX_A_ROW][MATRIX_B_COL]
);

    // =================================================================
    //  Step 1: Declare Flattened Interface Arrays
    // =================================================================
        // generate iter variables in the systolic arrays in the row and column direction
    genvar rows, cols;
    localparam int H_COUNTS = MATRIX_A_ROW*(MATRIX_B_COL+1);
    localparam int V_COUNTS = (MATRIX_A_ROW+1)*MATRIX_B_COL;

        // Horizontal Links: transfer matrix A
    // stream_if h_links[MATRIX_A_ROW][MATRIX_A_COL+1](
    //     clk_i,
    //     rst_async_i
    // );
    // But: Multi dimensional arrays of module instances are not yet supported.
    // Please use single dimension for instance arrays.
    // So, we need to flatten it

    // Horizontal Links: transfer matrix A
    stream_if h_links[H_COUNTS](
        .clk(clk_i),
        .rst_async_n(rst_async_n_i)
    );
    // Vertical Links: transfer matrix B
    stream_if v_links[V_COUNTS](
        .clk(clk_i),
        .rst_async_n(rst_async_n_i)
    );

    // =================================================================
    //  Step 2: Boundary Drivers
    // =================================================================
        // A: West Inputs ->
        // h_links[rows][0] = h_links[rows*(MATRIX_A_COL+1)+0]
    generate
        for(rows=0; rows<MATRIX_A_ROW; rows++) begin : gen_west_drivers
            assign  h_links[rows*(MATRIX_B_COL + 1) + 0].valid = west_valid_i[rows];
            assign  h_links[rows*(MATRIX_B_COL + 1) + 0].data  = west_data_i[rows];
            assign  west_ready_o[rows] = h_links[rows*(MATRIX_B_COL + 1) + 0].ready ;
        end
    endgenerate
        // B: north inputs ->
        // v_links[0][cols] = v_links[0*(MATRIX_B_COL)+cols]
    generate
        for(cols=0; cols<MATRIX_B_COL; cols++) begin : gen_north_drivers
            assign v_links[cols].valid = north_valid_i[cols];
            assign v_links[cols].data  = north_data_i[cols];
            assign north_ready_o[cols] = v_links[cols].ready;
        end
    endgenerate

        // C: Terminators ->
        // avoid the ready of easternmost and southernmost to be float so that deadlock
    /*
    easternmost :
        h_links[rows][MATRIX_A_COL+1] = h_links[rows*(MATRIX_B_COL+1) + rows];
    southernmost :
        v_links[MATRIX_B_ROW+1][cols] = v_links[(MATRIX_B_ROW*MATRIX_B_COL + MATRIX_B_SOL];
    */
    generate
        for(rows=0; rows<MATRIX_A_ROW; rows++) begin : term_east
            assign h_links[rows*(MATRIX_B_COL+1)+MATRIX_B_COL].ready = 1'b1;
        end

        for(cols=0; cols<MATRIX_B_COL; cols++) begin : term_south
            assign v_links[MATRIX_A_ROW*MATRIX_B_COL+cols].ready = 1'b1;
        end
    endgenerate

    // =================================================================
    //  Step3 : Internal Clear Skew Logic
    // =================================================================
    logic clear_grid [MATRIX_A_ROW][MATRIX_B_COL];

    generate
        for (cols = 0; cols < MATRIX_B_COL; cols++) begin : gen_col_clear_skew
            assign clear_grid[0][cols] = pe_clear_col_i[cols];

            for (rows = 1; rows < MATRIX_A_ROW; rows++) begin : gen_row_delay
                always_ff @(posedge clk_i or negedge rst_async_n_i) begin
                    if (!rst_async_n_i)
                        clear_grid[rows][cols] <= 1'b0;
                    else
                        clear_grid[rows][cols] <= clear_grid[rows-1][cols];
                end
            end
        end
    endgenerate

    // =================================================================
    //  Step 4: PE Instantiate and Interconnect
    // =================================================================
    generate
        for(rows=0; rows<MATRIX_A_ROW; rows++) begin : gen_rows
            for(cols=0; cols<MATRIX_B_COL; cols++) begin : gen_cols

                // calculate the one dimension index
                localparam int idx_h_curr = rows*(MATRIX_B_COL+1) + cols;
                localparam int idx_h_next = rows*(MATRIX_B_COL+1) + cols + 1;
                localparam int idx_v_curr = rows*MATRIX_B_COL + cols;
                localparam int idx_v_next = (rows+1)*MATRIX_B_COL + cols;

                pe systolic_pe(
                    .clk_i(clk_i),
                    .rst_async_n_i(rst_async_n_i),

                    .clear_acc_i(clear_grid[rows][cols]),

                    .din_west(h_links[idx_h_curr]),
                    .din_north(v_links[idx_v_curr]),
                    .dout_east(h_links[idx_h_next]),
                    .dout_south(v_links[idx_v_next]),

                    .result_o(result_o[rows][cols])
                );
            end
        end
    endgenerate
endmodule : systolic_top
