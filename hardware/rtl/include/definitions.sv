/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-18 22:21:47
 * @LastEditTime: 2025-12-24 16:18:41
 * @LastEditors: Qiao Zhang
 * @Description: Some important definitions which will be shared in different files
 * @FilePath: /cnn/hardware/rtl/include/definitions.sv
 */

`ifndef DEFINITIONS
    `define DEFINITIONS
    `timescale 1ns/1ps
    package definitions;

        // ==========================================================
        //  1.  Global Hardware Specs (Synthesized Constants)
        // ==========================================================
        parameter int INT_WIDTH         = 8;

            // Max supported Kernel Size (e.g. 7x7), determines Pointer Pool size
        parameter int MAX_K_R           = 7;

            // Line Buffer Depth: Supports full HD width
        parameter int MAX_LINE_W        = 1920;

            /*
                The Physical Width of the Systolic Array / ARR
                This is the "Modulo" basis for Circular Buffering.
                Even if Image is 1920 wide, we map it to these 64 columns.
            */
        parameter int MAX_TILE_W        = 64;

        // ==========================================================
        // 2. Model Default Parameters (Can be overridden by Software Config)
        // ==========================================================

        parameter int K_CHANNELS        = 6;

            // A. Logical width for the current model (LeNet)
        parameter int IMG_W             = 28        ;
        parameter int IMG_H             = 28        ;
        parameter int K_R               =  5        ; // the width of kernel
        parameter int K_S               =  5        ; // the depth of kernel
        parameter int OUT_W             = IMG_W - K_S + 1;// 24
        parameter int OUT_H             = IMG_H - K_R + 1;// 24
            // B. ROM_IMAGE
        parameter int       ROM_IMAGE_WIDTH      = INT_WIDTH;
        parameter int       ROM_IMAGE_DEPTH      = IMG_W*IMG_H;
        parameter int       ROM_IMAGE_WIDTH_W    = $clog2(ROM_IMAGE_WIDTH);
        parameter int       ROM_IMAGE_DEPTH_W    = $clog2(ROM_IMAGE_DEPTH);
        parameter string    ROM_IMAGE_INIT_FILE  = "../rtl/init_files/input_image.hex";

            // C. SRAM (Global Memory)
        parameter int SRAM_DEPTH        = 65536     ;
        parameter int SRAM_ADDR_W       = $clog2(SRAM_DEPTH);

            // D. ROM_WEIGHT
        parameter int       ROM_WEIGHTS_WIDTH     = INT_WIDTH                ;
        parameter int       ROM_WEIGHTS_DEPTH     = K_R * K_S                ;// 5*5=25
        parameter int       ROM_WEIGHTS_WIDTH_W   = $clog2(ROM_WEIGHTS_WIDTH);
        parameter int       ROM_WEIGHTS_DEPTH_W   = $clog2(ROM_WEIGHTS_DEPTH);
        parameter string    ROM_WEIGHTS_INIT_FILE = "../rtl/init_files/conv1_weights.hex";

            // E. Systolic Arrays IP
                // Mode 0: save area(just 1 adder for 1 pe --- blocking)
                // Mode 1: high performance(multi adder for 1 pe --- non-blocking, pipeline)
        parameter int MODE         = 0              ;

        parameter int MATRIX_A_ROW = K_CHANNELS     ;
        parameter int MATRIX_A_COL = K_R * K_S      ;
        parameter int MATRIX_B_ROW = MATRIX_A_COL   ;
                // NOTE: Systolic Array Columns.
                // If MAX_TILE_W (64) > MATRIX_B_COL (16), the Wrapper manages the mapping.
        parameter int MATRIX_B_COL = 64             ;
        parameter int DATA_WIDTH   = INT_WIDTH      ;
        parameter int ACC_WIDTH    = 32             ;

            // F. column_fifo
        parameter int COLUMN_FIFO_DEPTH = 8         ;// Enough for 5x5 or 7x7

            // G. Input_buffer_bank
                // Instantiates enough FIFOs to hold a FULL HD Line
        parameter int IB_BANK_W         = MAX_LINE_W;

            // H. Active Row Register
        parameter int PTR_WIDTH         = 32;  // the pre-wave pointer width
            // I. ROM Bias
        parameter int ROM_BIAS_DEPTH    = K_CHANNELS;// 6
        parameter string ROM_BIAS_INIT_FILE = "../rtl/init_files/conv1_bias.hex";
    endpackage
    import definitions::*;
`endif
