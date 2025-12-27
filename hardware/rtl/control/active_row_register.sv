/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-21 20:04:33
 * @LastEditTime: 2025-12-24 15:14:01
 * @LastEditors: Qiao Zhang
 * @Description: Active Row Register (ARR) & Wavefront Controller  - With Priming Logic.
 *               - Manages Wavefront Pointers for 2D Convolution.
 *               - Generates 'row_done_o' to trigger Input Buffer Window Shift.
 *               - Feeds skewed/aligned data to Systolic Array.
 * @FilePath: /cnn/hardware/rtl/wrapper/active_row_register.sv
 */

`timescale 1ns/1ps
`include "definitions.sv"

module active_row_register (
    input   logic                   clk_i           ,
    input   logic                   rst_async_n_i   ,

     // Control
    input   logic                   start_i             ,
    input   logic[PTR_WIDTH-1 : 0]  cfg_img_w_i         ,
    input   logic[3 : 0]            cfg_kernel_r_i      ,

    // handshake signal
    input   logic                   ib_ready_i          ,
    output  logic                   busy_o              ,
    output  logic                   row_done_o          ,// if high, trigger IB line wrap

    // IB interface
    output  logic[IB_BANK_W-1 : 0]                  ib_pop_o    ,
    input   logic[IB_BANK_W-1 : 0][INT_WIDTH-1 : 0] ib_data_i   ,

    // SA Interface
    output  logic[MATRIX_B_COL-1 : 0]                   north_valid_o   ,
    output  logic[MATRIX_B_COL-1 : 0][INT_WIDTH-1 : 0]  north_data_o
);

    // =========================================================
    // Internal Signals
    // =========================================================
    var logic        [INT_WIDTH-1 : 0]   arr[MAX_TILE_W];
    var logic signed [PTR_WIDTH-1 : 0]   ptr_wave[MAX_K_R];

    logic [3 : 0]   offset;

    // FSM
    typedef enum logic[1 : 0] {
        IDLE    =   2'b00   ,
        PRIME   =   2'b01   ,// Pre-load ARR
        RUNNING =   2'b10   ,
        DONE    =   2'b11
     } state_t;

    state_t    state, next_state;

    // =========================================================
    // 1. FSM Logic
    // =========================================================
    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin
        if(!rst_async_n_i) begin
            state <= IDLE;
        end else
            state <= next_state ;
    end

    always_comb begin : state_update
        next_state = state;

        unique case(state)
            IDLE    : if(start_i && ib_ready_i)    next_state = PRIME;
            PRIME   : next_state    = RUNNING;// Prime takes 1 cycle to latch data from IB to ARR
            RUNNING : begin
                        if(ptr_wave[cfg_kernel_r_i-1] > signed'(cfg_img_w_i + MATRIX_A_ROW))
                            next_state = DONE;
                    end
            DONE    : next_state = IDLE;
            default : next_state = IDLE;
        endcase
    end : state_update

    // Output Flags
    assign busy_o     = (state == RUNNING) || (state == PRIME); // Busy during Prime too
    assign row_done_o = (state == DONE);

    // =========================================================
    // 3. Pointer & Mux Control
    // =========================================================
    int signed  temp_init_ptr;
    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin : ptr_update_logic
        if(!rst_async_n_i) begin
            ptr_wave<= '{default: '0};
            offset  <= '0;
        end else begin : normal_operation
            unique case(state)
                IDLE    :   begin : idle_ptr_reset
                            temp_init_ptr   = '0;
                            offset <= '0;
                            // reset pre-wave pointer
                            for(int i=0; i<MAX_K_R; i++) begin
                                if(i < 32'(cfg_kernel_r_i)) begin
                                    // +signed'(1) is must otherwise the update will be late
                                    ptr_wave[i] <= -signed'(i * cfg_kernel_r_i) + signed'(1);
                                end else
                                    ptr_wave[i] <= '0;
                            end
                        end : idle_ptr_reset
                RUNNING :   begin
                            if(offset == cfg_kernel_r_i-1) offset <= '0;
                            else    offset <= offset + 1'b1;

                            // advance all the pre_wave pointer
                            for(int i=0; i<MAX_K_R; i++) begin
                                if(i < 32'(cfg_kernel_r_i)) begin
                                    ptr_wave[i] <= ptr_wave[i] + signed'(1);
                                end
                            end
                        end
                default :   begin
                            // PRIME and DONE, we don't move the mul_sel and ptr_wave
                        end
            endcase
        end : normal_operation
    end : ptr_update_logic

    // =========================================================
    // 4. ARR update: include PRIME and RUNNING
    // =========================================================
    always_ff @( posedge clk_i, negedge rst_async_n_i ) begin : arr_update_logic
        if(!rst_async_n_i) begin
            arr <= '{default: '0};
        end else begin : normal_operation
            ib_pop_o     <= '0;
            unique case(state)
                PRIME   :   begin
                            for(int i=0; i<MATRIX_B_COL; i++)   begin
                                ib_pop_o[i] <= 1'b1;
                                arr[i]  <= ib_data_i[i];
                            end
                        end
                RUNNING :   begin
                            for(int i=0; i<MAX_K_R; i++) begin
                                // we update all the data which is pointed by the number of cfg_kernel_r_i
                                if(i < 32'(cfg_kernel_r_i)) begin
                                    if(ptr_wave[i] >= signed'(0) && ptr_wave[i] < signed'(cfg_img_w_i)) begin
                                        logic do_update;
                                        if (i == 0) do_update = (ptr_wave[i] >= signed'(MAX_TILE_W)); // Only update if > 64 (HD)
                                        else        do_update = 1'b1; // P1..P4 always replace old rows

                                        if(do_update)   begin
                                            ib_pop_o[ptr_wave[i]] <= 1'b1;
                                            arr[ptr_wave[i]%MAX_TILE_W]      <= ib_data_i[ptr_wave[i]];
                                        end
                                    end



                                end
                            end
                        end
                default : begin
                            // in IDLE and DONE state, we don't do anything
                        end
            endcase
        end : normal_operation
    end : arr_update_logic

    // =========================================================
    // 5. ARR output: we need to use the generate logic
    // =========================================================
    genvar  c;
    generate
        for(c=0; c<MATRIX_B_COL; c++) begin : gen_col_mux
            logic signed [PTR_WIDTH-1:0] dist_p0;// the distance of between ptr_wave[0] and current column
            logic signed [PTR_WIDTH-1:0] effective_time; // a PEx running time when it's woke up(valid)
            logic signed [PTR_WIDTH-1:0] logical_col_idx;// the no-wrapping PEx column if we have a infinite PE arrays

            logic [PTR_WIDTH-1 : 0] output_width    ;// the OUT_W of current picture

            // Flag: check the selected col whether is legal:
            // like cfg_img_w_i=98, then PE94(=PE63+29) is only PE94-98 AND we don't allow PE95
            logic is_col_legal;
            // Due to PRIME: we must make sure the col has read before rewrite
            // Note: a col must rewrite right away after it's read
            logic has_read;
            logic is_in_window;// the active cols which is when the PEx woke up

            logic [5:0] arr_idx;// a index which PEx should select in different time

            assign output_width = cfg_img_w_i - 32'(cfg_kernel_r_i) + 1;

            always_comb begin
                if(state == RUNNING)  begin
                    // 1. calculate the distance of between ptr_wave[0] and current col
                    dist_p0 = ptr_wave[0] - signed'(c);

                    // 2. only P0 pass away this col, then this PE col is valid.
                    // Notice: we reset P0 is 1, therefore the dist_p0 must >= 1 rather than 0
                    has_read = (dist_p0 >= 1);

                    // 3. Calculate the local running time of PEx
                    // (dist_p0 - 1) is how many cycle when a col is valid(P0 is reset 1)
                    // &63 handle wrapping
                    effective_time = (dist_p0 - 1) & (MATRIX_B_COL-1);

                    // 4. Check a cols has running how many cycle
                    // for a Kernel_Size=5, it just could running 25(5*5) cycle
                    is_in_window = (effective_time < (cfg_kernel_r_i * cfg_kernel_r_i));

                    logical_col_idx = (ptr_wave[0] - 1) - signed'(effective_time);

                    is_col_legal = (logical_col_idx < output_width);

                    if (has_read && is_in_window && is_col_legal) begin
                        north_valid_o[c] = 1'b1;

                        // (effective_time % cfg_kernel_r_i) -> make sure a loop: 0...4
                        // c+(effective_time % cfg_kernel_r_i) -> make sure the PEx get different col in a kernel windows
                        // (c + (effective_time % cfg_kernel_r_i)) % MAX_TILE_W -> make sure a wrap happens: 63+1=>0
                        arr_idx = (c + (effective_time % cfg_kernel_r_i)) % MAX_TILE_W;// get the arr index even time running

                        north_data_o[c] = arr[arr_idx];
                    end
                    else begin
                        north_valid_o[c] = 1'b0;
                        north_data_o[c]  = '0;
                    end
                end
                else begin
                    north_valid_o[c] = 1'b0;
                    north_data_o[c]  = '0;
                end
            end
        end
    endgenerate
endmodule : active_row_register
