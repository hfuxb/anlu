`timescale 1ns / 1ps

module tb_traffic_sign_display_filter;
    reg clk = 0;
    reg rst_n = 0;
    reg raw_valid = 0;
    reg [7:0] raw_ascii = "?";
    reg raw_box = 0;
    reg [10:0] raw_x_min = 0, raw_x_max = 0;
    reg [9:0] raw_y_min = 0, raw_y_max = 0;
    wire display_valid;
    wire [7:0] display_ascii;
    wire display_box;
    wire [10:0] display_x_min, display_x_max;
    wire [9:0] display_y_min, display_y_max;

    traffic_sign_display_filter dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_result_valid(raw_valid),
        .I_ascii(raw_ascii), .I_bbox_valid(raw_box),
        .I_x_min(raw_x_min), .I_x_max(raw_x_max),
        .I_y_min(raw_y_min), .I_y_max(raw_y_max),
        .O_result_valid(display_valid), .O_ascii(display_ascii),
        .O_bbox_valid(display_box), .O_x_min(display_x_min),
        .O_x_max(display_x_max), .O_y_min(display_y_min),
        .O_y_max(display_y_max)
    );

    always #5 clk = ~clk;

    task sample;
        input [7:0] value;
        input has_box;
        input [10:0] xmax;
        input [7:0] expected;
        input expected_box;
        begin
            @(negedge clk);
            raw_valid = 1'b1;
            raw_ascii = value;
            raw_box = has_box;
            raw_x_min = 11'd100;
            raw_x_max = xmax;
            raw_y_min = 10'd100;
            raw_y_max = 10'd200;
            @(posedge clk);
            #1;
            if (!display_valid || display_ascii !== expected ||
                display_box !== expected_box)
                $fatal(1, "raw=%c displayed=%c/%b expected=%c/%b",
                       value, display_ascii, display_box, expected, expected_box);
            @(negedge clk);
            raw_valid = 1'b0;
            @(posedge clk);
            #1;
            if (display_valid) $fatal(1, "result pulse lasted too long");
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        sample("L", 1, 200, "?", 0);
        sample("L", 1, 200, "L", 1);
        sample("L", 1, 260, "L", 1);
        if (display_x_max !== 260) $fatal(1, "same sign did not update box size");
        sample("?", 0, 0, "L", 1);
        sample("R", 1, 220, "L", 1);
        sample("R", 1, 220, "R", 1);
        sample("?", 0, 0, "R", 1);
        sample("?", 0, 0, "R", 1);
        sample("?", 0, 0, "?", 0);
        if (display_x_min !== 0 || display_x_max !== 0)
            $fatal(1, "missing sign retained old box");
        sample("S", 1, 200, "?", 0);
        sample("S", 1, 200, "S", 1);
        $display("PASS traffic sign display filter");
        $finish;
    end
endmodule
