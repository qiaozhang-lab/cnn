/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-12 22:12:40
 * @LastEditTime: 2025-12-13 22:59:02
 * @LastEditors: Qiao Zhang
 * @Description: The package which defines some key definitions for the systolic arrays.
 * @FilePath: /systolic_arrays/rtl/definitions.sv
 */

`ifndef DEFINITIONS
    `define DEFINITIONS
    `timescale 1ns/1ps
    package definitions;
            // Mode 0: save area(just 1 adder for 1 pe --- blocking)
            // Mode 1: high performance(multi adder for 1 pe --- non-blocking, pipeline)
        parameter int MODE         = 0              ;

        parameter int MATRIX_A_ROW = 4              ;
        parameter int MATRIX_A_COL = 4              ;
        parameter int MATRIX_B_ROW = MATRIX_A_COL   ;
        parameter int MATRIX_B_COL = 4              ;
        parameter int DATA_WIDTH   = 8              ;
        parameter int ACC_WIDTH    = 32             ;

    endpackage

    import definitions::*;
`endif
