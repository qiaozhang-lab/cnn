/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-20 18:23:53
 * @LastEditTime: 2025-12-23 05:30:05
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

    input   logic                   sa_done_i       ,// systolic arrays has calculated completely
    // Tells the write distributor where to wrap.
    // LeNet: 28. HD: 1920.
    input   logic                   start_i         ,
    input   logic[31 : 0]           cfg_img_w_i     ,
    input   logic[31 : 0]           cfg_img_h_i     ,
    input   logic[3 : 0]            cfg_kernel_r_i  ,// Logical Kernel Size: LeNet5 -> 5

    // ===================================
    // 1. ROM/SRAM Interface (Master Mode)
    // ===================================
    output  logic[ROM_IMAGE_DEPTH_W-1 : 0]  rom_addr_o  ,
    output  logic                           rom_rd_en_o ,
        // Data returns from ROM (1 cycle latency expected)
    input   logic[INT_WIDTH-1 : 0]          rom_data_i  ,

    // ===================================
    // 2. Parallel Read Interface
    // ===================================
        // Need individual pop signals for Wavefront updates
        // Col 0 pops at T0, Col 1 pops at T1...
    input   logic[BANK_WIDTH-1 : 0]                      pop_i          ,
    output  logic[BANK_WIDTH-1 : 0][INT_WIDTH-1 : 0]     data_out_o     ,

    // ===================================
    // 3. Control Handshake
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
    logic [ROM_IMAGE_DEPTH_W-1 : 0] current_rom_addr;
    logic [ROM_IMAGE_DEPTH_W-1 : 0] next_rom_addr   ;

    // Write Distributor
    logic [$clog2(BANK_WIDTH)-1 : 0] wr_ptr;

    // ROM Latency Handling
    // Because ROM has 1 cycle latency, Valid signal is delayed rd_en
    logic rom_valid_d1;

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
            total_rows_loaded <= '0;
            row_cnt <= '0;
            col_cnt <= '0;
            current_rom_addr <= '0;
            next_rom_addr    <= '0;
            rom_rd_en_o <= 1'b0;
        end else begin
            rom_rd_en_o <= 1'b0;

            case (state)
                PREFETCH, REFILL_ROW : begin
                            rom_rd_en_o <= 1'b1;
                            current_rom_addr <= next_rom_addr;
                            // advance column counter
                            if(col_cnt == cfg_img_w_i-1) begin
                                col_cnt <= '0;
                                total_rows_loaded <= total_rows_loaded + 1'b1;
                                // only increase row counter in prefetch stage for checking if K+1 row is full
                                if(state == PREFETCH) row_cnt <= row_cnt + 1'b1;
                            end else
                                col_cnt <= col_cnt + 1'b1;

                            // advance global address
                            next_rom_addr <= next_rom_addr + 1'b1;
                        end
                default            : begin
                            if (state == IDLE) begin
                                col_cnt <= '0;
                                row_cnt <= '0;
                                current_rom_addr <= '0;
                                next_rom_addr <= '0;
                            end
                        end
            endcase
        end
    end :addr_req_gen

    assign rom_addr_o = current_rom_addr;

    // =========================================================
    // 3. Data Write (Handling ROM Latency)
    // =========================================================
    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin : write_input_buffer
        if(!rst_async_n_i) begin
            rom_valid_d1 <= 1'b0;
            wr_ptr       <= '0;
        end else begin
            rom_valid_d1 <= rom_rd_en_o; // Delay 1 cycle

            if (rom_valid_d1) begin
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
            assign  push_en = rom_valid_d1 && (32'(wr_ptr) == i);

            column_fifo #(
                .WIDTH(INT_WIDTH),
                .DEPTH(COLUMN_FIFO_DEPTH)
            ) u_fifo(
                .clk_i(clk_i),
                .rst_async_n_i(rst_async_n_i),

                .push_i(push_en),
                .data_i(rom_data_i),

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
