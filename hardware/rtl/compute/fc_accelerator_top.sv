/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-31 03:53:45
 * @LastEditTime: 2026-01-01 20:22:17
 * @LastEditors: Qiao Zhang
 * @Description: FC Accelerator
 * @FilePath: /cnn/hardware/rtl/compute/fc_accelerator_top.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module fc_accelerator_top (
    input   logic                                       clk_i           ,
    input   logic                                       rst_async_n_i   ,

    // --- Control Interface ---
    input   logic                                       start_i         ,
    input   logic                                       calc_start_i    ,
    input   logic                                       load_from_sram_i,
    input   logic [SRAM_ADDR_W-1:0]                     load_sram_addr_i,
    input   logic [31:0]                                load_len_i      ,
    input   logic [31:0]                                calc_len_i      ,

    // Config
    input   logic                                       do_bias_i       ,
    input   logic                                       do_relu_i       ,
    input   logic                                       do_quant_i      ,
    input   logic [4:0]                                 quant_shift_i   ,
    input   logic [9:0]                                 fb_rd_base_i    ,
    input   logic [9:0]                                 fb_wr_base_i    ,
    output  logic                                       fb_load_done_o  ,
    output  logic                                       weight_req_o    ,
    input   logic                                       weight_ack_i    ,
    input   logic signed [7:0]                          weights_vector_i [100],
    input   logic signed [31:0]                         bias_vector_i    [100],
    output  logic [K_CHANNELS-1 : 0]                    sram_rd_en_o    ,
    output  logic [SRAM_ADDR_W-1 : 0]                   sram_rd_addr_o  ,
    input   logic [K_CHANNELS-1 : 0][INT_WIDTH-1 : 0]   sram_rd_data_i  ,
    output  logic                                       done_o
);

    // =========================================================
    // FSM States
    // =========================================================
    typedef enum logic [3:0] {
        IDLE,
        LOAD_L2,
        WAIT_LAST_WRITE_1,
        WAIT_LAST_WRITE_2,
        REQ_WEIGHTS,
        CALC_STREAM,
        WAIT_SA_1,
        WAIT_SA_2,
        WRITE_BACK,
        CHECK_LOOP,
        DONE
    } state_t;

    state_t state, next_state;

    // Latch signals
    logic [31:0]            latch_load_len;
    logic [31:0]            latch_calc_len;
    logic [9:0]             latch_fb_rd_base;
    logic [9:0]             latch_fb_wr_base;
    logic [31:0]            latch_current_batch_size;

    // Counters
    logic [31:0]            cnt_loaded;
    logic [31:0]            cnt_calc_cycle;
    logic [31:0]            cnt_calc_done;
    logic [31:0]            cnt_wb_local;
    logic [31:0]            current_batch_size;

    // Internal Control Signals
    logic                   buf_wr_en, buf_rd_en, buf_wb_done;
    logic [9:0]             buf_wr_addr, buf_rd_addr;
    logic [7:0]             buf_wr_data, buf_rd_data;
    logic                   sa_clear, sa_en;
    logic signed [31:0]     sa_results [100];
    logic                   sa_done;

    // Pipeline Registers
    logic                   sram_data_valid_d1, sram_data_valid_d2;
    logic [3:0]             sram_bank_sel_d1, sram_bank_sel_d2;
    logic [31:0]            cnt_loaded_d1, cnt_loaded_d2;

    logic signed [7:0]      weights_vector_d1 [100];
    logic signed [31:0]     bias_vector_d1    [100];
    logic signed [7:0]      weights_vector_d2 [100];
    logic signed [31:0]     bias_vector_d2    [100];

    logic                   sa_en_d1;

    // Address Gen
    int                     cnt_rd_pixel;
    int                     cnt_rd_logical_ch;
    int                     phys_bank_int;
    logic [31:0]            phys_offset;

    // =========================================================
    // 1. Instantiations
    // =========================================================
    fc_buffer u_local_mem (
        .clk_i          (clk_i)         ,
        .wr_en_i        (buf_wr_en)     ,
        .wr_addr_i      (buf_wr_addr)   ,
        .wr_data_i      (buf_wr_data)   ,
        .rd_en_i        (buf_rd_en)     ,
        .rd_addr_i      (buf_rd_addr)   ,
        .rd_data_o      (buf_rd_data)
    );

    fc_systolic_array #(100) u_sa (
        .clk_i                  (clk_i)             ,
        .rst_async_n_i          (rst_async_n_i)     ,
        .clear_acc_i            (sa_clear)          ,
        .calc_en_i              (sa_en_d1)          ,
        .pixel_broadcast_i      (buf_rd_data)       ,
        .weights_vector_i       (weights_vector_d2) ,
        .results_vector_o       (sa_results)
    );

    // =========================================================
    // 2. Post-Process
    // =========================================================
    function logic signed [7:0] post_process(
        input logic signed [31:0]   raw_acc,
        input logic                 do_bias,
        input logic signed [31:0]   bias,
        input logic                 do_relu,
        input logic                 do_quant,
        input logic [4:0]           quant_shift
);
        logic signed [31:0] val_biased, val_activated, val_shifted;
        val_biased    = (do_bias) ? (raw_acc + bias) : raw_acc;
        val_activated = (do_relu && (val_biased[31]==1'b1)) ? 32'd0 : val_biased;
        val_shifted   = (do_quant) ? val_activated >>> quant_shift : val_activated;

        if(val_shifted > 127)       return 8'd127;
        else if(val_shifted < -128) return -8'd128;
        else                        return val_shifted[7:0];
    endfunction

    // =========================================================
    // 3. FSM Update
    // =========================================================
    always_ff @(posedge clk_i or negedge rst_async_n_i) begin
        if(!rst_async_n_i)  state <= IDLE;
        else                state <= next_state;
    end

    always_comb begin : fsm_logic
        next_state = state;
        case(state)
            IDLE             : if(start_i) next_state = load_from_sram_i ? LOAD_L2 : REQ_WEIGHTS;
            LOAD_L2          : if(cnt_loaded == load_len_i) next_state = WAIT_LAST_WRITE_1;
            WAIT_LAST_WRITE_1: next_state = WAIT_LAST_WRITE_2;
            WAIT_LAST_WRITE_2: next_state = REQ_WEIGHTS;
            REQ_WEIGHTS      : if(weight_ack_i && calc_start_i) next_state = CALC_STREAM;
            CALC_STREAM      : if(sa_done) next_state = WAIT_SA_1;
            WAIT_SA_1        : next_state = WAIT_SA_2;
            WAIT_SA_2        : next_state = WRITE_BACK;
            WRITE_BACK       : if(cnt_wb_local == (latch_current_batch_size - 1)) next_state = CHECK_LOOP;
            CHECK_LOOP       : if(cnt_calc_done >= latch_calc_len) next_state = DONE;
                                else next_state = REQ_WEIGHTS;
            DONE             : next_state = IDLE;
            default          : next_state = IDLE;
        endcase
    end

    logic [31:0] next_batch_remaining;

    assign next_batch_remaining = calc_len_i - cnt_calc_done;

    // =========================================================
    // 4. Counters & Datapath
    // =========================================================
    always_ff @(posedge clk_i or negedge rst_async_n_i) begin
        if(!rst_async_n_i) begin
            cnt_loaded               <= '0;
            cnt_calc_cycle           <= '0;
            cnt_calc_done            <= '0;
            cnt_wb_local             <= '0;
            current_batch_size       <= '0;
            fb_load_done_o           <= 1'b0;
            sa_done                  <= 1'b0;
            buf_wb_done              <= 1'b0;
            done_o                   <= 1'b0;
            sa_en_d1                 <= '0;
            latch_load_len           <= '0;
            latch_calc_len           <= '0;
            latch_fb_rd_base         <= '0;
            latch_fb_wr_base         <= '0;
            latch_current_batch_size <= '0;
            for(int k=0; k<100; k++) begin
                weights_vector_d1[k] <= 0;
                bias_vector_d1[k]    <= 0;
                weights_vector_d2[k] <= 0;
                bias_vector_d2[k]    <= 0;
            end
        end else begin
            done_o <= 1'b0;

            for(int k=0; k<100; k++) begin
                weights_vector_d1[k] <= weights_vector_i[k];
                bias_vector_d1[k]    <= bias_vector_i[k];
                weights_vector_d2[k] <= weights_vector_d1[k];
                bias_vector_d2[k]    <= bias_vector_d1[k];
            end

            if (state == CALC_STREAM && !sa_done)
                sa_en_d1 <= 1;
            else
                sa_en_d1 <= 0;

            case(state)
                IDLE                : begin
                                        cnt_loaded          <= '0;
                                        cnt_calc_cycle      <= '0;
                                        cnt_calc_done       <= '0;
                                        cnt_wb_local        <= '0;
                                        fb_load_done_o      <= 1'b0;
                                    end
                LOAD_L2             : if(cnt_loaded < load_len_i)
                                        cnt_loaded <= cnt_loaded + 1;
                WAIT_LAST_WRITE_2   : fb_load_done_o <= 1'b1;

                REQ_WEIGHTS         : begin
                                        sa_done             <= 1'b0;
                                        buf_wb_done         <= 1'b0;
                                        cnt_calc_cycle      <= '0;
                                        cnt_wb_local        <= '0;

                                        // Latch parameters
                                        latch_load_len      <= load_len_i;
                                        latch_calc_len      <= calc_len_i;
                                        latch_fb_rd_base    <= fb_rd_base_i;
                                        latch_fb_wr_base    <= fb_wr_base_i;

                                        if(next_batch_remaining >= 100)
                                            current_batch_size <= 100;
                                        else
                                            current_batch_size <= next_batch_remaining;

                                        if(next_batch_remaining >= 100)
                                            latch_current_batch_size <= 100;
                                        else
                                            latch_current_batch_size <= next_batch_remaining;
                                    end

                CALC_STREAM         : begin
                                        if(cnt_calc_cycle == latch_load_len + 2) begin
                                            cnt_calc_cycle <= '0;
                                            sa_done <= 1'b1;
                                        end else begin
                                            cnt_calc_cycle <= cnt_calc_cycle + 1;
                                        end
                                    end

                WAIT_SA_2          : begin
                                        cnt_wb_local <= '0;
                                    end

                WRITE_BACK         : begin
                                        if(cnt_wb_local == latch_current_batch_size - 1) begin
                                            buf_wb_done   <= 1'b1;
                                            cnt_calc_done <= cnt_calc_done + latch_current_batch_size;
                                        end else begin
                                            cnt_wb_local  <= cnt_wb_local + 1;
                                        end
                                    end

                CHECK_LOOP          : begin
                                        cnt_wb_local <= '0;
                                    end

                DONE                : done_o <= 1'b1;
                default             : ;// do nothing
            endcase
        end
    end

    // =========================================================
    // 5. SRAM Read Logic
    // =========================================================
    assign phys_bank_int = cnt_rd_logical_ch % 6;
    assign phys_offset   = (cnt_rd_logical_ch / 6) * 25;

    always_ff @(posedge clk_i or negedge rst_async_n_i) begin
        if(!rst_async_n_i) begin
            sram_rd_addr_o      <= '0;
            sram_rd_en_o        <= '0;
            cnt_rd_pixel        <= 0;
            cnt_rd_logical_ch   <= 0;
            sram_data_valid_d1  <= 0;
            sram_bank_sel_d1    <= 0;
            cnt_loaded_d1       <= 0;
            sram_data_valid_d2  <= 0;
            sram_bank_sel_d2    <= 0;
            cnt_loaded_d2       <= 0;
        end else begin
            sram_data_valid_d1 <= (state == LOAD_L2);
            sram_bank_sel_d1   <= 4'(phys_bank_int);
            cnt_loaded_d1      <= cnt_loaded;
            sram_data_valid_d2 <= sram_data_valid_d1;
            sram_bank_sel_d2   <= sram_bank_sel_d1;
            cnt_loaded_d2      <= cnt_loaded_d1;

            if(state == LOAD_L2) begin
                if(cnt_rd_pixel == 24) begin
                    cnt_rd_pixel      <= 0;
                    cnt_rd_logical_ch <= cnt_rd_logical_ch + 1;
                end
                else
                    cnt_rd_pixel <= cnt_rd_pixel + 1;

                sram_rd_en_o                <= '0;
                sram_rd_en_o[phys_bank_int] <= 1'b1;

                sram_rd_addr_o <= SRAM_ADDR_W'(load_sram_addr_i + cnt_rd_pixel + phys_offset);
            end else begin
                sram_rd_en_o        <= '0;
                cnt_rd_pixel        <= 0;
                cnt_rd_logical_ch   <= 0;
            end
        end
    end

    // =========================================================
    // 6. Outputs Logic
    // =========================================================
    always_comb begin
        buf_wr_en        = 0;
        buf_wr_addr      = 0;
        buf_wr_data      = 0;
        buf_rd_en        = 0;
        buf_rd_addr      = 0;
        sa_clear         = 0;
        sa_en            = 0;
        weight_req_o     = 0;
        case(state)
            LOAD_L2, WAIT_LAST_WRITE_1, WAIT_LAST_WRITE_2: begin
                if(sram_data_valid_d2) begin
                    buf_wr_en   = 1;
                    buf_wr_addr = fb_wr_base_i + 10'(cnt_loaded_d2);
                    buf_wr_data = sram_rd_data_i[sram_bank_sel_d2];
                end
            end
            REQ_WEIGHTS: begin
                weight_req_o = 1; sa_clear = 1;
            end
            CALC_STREAM: begin
                if(!sa_done) begin
                    if (cnt_calc_cycle < latch_load_len) begin
                        buf_rd_en = 1;
                        buf_rd_addr = latch_fb_rd_base + 10'(cnt_calc_cycle);
                    end
                end
            end
            WRITE_BACK: begin
                buf_wr_en   = 1;
                buf_wr_addr = latch_fb_wr_base + 10'(cnt_calc_done + cnt_wb_local);
                buf_wr_data = post_process(
                                sa_results[cnt_wb_local]    ,
                                do_bias_i                   ,
                                bias_vector_d2[cnt_wb_local],
                                do_relu_i                   ,
                                do_quant_i                  ,
                                quant_shift_i
                                );
            end
            default: ;// do nothing
        endcase
    end
endmodule
