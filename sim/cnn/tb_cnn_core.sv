`timescale 1ns/1ps

// 使用实际权重和偏置验证CNN核心的输入读时序、八路MAC和最终分类结果。
module tb_cnn_core;

    reg clk;
    reg rst_n;
    reg start;
    reg input_frame_ready;
    reg input_bank_select;
    wire input_rd_bank;
    wire [11:0] input_rd_addr;
    reg [7:0] input_rd_data;
    wire busy;
    wire done;
    wire result_valid;
    wire [4:0] result_class;
    wire [7:0] result_ascii;

    reg [7:0] input_mem [0:4095];
    integer i;
    integer cycle_count;
    integer error_count;
    reg busy_seen;
    reg done_seen;
    reg dumped_conv1;
    reg dumped_conv2;
    reg dumped_conv3;
    reg dumped_fc1;

    cnn_core dut (
        .aclk              (clk),
        .aresetn           (rst_n),
        .start             (start),
        .input_frame_ready (input_frame_ready),
        .input_bank_select (input_bank_select),
        .input_rd_bank     (input_rd_bank),
        .input_rd_addr     (input_rd_addr),
        .input_rd_data     (input_rd_data),
        .busy              (busy),
        .done              (done),
        .result_valid      (result_valid),
        .result_class      (result_class),
        .result_ascii      (result_ascii)
    );

    always #1 clk = ~clk;

    // 与采样器输入RAM相同的同步读行为。
    always @(posedge clk)
        input_rd_data <= input_mem[input_rd_addr];

    // 在层间切换后导出物理特征图，供Python定点模型逐字比较。
    always @(posedge clk) begin
        if (!dumped_conv1 && (dut.state == 6'd1) && (dut.bias_load_base == 8'd8)) begin
            #0.1;
            $writememh("../../work/tmp/cnn_actual_conv1.mem", dut.u_cnn_feat_bram_a.mem);
            dumped_conv1 = 1'b1;
        end
        if (!dumped_conv2 && (dut.state == 6'd1) && (dut.bias_load_base == 8'd24)) begin
            #0.1;
            $writememh("../../work/tmp/cnn_actual_conv2.mem", dut.u_cnn_feat_bram_b.mem);
            dumped_conv2 = 1'b1;
        end
        if (!dumped_conv3 && (dut.state == 6'd1) && (dut.bias_load_base == 8'd56)) begin
            #0.1;
            $writememh("../../work/tmp/cnn_actual_conv3.mem", dut.u_cnn_feat_bram_a.mem);
            dumped_conv3 = 1'b1;
        end
        if (!dumped_fc1 && (dut.state == 6'd1) && (dut.bias_load_base == 8'd120)) begin
            #0.1;
            $writememh("../../work/tmp/cnn_actual_fc1.mem", dut.u_cnn_feat_bram_b.mem);
            dumped_fc1 = 1'b1;
        end
    end

    initial begin
        for (i = 0; i < 4096; i = i + 1)
            input_mem[i] = ((i * 37 + (i / 64) * 11) ^ (i >> 3)) & 8'hff;

        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        input_frame_ready = 1'b1;
        input_bank_select = 1'b0;
        input_rd_data = 8'd0;
        cycle_count = 0;
        error_count = 0;
        busy_seen = 1'b0;
        done_seen = 1'b0;
        dumped_conv1 = 1'b0;
        dumped_conv2 = 1'b0;
        dumped_conv3 = 1'b0;
        dumped_fc1 = 1'b0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        while (!done_seen && cycle_count < 2000000) begin
            @(posedge clk);
            #0.1;
            cycle_count = cycle_count + 1;
            if (busy)
                busy_seen = 1'b1;
            if (done) begin
                done_seen = 1'b1;
                if (!result_valid) begin
                    $display("[FAIL] done without result_valid");
                    error_count = error_count + 1;
                end
                if (result_class !== 5'd6) begin
                    $display("[FAIL] result_class=%0d expected=6", result_class);
                    error_count = error_count + 1;
                end
                if (result_ascii !== "G") begin
                    $display("[FAIL] result_ascii=%h expected=47", result_ascii);
                    error_count = error_count + 1;
                end
            end
        end

        if (!busy_seen) begin
            $display("[FAIL] CNN never entered busy state");
            error_count = error_count + 1;
        end
        if (!done_seen) begin
            $display("[FAIL] CNN timeout after %0d cycles state=%0d layer=%0d conv=(%0d,%0d) ch=%0d k=%0d group=%0d fc=(%0d,%0d)",
                     cycle_count, dut.state, dut.layer_sel, dut.conv_x, dut.conv_y,
                     dut.out_channel, dut.kernel_index, dut.input_group,
                     dut.fc_out_index, dut.fc_word_index);
            error_count = error_count + 1;
        end
        if (busy) begin
            $display("[FAIL] busy remains high after done");
            error_count = error_count + 1;
        end

        $writememh("../../work/tmp/cnn_actual_feat_a.mem", dut.u_cnn_feat_bram_a.mem);
        $writememh("../../work/tmp/cnn_actual_feat_b.mem", dut.u_cnn_feat_bram_b.mem);

        if (error_count == 0)
            $display("[RESULT] CNN CORE TEST PASSED cycles=%0d class=%0d ascii=%s",
                     cycle_count, result_class, result_ascii);
        else
            $display("[RESULT] CNN CORE FAILURES=%0d cycles=%0d", error_count, cycle_count);
        $finish;
    end

endmodule
