`timescale 1ns / 1ps

module tb_traffic_sign_joint_evidence;
    reg clk = 0;
    reg rst_n = 0;
    wire [7:0] ascii;
    wire valid, bbox;
    integer pattern, delta;
    reg [15:0] weak_mask, strong_mask;
    reg [1:0] original, reflected;
    traffic_sign_detector_96 dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_tuser(1'b0), .I_tlast(1'b0),
        .I_tvalid(1'b0), .I_tdata(96'd0), .O_busy(), .O_done(),
        .O_result_valid(valid), .O_result_class(), .O_result_ascii(ascii),
        .O_bbox_valid(bbox), .O_x_min(), .O_x_max(), .O_y_min(), .O_y_max(), .O_frame_drop()
    );
    always #5 clk = ~clk;

    function [15:0] mirror;
        input [15:0] mask;
        integer x, y;
        begin
            for (y = 0; y < 4; y = y + 1)
                for (x = 0; x < 4; x = x + 1)
                    mirror[y*4+x] = mask[y*4+3-x];
        end
    endfunction
    function [1:0] swap_turn;
        input [1:0] direction;
        begin
            swap_turn = direction == 1 ? 2 : direction == 2 ? 1 : direction;
        end
    endfunction

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        // 枚举全部强掩码，并为每个掩码构造不同的弱格超集。
        for (pattern = 0; pattern < 65536; pattern = pattern + 1) begin
            strong_mask = pattern;
            weak_mask = strong_mask | ((pattern * 25173 + 13849) & 16'hffff);
            original = dut.F_classify_arrow(strong_mask, 4095);
            reflected = dut.F_classify_arrow(mirror(strong_mask), 4095);
            if (reflected !== swap_turn(original)) $fatal(1, "强格分类不满足镜像: %h", strong_mask);
            original = dut.F_turn_shape(weak_mask, strong_mask, 4095);
            reflected = dut.F_turn_shape(mirror(weak_mask), mirror(strong_mask), 4095);
            if (reflected !== swap_turn(original)) $fatal(1, "弱格分类不满足镜像: %h/%h", weak_mask, strong_mask);
            if (dut.F_turn_shape(weak_mask, strong_mask, 23) !== 0) $fatal(1, "白色总量下限失效");
        end
        for (delta = -8; delta <= 8; delta = delta + 1) begin
            if (dut.F_edge_matches(200, 200+delta, 96) !== (delta >= -4 && delta <= 4))
                $fatal(1, "关联边界错误: delta=%0d", delta);
        end
        if (dut.F_edge_matches(0, 4095, 24) !== 0 || dut.F_edge_matches(4095, 0, 24) !== 0)
            $fatal(1, "边差缩放溢出");
        force dut.result_head_difference = 17'sd65534;
        force dut.result_stem_difference = -17'sd65534;
        #1;
        if (dut.head_difference_scaled !== 25'sd10485440 ||
            dut.stem_difference_scaled !== -25'sd10485440) $fatal(1, "有符号缩放溢出");
        release dut.result_head_difference;
        release dut.result_stem_difference;
        @(negedge clk); rst_n = 0;
        @(negedge clk);
        if (ascii !== "?" || valid || bbox || dut.result_commit_pending) $fatal(1, "复位没有清空流水");
        $display("PASS joint evidence: 65536 mirror masks, white floor, edge bounds, signed extrema, reset");
        $finish;
    end
endmodule
