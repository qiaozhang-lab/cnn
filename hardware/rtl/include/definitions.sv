/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-18 22:21:47
 * @LastEditTime: 2025-12-19 00:05:30
 * @LastEditors: Qiao Zhang
 * @Description: Some important definitions which will be shared in different files
 * @FilePath: /cnn/hardware/rtl/include/definitions.sv
 */

`ifndef DEFINITIONS
    `define DEFINITIONS
    package definitions;

        // ==========================================================
        //  1. Global Parameters
        // ==========================================================
        parameter int INT_WIDTH = 8;

        // ==========================================================
        // 2. Local  Parameters
        // ==========================================================
            // A. ROM_IMAGE
        parameter int ROM_WIDTH         = INT_WIDTH;
        parameter int ROM_DEPTH         = IMG_W*IMG_H;
        parameter int ROM_WIDTH_W       = $clog2(ROM_WIDTH);
        parameter int ROM_DEPTH_W       = $clog2(ROM_DEPTH);
        parameter string ROM_INIT_FILE  = "";

            // B. Img2col_addr_gen(AGU)
        parameter int IMG_W             = 28        ;
        parameter int IMG_H             = 28        ;
        parameter int K_R               = 5         ; // the width of kernel
        parameter int K_S               = 5         ; // the depth of kernel

            // C. SRAM
        parameter int SRAM_DEPTH        = 65536     ;
        parameter int SRAM_ADDR_W       = $clog2(SRAM_DEPTH);
    endpackage
    import definitions::*;
`endif
