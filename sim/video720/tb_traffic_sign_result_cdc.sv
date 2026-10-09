`timescale 1ns/1ps

module tb_traffic_sign_result_cdc;
    reg src_clk = 0;
    reg dst_clk = 0;
    reg src_rst_n = 0;
    reg dst_rst_n = 0;
    reg src_toggle = 0;
    reg [7:0] src_ascii = "?";
    reg src_bbox_valid = 0;
    reg [10:0] src_x_min = 0;
    reg [10:0] src_x_max = 0;
    reg [9:0] src_y_min = 0;
    reg [9:0] src_y_max = 0;
    wire dst_toggle;
    wire [7:0] dst_ascii;
    wire dst_bbox_valid;
    wire [10:0] dst_x_min, dst_x_max;
    wire [9:0] dst_y_min, dst_y_max;
    wire dst_valid;
    integer events = 0;

    traffic_sign_result_cdc dut (
        .I_src_clk(src_clk), .I_src_rst_n(src_rst_n),
        .I_src_toggle(src_toggle), .I_src_ascii(src_ascii),
        .I_src_bbox_valid(src_bbox_valid),
        .I_src_x_min(src_x_min), .I_src_x_max(src_x_max),
        .I_src_y_min(src_y_min), .I_src_y_max(src_y_max),
        .I_dst_clk(dst_clk), .I_dst_rst_n(dst_rst_n),
        .O_dst_toggle(dst_toggle), .O_dst_ascii(dst_ascii),
        .O_dst_bbox_valid(dst_bbox_valid),
        .O_dst_x_min(dst_x_min), .O_dst_x_max(dst_x_max),
        .O_dst_y_min(dst_y_min), .O_dst_y_max(dst_y_max),
        .O_dst_valid(dst_valid)
    );

    always #5 src_clk = ~src_clk;
    always #7 dst_clk = ~dst_clk;
    always @(posedge dst_clk)
        if (dst_valid) events = events + 1;

    task send_result;
        input [7:0] ascii;
        input bbox_valid;
        input [10:0] x0;
        input [10:0] x1;
        input [9:0] y0;
        input [9:0] y1;
        begin
            @(negedge src_clk);
            src_ascii = ascii;
            src_bbox_valid = bbox_valid;
            src_x_min = x0;
            src_x_max = x1;
            src_y_min = y0;
            src_y_max = y1;
            src_toggle = ~src_toggle;
            wait (dst_valid === 1'b1);
            #1;
            if (dst_ascii !== ascii || dst_bbox_valid !== bbox_valid ||
                dst_x_min !== x0 || dst_x_max !== x1 ||
                dst_y_min !== y0 || dst_y_max !== y1)
                $fatal(1, "CDC payload mismatch: ascii=%c box=%b x=%0d..%0d y=%0d..%0d",
                       dst_ascii, dst_bbox_valid, dst_x_min, dst_x_max, dst_y_min, dst_y_max);
            @(posedge dst_clk);
            #1;
            if (dst_valid !== 1'b0)
                $fatal(1, "CDC valid must be a one-cycle pulse");
        end
    endtask

    initial begin
        repeat (4) @(posedge src_clk);
        src_rst_n = 1'b1;
        dst_rst_n = 1'b1;
        repeat (3) @(posedge dst_clk);

        send_result("L", 1'b1, 11'd101, 11'd151, 10'd202, 10'd252);
        // 输入总线在无toggle时变化，目标域必须保留上一份完整负载。
        @(negedge src_clk);
        src_ascii = "R";
        src_bbox_valid = 1'b0;
        src_x_min = 11'd900;
        src_x_max = 11'd950;
        src_y_min = 10'd600;
        src_y_max = 10'd650;
        repeat (8) @(posedge dst_clk);
        if (dst_ascii !== "L" || dst_bbox_valid !== 1'b1 ||
            dst_x_min !== 11'd101 || dst_x_max !== 11'd151 ||
            dst_y_min !== 10'd202 || dst_y_max !== 10'd252)
            $fatal(1, "stable CDC payload changed without toggle");

        send_result("S", 1'b1, 11'd901, 11'd959, 10'd601, 10'd659);
        send_result("?", 1'b0, 11'd0, 11'd0, 10'd0, 10'd0);
        if (events != 3)
            $fatal(1, "expected 3 CDC events, got %0d", events);
        $display("PASS traffic sign result CDC (%0d atomic events)", events);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "CDC simulation timeout");
    end
endmodule
