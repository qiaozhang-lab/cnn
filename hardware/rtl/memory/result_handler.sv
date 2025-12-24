`timescale 1ns/1ps
`include "definitions.sv"

module result_handler (
    input   logic           clk_i           ,
    input   logic           rst_async_n_i   ,

    // Monitor North Valid falling edge
    input   logic[MATRIX_B_COL-1 : 0]  sa_valid_monitor_i,
    input   logic[ACC_WIDTH-1 : 0]     sa_result_i[MATRIX_A_ROW][MATRIX_B_COL],

    // Output Clear Trigger (Per Column)
    output  logic[MATRIX_B_COL-1 : 0]  pe_clear_o,

    // Debug
    output  logic                      fifo_valid_o
);

    // =========================================================
    // 1. Edge Detection
    // =========================================================
    logic [MATRIX_B_COL-1 : 0] valid_d1;

    // Base Trigger Signal -> the end moments of Channel 0
    logic [MATRIX_B_COL-1 : 0] trigger_base;// delay col by col, depends on monitor the invalid

    always_ff @(posedge clk_i or negedge rst_async_n_i) begin
        if(!rst_async_n_i) begin
            valid_d1     <= '0;
            trigger_base <= '0;
            pe_clear_o   <= '0;
        end else begin
            valid_d1 <= sa_valid_monitor_i;

            for (int c = 0; c < MATRIX_B_COL; c++) begin
                // Falling Edge Detection: 1 -> 0, once a col is not valid, then the calculation of PE(0,x) is finished
                // Note: we will handle the row delay in the next context
                if (valid_d1[c] && !sa_valid_monitor_i[c]) begin
                    trigger_base[c] <= 1'b1;
                    pe_clear_o[c]   <= 1'b1; // Send Clear Pulse (Systolic Top will skew this internally)
                end else begin
                    trigger_base[c] <= 1'b0;
                    pe_clear_o[c]   <= 1'b0;
                end
            end
        end
    end

    assign fifo_valid_o = |trigger_base;

    // =========================================================
    // 2. Skewed Capture Logic
    // =========================================================
    // We need to create a delay chain as different Channel has different clear trigger signal
    // capture_trig[channel][column]
    logic [MATRIX_B_COL-1 : 0] capture_trig [MATRIX_A_ROW];

    // Channel 0 has no-delay, directly trigger_base
    assign capture_trig[0] = trigger_base;

    // Channel 1..5: delay row(channel) by row
    genvar r;
    generate
        for (r = 1; r < MATRIX_A_ROW; r++) begin : gen_capture_skew
            always_ff @(posedge clk_i or negedge rst_async_n_i) begin
                if (!rst_async_n_i)
                    capture_trig[r] <= '0;
                else
                    // delay a cycle for Ch[r-1] -> Ch[r]
                    capture_trig[r] <= capture_trig[r-1];
            end
        end : gen_capture_skew
    endgenerate

    // =========================================================
    // 3. Result Memory with Independent Pointers
    // =========================================================
    var logic [ACC_WIDTH-1 : 0] result_mems [K_CHANNELS][MAX_LINE_W];

    // different channels need independent write pointer:
    // because their ending moments are different so they need different write pointer
    logic [31:0] wr_ptrs [K_CHANNELS];

    always_ff @(posedge clk_i or negedge rst_async_n_i) begin : mem_write_logic
        if(!rst_async_n_i) begin
            result_mems <= '{default: '0};
            for(int k=0; k<K_CHANNELS; k++) wr_ptrs[k] <= '0;
        end else begin

            for (int k = 0; k < K_CHANNELS; k++) begin
                for (int c = 0; c < MATRIX_B_COL; c++) begin

                    // Check a (Channel, Col) whether has a trigger
                    if (capture_trig[k][c]) begin
                        // write and move to next col
                        result_mems[k][wr_ptrs[k]] <= sa_result_i[k][c];
                        wr_ptrs[k] <= wr_ptrs[k] + 1'b1;
                    end

                end
            end
        end
    end : mem_write_logic
endmodule
