/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-29
 * @Description: Partial Sum Accumulator - Fixed Output Synchronization.
 *               - Data Output: Registered (1 cycle latency).
 *               - Valid Output: Registered (1 cycle latency) to match Data.
 *               - Internal Skew: Matches Systolic Wavefront.
 */

`timescale 1ns/1ps
`include "definitions.sv"

module partial_sum_accumulator #(
    parameter int MEM_DEPTH = 256
)(
    input   logic               clk_i           ,
    input   logic               rst_async_n_i   ,
    input   logic               start_i         ,
    input   logic               is_first_pass_i ,
    input   logic               is_last_pass_i  ,

    input   logic[MATRIX_B_COL-1 : 0]   sa_valid_monitor_i,
    input   logic[ACC_WIDTH-1 : 0]      sa_result_i[MATRIX_A_ROW][MATRIX_B_COL],

    output  logic[ACC_WIDTH-1 : 0]      accumulated_result_o[MATRIX_A_ROW][MATRIX_B_COL],
    output  logic[MATRIX_B_COL-1 : 0]   accumulated_valid_o,
    output  logic[MATRIX_B_COL-1 : 0]   pe_clear_o
);

    // Storage
    logic signed [ACC_WIDTH-1 : 0] psum_mem [MATRIX_A_ROW][MATRIX_B_COL][MEM_DEPTH];

    // --- 1. Base Trigger & PE Clear ---
    logic [MATRIX_B_COL-1 : 0] valid_d1;
    logic [MATRIX_B_COL-1 : 0] base_trigger;

    always_ff @(posedge clk_i or negedge rst_async_n_i) begin
        if(!rst_async_n_i) begin
            valid_d1     <= '0;
            base_trigger <= '0;
            pe_clear_o   <= '0;
        end else begin
            if (start_i) begin
                 valid_d1     <= '0;
                 base_trigger <= '0;
                 pe_clear_o   <= '0;
            end else begin
                valid_d1 <= sa_valid_monitor_i;
                for(int c=0; c<MATRIX_B_COL; c++) begin
                    // 下降沿检测：窗口结束
                    if (valid_d1[c] && !sa_valid_monitor_i[c]) begin
                        base_trigger[c] <= 1'b1;
                        // 立即发出清零，假设 SA 内部会处理行间延迟
                        pe_clear_o[c]   <= 1'b1;
                    end else begin
                        base_trigger[c] <= 1'b0;
                        pe_clear_o[c]   <= 1'b0;
                    end
                end
            end
        end
    end

    // --- 2. Valid Output Synchronization (关键修复) ---
    // 数据输出是寄存器的，Valid 也必须是寄存器的，以保持相位一致
    // 只有在 Last Pass 才输出 Valid
    always_ff @(posedge clk_i or negedge rst_async_n_i) begin
        if(!rst_async_n_i) accumulated_valid_o <= '0;
        else begin
            if (is_last_pass_i)
                accumulated_valid_o <= base_trigger; // Delay 1 cycle to match Data
            else
                accumulated_valid_o <= '0;
        end
    end

    // --- 3. Internal Skew & Pointers ---
    logic [MATRIX_B_COL-1 : 0] row_triggers [MATRIX_A_ROW];
    assign row_triggers[0] = base_trigger;

    generate
        for (genvar r = 1; r < MATRIX_A_ROW; r++) begin : gen_row_skew
            always_ff @(posedge clk_i or negedge rst_async_n_i) begin
                if (!rst_async_n_i) row_triggers[r] <= '0;
                else                row_triggers[r] <= row_triggers[r-1];
            end
        end
    endgenerate

    // Pointers
    logic [$clog2(MEM_DEPTH)-1 : 0] base_ptrs [MATRIX_B_COL];
    logic [$clog2(MEM_DEPTH)-1 : 0] skewed_ptrs [MATRIX_A_ROW][MATRIX_B_COL];

    always_ff @(posedge clk_i or negedge rst_async_n_i) begin
        if(!rst_async_n_i) begin
            for(int c=0; c<MATRIX_B_COL; c++) base_ptrs[c] <= '0;
        end else if(start_i) begin
            for(int c=0; c<MATRIX_B_COL; c++) base_ptrs[c] <= '0;
        end else begin
            for(int c=0; c<MATRIX_B_COL; c++) begin
                if(base_trigger[c]) base_ptrs[c] <= base_ptrs[c] + 1'b1;
            end
        end
    end

    always_comb begin
        for(int c=0; c<MATRIX_B_COL; c++) skewed_ptrs[0][c] = base_ptrs[c];
    end

    generate
        for(genvar k=1; k<MATRIX_A_ROW; k++) begin : gen_ptr_skew
            for(genvar  c=0; c<MATRIX_B_COL; c++) begin : gen_ptr_col
                always_ff @(posedge clk_i) skewed_ptrs[k][c] <= skewed_ptrs[k-1][c];
            end
        end
    endgenerate

    // --- 4. Processing Logic ---
    generate
        for (genvar r = 0; r < MATRIX_A_ROW; r++) begin : gen_proc_rows
            for(genvar c=0; c<MATRIX_B_COL; c++) begin : gen_proc_cols
                always_ff @(posedge clk_i) begin
                    if (row_triggers[r][c]) begin
                        logic [$clog2(MEM_DEPTH)-1 : 0] my_ptr;
                        logic signed [ACC_WIDTH-1:0] curr_val;
                        logic signed [ACC_WIDTH-1:0] old_val;

                        my_ptr = skewed_ptrs[r][c];

                        curr_val = $signed(sa_result_i[r][c]);

                        if (is_first_pass_i) old_val = 0;
                        else                 old_val = psum_mem[r][c][my_ptr];

                        // 输出寄存器更新 (Latency = 1 relative to trigger)
                        if (is_last_pass_i) accumulated_result_o[r][c] <= old_val + curr_val;
                        else                psum_mem[r][c][my_ptr]     <= old_val + curr_val;
                    end
                end
            end
        end
    endgenerate

endmodule : partial_sum_accumulator
