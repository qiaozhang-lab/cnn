/**
 * @Author: Qiao Zhang
 * @Date: 2025-12-31 12:19:54
 * @LastEditTime: 2026-01-01 20:50:16
 * @LastEditors: Qiao Zhang
 * @Description: System Testbench for LeNet-5.
 *               - Includes Full flow FC1/FC2/FC3 verification.
 * @FilePath: /cnn/hardware/sim/tb_lenet5_top.sv
 */


`timescale 1ns/1ps
`include "definitions.sv"

module tb_lenet5_top;

parameter int       CLK_PERIOD = 10;
parameter int       ADDR_IMG_IN = 32'h0000;
parameter int       ADDR_L2_OUT = 32'h0800;

    logic [63:0]    dram_conv2_weights [0:4095];
    logic [31:0]    dram_conv2_bias    [0:63];
    int             ptr_w_conv2, ptr_b_conv2;

    logic           clk_i               ;
    logic           rst_async_n_i       ;
    logic           start_i             ;
    logic           busy_o              ;
    logic           done_o              ;
    logic           host_weight_loaded  ;

    logic [1:0]                     loader_sel  ;
    logic                           loader_wen  ;
    logic [31:0]                    loader_addr ;
    logic [K_CHANNELS-1:0][31:0]    loader_data ;

    lenet5_top u_dut (
        .clk_i                  (clk_i)             ,
        .rst_async_n_i          (rst_async_n_i)     ,
        .host_start_i           (start_i)           ,
        .host_weight_loaded_i   (host_weight_loaded),
        .accelerator_busy_o     (busy_o)            ,
        .accelerator_done_o     (done_o)            ,
        .loader_target_sel_i    (loader_sel)        ,
        .loader_wr_en_i         (loader_wen)        ,
        .loader_wr_addr_i       (loader_addr)       ,
        .loader_wr_data_i       (loader_data)       ,

        // keep these port 0 for test
        .cfg_img_w_i           ('0)                 ,
        .cfg_img_h_i           ('0)                 ,
        .cfg_kernel_r_i        ('0)                 ,
        .cfg_input_ch_sel_i    ('0)                 ,
        .cfg_do_pool_i         ('0)                 ,
        .cfg_has_bias_i        ('0)                 ,
        .cfg_do_relu_i         ('0)                 ,
        .cfg_quant_shift_i     ('0)                 ,
        .cfg_read_base_addr_i  ('0)                 ,
        .cfg_write_base_addr_i ('0)
    );

    // Verification Data
    logic signed [7:0]          tb_fc1_weights [120][400];
    logic signed [31:0]         tb_fc1_bias [120];
    logic signed [7:0]          tb_fc1_input [400];

    logic signed [7:0]          tb_fc2_weights [84][120];
    logic signed [31:0]         tb_fc2_bias [84];
    logic signed [7:0]          tb_fc2_input [120];

    logic signed [7:0]          tb_fc3_weights [10][84];
    logic signed [31:0]         tb_fc3_bias [10];
    logic signed [7:0]          tb_fc3_input [84];

    logic signed [7:0]          tb_shadow_drive_weights [100];
    logic signed [31:0]         tb_shadow_drive_bias    [100];

    logic [7:0]                 temp_fc1_weights_linear [0 : 120*400 - 1];
    logic [31:0]                temp_fc1_bias_linear    [0 : 120 - 1];
    logic [7:0]                 temp_fc2_weights_linear [0 : 84*120 - 1];
    logic [31:0]                temp_fc2_bias_linear    [0 : 84 - 1];
    logic [7:0]                 temp_fc3_weights_linear [0 : 10*84 - 1];
    logic [31:0]                temp_fc3_bias_linear    [0 : 10 - 1];

    generate
        genvar g;
        for(g=0; g<100; g++) begin : force_map_blk
            initial begin
                force u_dut.fc_weights_vector[g] = tb_shadow_drive_weights[g];
                force u_dut.fc_bias_vector[g]    = tb_shadow_drive_bias[g];
            end
        end
    endgenerate

    initial begin
        clk_i = 0; forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end

    initial begin
        rst_async_n_i           = 0;
        start_i                 = 0;
        host_weight_loaded      = 0;
        loader_wen              = 0;
        ptr_w_conv2             = 0;
        ptr_b_conv2             = 0;

        for(int k=0; k<100; k++) begin
            tb_shadow_drive_weights[k]  = 0;
            tb_shadow_drive_bias[k]     = 0;
        end
        force u_dut.fc_weight_ack = 0;

        load_all_fc_data();

        $readmemh("../rtl/init_files/conv2_weights.hex", dram_conv2_weights);
        $readmemh("../rtl/init_files/conv2_bias.hex",    dram_conv2_bias);

        $display("\n========================================================");
        $display("[TB] LeNet-5 Integrated System Simulation Start");
        $display("========================================================");

        #(CLK_PERIOD * 10);
        rst_async_n_i = 1;
        #(CLK_PERIOD * 5);

        $display("[TB] Phase 1: Loading Layer 1 Data...");

        load_image_to_sram("../rtl/init_files/input_image.hex");

        load_weights_l1("../rtl/init_files/conv1_weights.hex");

        load_bias_l1("../rtl/init_files/conv1_bias.hex");

        $display("[TB] Layer 1 Data Ready. Starting Accelerator...");

        @(negedge clk_i);
        start_i = 1;
        @(negedge clk_i);
        start_i = 0;

        while (!u_dut.conv_done) begin
            // 1. Wait for ANY change
            wait (u_dut.u_ctrl.req_load_weight_o || u_dut.conv_done);

            // 2. Small delay to allow signals to settle (Anti-Glitch)
            #1;

            if (done_o) break;

            if (u_dut.u_ctrl.req_load_weight_o) begin
                logic [3:0] layer_id;
                layer_id = u_dut.u_ctrl.layer_id_o;

                // Safety check: if X, wait for clock edge
                if ($isunknown(layer_id)) begin
                    @(negedge clk_i);
                    layer_id = u_dut.u_ctrl.layer_id_o;
                end

                if (!$isunknown(layer_id)) begin
                    $display("\n[TB] IRQ: Load Request for Layer ID %0d (Time=%0t)", layer_id, $time);

                    if (layer_id >= 2 && layer_id <= 4) begin
                        dma_transfer_weights(150);
                        dma_transfer_bias(1);
                    end

                    // Handshake
                    @(negedge clk_i); host_weight_loaded = 1;

                    // Wait for request to drop
                    wait (!u_dut.u_ctrl.req_load_weight_o);

                    @(negedge clk_i); host_weight_loaded = 0;
                end
            end
        end

        $display("\n[TB] Conv Acceleration Done!");

        // ---------------------------------------------------------
        // Phase 2: Verify LOAD_SRAM
        // ---------------------------------------------------------
        $display("[TB] Monitoring FC Controller Status...");

        wait (u_dut.u_fc_top.fb_load_done_o == 1);

        $display("[TB] FC Buffer Load Complete! Verifying Load Phase...");

        #(CLK_PERIOD * 2);

        verify_fc_load_data();

        // ---------------------------------------------------------
        // Phase 3: FC1 Calculation
        // ---------------------------------------------------------
        $display("\n[TB] --- Starting FC1 Calculation (120 Outputs) ---");

        feed_fc_weights_generic(1, 0, 100, 400);
        feed_fc_weights_generic(1, 100, 20, 400);

        $display("[TB] Waiting for FC1 Core Done...");

        wait (u_dut.fc_core_done == 1);

        @(negedge clk_i);

        $display("[TB] Verifying FC1 Results & Capturing FC2 Input...");

        verify_fc1_results_and_capture();

        // ---------------------------------------------------------
        // Phase 4: FC2 Calculation
        // ---------------------------------------------------------
        $display("\n[TB] --- Starting FC2 Calculation (84 Outputs) ---");

        feed_fc_weights_generic(2, 0, 84, 120);

        $display("[TB] Waiting for FC2 Core Done...");

        wait (u_dut.fc_core_done == 1);

        @(negedge clk_i);

        $display("[TB] Verifying FC2 Results & Capturing FC3 Input...");

        verify_fc2_results_and_capture();

        // ---------------------------------------------------------
        // Phase 5: FC3 Calculation
        // ---------------------------------------------------------
        $display("\n[TB] --- Starting FC3 Calculation (10 Outputs) ---");

        feed_fc_weights_generic(3, 0, 10, 84);

        wait (u_dut.u_fc_ctrl.done_o == 1);

        $display("[TB] FC Controller Reported DONE!");

        #(CLK_PERIOD * 10);

        verify_fc3_results();

        $display("\n========================================================");
        $display("[TB] ALL CHECKS PASSED. SIMULATION SUCCESSFUL.");
        $display("========================================================");
        $finish;
    end

    // Utility Tasks
    task load_all_fc_data();
        int o, i, idx;

        $display("[TB] Loading FC Data...");

        $readmemh("../rtl/init_files/fc1_weights.hex", temp_fc1_weights_linear);
        $readmemh("../rtl/init_files/fc1_bias.hex",    temp_fc1_bias_linear);

        idx = 0;
        for(o=0;o<120;o++) begin
            tb_fc1_bias[o]=temp_fc1_bias_linear[o];
            for(i=0;i<400;i++) begin
                tb_fc1_weights[o][i]=temp_fc1_weights_linear[idx];
                idx++;
            end
        end

        $readmemh("../rtl/init_files/fc2_weights.hex", temp_fc2_weights_linear);
        $readmemh("../rtl/init_files/fc2_bias.hex",    temp_fc2_bias_linear);

        idx = 0;
        for(o=0;o<84;o++) begin
            tb_fc2_bias[o]=temp_fc2_bias_linear[o];
            for(i=0;i<120;i++) begin
                tb_fc2_weights[o][i]=temp_fc2_weights_linear[idx];
                idx++;
            end
        end

        $readmemh("../rtl/init_files/fc3_weights.hex", temp_fc3_weights_linear);
        $readmemh("../rtl/init_files/fc3_bias.hex",    temp_fc3_bias_linear);

        idx = 0;
        for(o=0;o<10;o++) begin
            tb_fc3_bias[o]=temp_fc3_bias_linear[o];
            for(i=0;i<84;i++) begin
                tb_fc3_weights[o][i]=temp_fc3_weights_linear[idx];
                idx++;
            end
        end
    endtask

    task feed_fc_weights_generic(
        int layer_idx       ,
        int start_out_ch    ,
        int num_ch          ,
        int input_len
    );
        int i, k;
        logic signed [7:0] w;
        logic signed [31:0] b;

        $display("[TB] Waiting for FC%0d Weight Request (Batch Start: %0d)...", layer_idx, start_out_ch);

        wait (u_dut.u_fc_top.weight_req_o == 1);
        @(negedge clk_i);

        force u_dut.fc_weight_ack = 1;

        for (i=0; i<input_len; i++) begin
            for (k=0; k<100; k++) begin
                if (k < num_ch) begin
                    case(layer_idx)
                        1: begin w=tb_fc1_weights[start_out_ch+k][i]; b=tb_fc1_bias[start_out_ch+k]; end
                        2: begin w=tb_fc2_weights[start_out_ch+k][i]; b=tb_fc2_bias[start_out_ch+k]; end
                        3: begin w=tb_fc3_weights[start_out_ch+k][i]; b=tb_fc3_bias[start_out_ch+k]; end
                    endcase
                    tb_shadow_drive_weights[k]=w;
                    tb_shadow_drive_bias[k]=b;
                end else begin
                    tb_shadow_drive_weights[k]=0;
                    tb_shadow_drive_bias[k]=0;
                end
            end
            @(negedge clk_i);
        end

        force u_dut.fc_weight_ack = 0;

        wait (u_dut.u_fc_top.weight_req_o == 0);

        $display("[TB] FC%0d Batch Finished.", layer_idx);
    endtask

    task release_fc_signals();
        force u_dut.fc_weight_ack=0;
    endtask

    task verify_fc_load_data();
        int cnt=0, base=32'h0800, idx=0, ch, px, bank, addr;
        logic [7:0] exp, act;

        $display("   ... Checking SRAM -> Buffer Copy ...");
        for(ch=0;ch<16;ch++) for(px=0;px<25;px++) begin
            bank=ch%6; addr=base+px+(ch/6)*25;

            case(bank)
                0:exp=u_dut.u_global_mem.gen_sram_banks[0].mems[addr];
                1:exp=u_dut.u_global_mem.gen_sram_banks[1].mems[addr];
                2:exp=u_dut.u_global_mem.gen_sram_banks[2].mems[addr];
                3:exp=u_dut.u_global_mem.gen_sram_banks[3].mems[addr];
                4:exp=u_dut.u_global_mem.gen_sram_banks[4].mems[addr];
                5:exp=u_dut.u_global_mem.gen_sram_banks[5].mems[addr];
            endcase

            act               = u_dut.u_fc_top.u_local_mem.mem[idx];
            tb_fc1_input[idx] = exp;

            if(act!==exp) begin
                cnt++;
                if(cnt<5)
                    $display("[ERROR] Load Mismatch Idx %0d: Exp %h | Got %h", idx, exp, act);
            end
            idx++;
            end

            if(cnt==0)
                $display("   [PASS] Load Verified.");
            else begin
                $display("   [FAIL] Load Failed");
                $stop;
            end
    endtask

    task verify_fc1_results_and_capture();
        int cnt=0, base=400, o, i; logic signed [31:0] sum, b, val; logic signed [7:0] g, r;
        for(o=0;o<120;o++) begin
            sum=0; for(i=0;i<400;i++) sum+=$signed(tb_fc1_input[i])*$signed(tb_fc1_weights[o][i]);
            b=sum+tb_fc1_bias[o]; val=(b<0)?0:b; val=val>>>8;
            if(val>127) g=127; else if(val<-128) g=-128; else g=val[7:0];
            r=u_dut.u_fc_top.u_local_mem.mem[base+o]; tb_fc2_input[o]=r;
            if(r!==g) begin cnt++; if(cnt<=10) $display("[ERROR] FC1 Out %0d: Exp %d | Got %d", o, g, r); end
        end
        if(cnt==0) $display("   [PASS] FC1 Verified."); else $stop;
    endtask

    task verify_fc2_results_and_capture();
        int cnt=0, base=0, o, i;
        logic signed [31:0] sum, b, val;
        logic signed [7:0] g, r;

        for(o=0;o<84;o++) begin
            sum=0;
            for(i=0;i<120;i++)
                sum += $signed(tb_fc2_input[i])*$signed(tb_fc2_weights[o][i]);

            b=sum+tb_fc2_bias[o];
            val=(b<0)?0:b;
            val=val>>>8;

            if(val>127) g=127;
            else if(val<-128) g=-128;
            else g=val[7:0];

            r = u_dut.u_fc_top.u_local_mem.mem[base+o];
            tb_fc3_input[o]=r;
            if(r!==g) begin
                cnt++;
                if(cnt<=10)
                $display("[ERROR] FC2 Out %0d: Exp %d | Got %d", o, g, r);
            end
        end

        if(cnt==0)  $display("   [PASS] FC2 Verified.");
        else        $stop;
    endtask

    task verify_fc3_results();
        int cnt=0, base=400, o, i;
        logic signed [31:0] sum, b, val;
        logic signed [7:0] g, r;

        for(o=0;o<10;o++) begin
            sum=0;

            for(i=0;i<84;i++)
                sum+=$signed(tb_fc3_input[i])*$signed(tb_fc3_weights[o][i]);

            b=sum+tb_fc3_bias[o];
            val=b>>>8;

            if(val>127) g=127;
            else if(val<-128) g=-128;
            else g=val[7:0];

            r=u_dut.u_fc_top.u_local_mem.mem[base+o];
            if(r!==g) begin
                cnt++;
                if(cnt<=10)
                    $display("[ERROR] FC3 Out %0d: Exp %d | Got %d", o, g, r);
            end
        end

        if(cnt==0)  $display("   [PASS] FC3 Verified.");
        else        $stop;
    endtask

    task load_image_to_sram(string filename);
        int fd,val,code,r,c,addr;
        logic [7:0] img [32][32];

        for(r=0;r<32;r++)
            for(c=0;c<32;c++)
                img[r][c]=0;

        fd=$fopen(filename,"r");

        if(fd)begin
            for(r=0;r<28;r++)
                for(c=0;c<28;c++)begin
                    code=$fscanf(fd,"%h",val);
                    img[r+2][c+2]=val;
                end

            $fclose(fd);
        end

        addr=ADDR_IMG_IN;

        for(r=0;r<32;r++)begin
            for(c=0;c<32;c++)begin
                @(negedge clk_i);
                loader_sel=0;
                loader_wen=1;
                loader_addr=addr;
                loader_data[0]={24'b0,img[r][c]};
                addr++;
            end
        end

        @(negedge clk_i);
        loader_wen=0;
    endtask

    task load_weights_l1(string filename);
        int fd,addr,code;
        logic [63:0] val;

        addr=0;

        fd=$fopen(filename,"r");

        while(!$feof(fd))begin
            code=$fscanf(fd,"%h",val);

            if(code==1)begin
                @(negedge clk_i);
                loader_sel=1;
                loader_wen=1;
                loader_addr=addr;

                for(int k=0;k<6;k++)
                    loader_data[k]=(val>>(k*8))&8'hFF;

                addr++;
            end
        end

        $fclose(fd);

        @(negedge clk_i);
        loader_wen=0;
    endtask


    task load_bias_l1(string filename);
         int fd,val,code,k;
         logic [31:0] cache[6];
         k=0;

         fd=$fopen(filename,"r");

         while(!$feof(fd)&&k<6)begin
            code=$fscanf(fd,"%h",val);

            if(code==1) cache[k++]=val;
        end

        $fclose(fd);

        @(negedge clk_i);
        loader_sel=2;
        loader_wen=1;
        loader_addr=0;

        for(int j=0;j<6;j++)
            loader_data[j]=cache[j];

        @(negedge clk_i);
        loader_wen=0;

    endtask

    task dma_transfer_weights(int count);
        for(int i=0;i<count;i++)begin
            @(negedge clk_i);
            loader_sel=1;
            loader_wen=1;
            loader_addr=i;

            for(int k=0;k<6;k++)
                loader_data[k]=(dram_conv2_weights[ptr_w_conv2]>>(k*8))&8'hFF;

            ptr_w_conv2++;
        end

        @(negedge clk_i);
        loader_wen=0;

    endtask

    task dma_transfer_bias(int count);
        for(int i=0;i<count;i++)begin
            @(negedge clk_i);
            loader_sel=2;
            loader_wen=1;
            loader_addr=0;

            for(int k=0;k<6;k++)
                loader_data[k]=(dram_conv2_bias[ptr_b_conv2]>>(k*32))&32'hFFFFFFFF;

            ptr_b_conv2++;
        end

        @(negedge clk_i);
        loader_wen=0;

    endtask

endmodule
