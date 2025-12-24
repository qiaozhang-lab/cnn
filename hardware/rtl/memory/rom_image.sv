/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-18 22:19:47
 * @LastEditTime: 2025-12-21 03:31:13
 * @LastEditors: Qiao Zhang
 * @Description: Simple ROM to hold Input Image (Read-Only from Hex)
 * @FilePath: /cnn/hardware/rtl/memory/rom_image.sv
 */
`timescale 1ns/1ps
`include "definitions.sv"

module rom_image #(
    parameter int       WIDTH = ROM_IMAGE_WIDTH,
    parameter int       DEPTH = ROM_IMAGE_DEPTH,
    parameter string    INIT_FILE = ROM_IMAGE_INIT_FILE
)(
    input  logic                    clk_i   ,
    input  logic                    rd_en   ,
    input  logic[ROM_IMAGE_DEPTH_W-1 : 0] addr_i  ,
    output logic[WIDTH-1 : 0]       rd_o
);

    var logic[WIDTH-1 : 0]  mems[DEPTH];
    // Initialize the ROM

    initial begin
        if(INIT_FILE == "")     $display("Warning, no initial files is specified");
            else begin
                $display("ROM_IMAGE: Loading model... \n from %s",INIT_FILE);
                $readmemh(INIT_FILE,mems);
            end
    end

    always_ff @( posedge clk_i) begin : main_logic
            if(rd_en) rd_o <= mems[addr_i];
    end : main_logic
endmodule : rom_image
