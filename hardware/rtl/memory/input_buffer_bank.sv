/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-20 18:23:53
 * @LastEditTime: 2025-12-26 23:27:24
 * @LastEditors: Qiao Zhang
 * @Description: Bank of Column FIFOs (The Smart Line Buffer).
 *               - Distributes Serial SRAM data to N columns.
 *               - Provides N parallel outputs for Wavefront processing.
 * @FilePath: /cnn/hardware/rtl/memory/input_buffer_bank.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module input_buffer_bank #(
    // Hardware Physical Limit (default to 1920), we could limit it when simulating
    parameter int BANK_WIDTH = IB_BANK_W
)(
    input   logic                   clk_i           ,
    input   logic                   rst_async_n_i   ,

    // ===================================
    // 1. Control & Config
    // ===================================
    input   logic                   sa_done_i       ,// systolic arrays has calculated completely
    input   logic                   start_i         ,
        // LeNet: 28. HD: 1920.
    input   logic[31 : 0]           cfg_img_w_i     ,// Tells the write distributor where to wrap.
    input   logic[31 : 0]           cfg_img_h_i     ,
    input   logic[3 : 0]            cfg_kernel_r_i  ,// Logical Kernel Size: LeNet5 -> 5
    input   logic [2 : 0]                               input_ch_sel_i  ,

    // ===================================
    // 2. SRAM Interface (Master Mode)
    // ===================================
    output  logic [K_CHANNELS-1 : 0]                    sram_rd_en_o    ,
    output  logic [SRAM_ADDR_W-1 : 0]                   sram_rd_addr_o  ,
    input   logic [K_CHANNELS-1 : 0][INT_WIDTH-1 : 0]   sram_rd_data_i  ,

    // ===================================
    // 3. Parallel Read Interface
    // ===================================
        // Need individual pop signals for Wavefront updates
        // Col 0 pops at T0, Col 1 pops at T1...
    input   logic[BANK_WIDTH-1 : 0]                      pop_i          ,
    output  logic[BANK_WIDTH-1 : 0][INT_WIDTH-1 : 0]     data_out_o     ,

    // ===================================
    // 4. Control Handshake
    // ===================================
        // Wrapper tells IB: "I finished processing the current wavefront row"
    input   logic                                       pre_wave_done_i ,
        // IB tells Wrapper: "Data is ready, you can run"
    output  logic                                       ib_ready_o
);

    // =========================================================
    // Internal Signals & State Machine
    // =========================================================
    typedef enum logic [1:0] {
        IDLE        = 2'b00,
        PREFETCH    = 2'b01, // Fill initial K rows
        WAIT_TRIGGER= 2'b10, // Wait for SA to finish a row
        REFILL_ROW  = 2'b11  // Fill 1 single row
    } state_t;

    state_t state, next_state;

    // Counters
    logic [31:0]    col_cnt;      // 0 to img_w - 1
    logic [31:0]    total_rows_loaded;// global cnt for remember how many rows of image have loaded
    logic [3:0]     row_cnt;      // Track how many rows we loaded

    // Address Logic
    logic [SRAM_ADDR_W-1 : 0] curr_addr;
    logic [SRAM_ADDR_W-1 : 0] next_addr   ;

    logic internal_rd_req;

    // Write Distributor
    logic [$clog2(BANK_WIDTH)-1 : 0] wr_ptr;

    // SRAM Latency Handling
    // Because RAM has 1 cycle latency, Valid signal is delayed rd_en
    logic sram_valid_d1;

    // =========================================================
    // 1. Main Control FSM
    // =========================================================
    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin
        if(!rst_async_n_i)  state <= IDLE;
        else                state <= next_state;
    end

    always_comb begin : state_update_logic
        next_state = state;

        priority if(sa_done_i)  begin
            next_state = IDLE;
        end else begin
            case (state)
                IDLE        : if(start_i)    next_state = PREFETCH;
                PREFETCH    :   begin
                                // Load K_R rows (e.g., 5 rows).
                                // Condition: Row count reaches limit AND current col finishes
                                if((row_cnt == cfg_kernel_r_i) && (col_cnt == cfg_img_w_i-1))
                                    next_state = WAIT_TRIGGER;
                            end
                WAIT_TRIGGER:   begin
                                // Waiting for the Systolic Wrapper to say "I'm done with top row"
                                // Note: Only there is the rest of rows of image isn't loaded, then we go to
                                if(pre_wave_done_i) begin
                                    if(total_rows_loaded < cfg_img_h_i)
                                        next_state = REFILL_ROW;
                                    else
                                        next_state = WAIT_TRIGGER;
                                end
                            end
                REFILL_ROW  :   begin
                                // Load exactly 1 row
                                if(col_cnt == cfg_img_w_i-1)  next_state = WAIT_TRIGGER;
                            end
                default     : next_state = state;
            endcase
        end

    end : state_update_logic

    // =========================================================
    // 2. Address & Request Generation
    // =========================================================
    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin : addr_req_gen
        if(!rst_async_n_i) begin
            total_rows_loaded   <= '0;
            row_cnt             <= '0;
            col_cnt             <= '0;
            curr_addr           <= '0;
            next_addr           <= '0;
            internal_rd_req     <= 1'b0;
        end else begin
            internal_rd_req     <= 1'b0;

            case (state)
                IDLE                 : begin
                    col_cnt             <= '0;
                    row_cnt             <= '0;
                    curr_addr           <= '0;
                    next_addr           <= '0;
                    total_rows_loaded   <= '0;
                end
                PREFETCH, REFILL_ROW : begin
                            internal_rd_req <= 1'b1;
                            curr_addr       <= next_addr;
                            next_addr       <= next_addr + 1'b1;// advance global address
                            // advance column counter
                            if(col_cnt == cfg_img_w_i-1) begin
                                col_cnt <= '0;
                                total_rows_loaded <= total_rows_loaded + 1'b1;
                                // only increase row counter in prefetch stage for checking if K+1 row is full
                                if(state == PREFETCH) row_cnt <= row_cnt + 1'b1;
                            end else
                                col_cnt <= col_cnt + 1'b1;
                        end
                default            : begin
                            // Keep status
                        end
            endcase
        end
    end :addr_req_gen

    assign sram_rd_addr_o = curr_addr;

    // =========================================================
    // 3. SRAM Read Control (Bank Selection)
    // =========================================================
    always_comb begin : sram_read_logic
        sram_rd_en_o = '0;
        if(internal_rd_req) begin
            sram_rd_en_o[input_ch_sel_i] = 1'b1;
        end
    end : sram_read_logic



    // =========================================================
    // 4. Data Mux
    // =========================================================
    logic [INT_WIDTH-1 : 0] selected_pixel_data  ;

    assign  selected_pixel_data = sram_rd_data_i[input_ch_sel_i] ;

    // =========================================================
    // 3. Data Write (Handling ROM Latency)
    // =========================================================
    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin : write_input_buffer
        if(!rst_async_n_i) begin
            sram_valid_d1 <= 1'b0;
            wr_ptr       <= '0;
        end else begin
            sram_valid_d1 <= internal_rd_req; // Delay 1 cycle

            if (sram_valid_d1) begin
                // only rom data is valid, we move the pointer
                if (wr_ptr == $clog2(BANK_WIDTH)'(cfg_img_w_i - 1))// line wrap
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end else if ((state == IDLE) || (state == WAIT_TRIGGER)) begin
                wr_ptr <= '0;
            end
        end
    end : write_input_buffer

    // =========================================================
    // 4. Instantiate N FIFOs
    // =========================================================
    genvar i;
    generate
        for( i = 0; i<BANK_WIDTH ; i++) begin : gen_cols
            // Write Enable Logic: Only write if selected
            logic   push_en     ;
            assign  push_en = sram_valid_d1 && (32'(wr_ptr) == i);

            column_fifo #(
                .WIDTH(INT_WIDTH),
                .DEPTH(COLUMN_FIFO_DEPTH)
            ) u_fifo(
                .clk_i(clk_i),
                .rst_async_n_i(rst_async_n_i),

                .push_i(push_en),
                .data_i(selected_pixel_data),

                .pop_i(pop_i[i]),
                .shift_window_i(pre_wave_done_i),
                .data_o(data_out_o[i]),

                .full_o(),
                .empty_o()
            );
        end : gen_cols
    endgenerate

    // only ready when init fifo is finished or when we allow the systolic arrays start
    // Note: the calculation speed of systolic arrays is slower than SRAM/ROM fill the input buffer(REFILL_ROW)
    assign ib_ready_o = (state == WAIT_TRIGGER) || (state == REFILL_ROW);
endmodule : input_buffer_bank
