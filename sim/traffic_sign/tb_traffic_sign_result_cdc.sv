`timescale 1ns/1ps

// 验证路牌识别结果从摄像头时钟域进入HDMI像素时钟域时，toggle和ASCII数据保持一致。
module tb_traffic_sign_result_cdc;

    reg src_clk;
    reg dst_clk;
    reg src_rst_n;
    reg dst_rst_n;
    reg src_toggle;
    reg [7:0] src_ascii;
    wire dst_toggle;
    wire [7:0] dst_ascii;
    wire dst_valid;
    integer error_count;
    integer valid_count;

    traffic_sign_result_cdc dut (
        .I_src_clk    (src_clk),
        .I_src_rst_n  (src_rst_n),
        .I_src_toggle (src_toggle),
        .I_src_ascii  (src_ascii),
        .I_dst_clk    (dst_clk),
        .I_dst_rst_n  (dst_rst_n),
        .O_dst_toggle (dst_toggle),
        .O_dst_ascii  (dst_ascii),
        .O_dst_valid  (dst_valid)
    );

    always #5 src_clk = ~src_clk;
    always #7 dst_clk = ~dst_clk;

    always @(posedge dst_clk) begin
        if (dst_valid) begin
            valid_count = valid_count + 1;
            if ((valid_count == 1) && ((dst_ascii !== "G") || (dst_toggle !== 1'b1))) begin
                $display("[FAIL] first CDC result ascii=%h toggle=%b", dst_ascii, dst_toggle);
                error_count = error_count + 1;
            end
            if ((valid_count == 2) && ((dst_ascii !== "Z") || (dst_toggle !== 1'b0))) begin
                $display("[FAIL] second CDC result ascii=%h toggle=%b", dst_ascii, dst_toggle);
                error_count = error_count + 1;
            end
        end
    end

    task send_result;
        input [7:0] value;
        begin
            @(negedge src_clk);
            src_ascii = value;
            src_toggle = ~src_toggle;
        end
    endtask

    initial begin
        src_clk = 1'b0;
        dst_clk = 1'b0;
        src_rst_n = 1'b0;
        dst_rst_n = 1'b0;
        src_toggle = 1'b0;
        src_ascii = "A";
        error_count = 0;
        valid_count = 0;

        repeat (3) @(posedge src_clk);
        src_rst_n = 1'b1;
        dst_rst_n = 1'b1;

        send_result("G");
        repeat (8) @(posedge dst_clk);
        send_result("Z");
        repeat (8) @(posedge dst_clk);

        if (valid_count !== 2) begin
            $display("[FAIL] expected two CDC result pulses, got %0d", valid_count);
            error_count = error_count + 1;
        end

        if (error_count == 0)
            $display("[RESULT] TRAFFIC SIGN RESULT CDC TEST PASSED");
        else
            $display("[RESULT] TRAFFIC SIGN RESULT CDC FAILURES=%0d", error_count);
        $finish;
    end

endmodule
