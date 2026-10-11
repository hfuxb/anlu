`timescale 1ns / 1ps

module tb_traffic_sign_photo_replay;
    localparam integer WIDTH = 320;
    localparam integer HEIGHT = 240;
    localparam integer GROUPS = WIDTH / 4;
    reg clk = 0, rst_n = 0, tuser = 0, tlast = 0, tvalid = 0;
    reg [95:0] tdata = 0;
    reg [23:0] photo [0:9215];
    reg [23:0] cyan_background [0:WIDTH*HEIGHT-1];
    reg use_cyan_background = 0;
    wire busy, done, result_valid, bbox_valid, frame_drop;
    wire [4:0] result_class;
    wire [7:0] result_ascii;
    wire [10:0] x_min, x_max;
    wire [9:0] y_min, y_max;
    integer checks = 0;
    integer mismatches = 0;
    integer candidate_misses = 0;
    integer characterize;

    traffic_sign_detector_96 #(.IMG_WIDTH(WIDTH), .IMG_HEIGHT(HEIGHT)) dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_tuser(tuser), .I_tlast(tlast),
        .I_tvalid(tvalid), .I_tdata(tdata), .O_busy(busy), .O_done(done),
        .O_result_valid(result_valid), .O_result_class(result_class),
        .O_result_ascii(result_ascii), .O_bbox_valid(bbox_valid),
        .O_x_min(x_min), .O_x_max(x_max), .O_y_min(y_min),
        .O_y_max(y_max), .O_frame_drop(frame_drop)
    );
    always #5 clk = ~clk;

    function [7:0] brighten;
        input [7:0] value;
        input integer percent;
        integer scaled;
        begin
            scaled = value * percent / 100;
            brighten = (scaled > 255) ? 8'd255 : scaled[7:0];
        end
    endfunction

    task send_frame;
        input integer sign_size;
        input integer brightness;
        input integer tilt;
        integer y, group, lane, px, dx, dy, sx, sy;
        reg [23:0] rgb;
        reg [95:0] word;
        begin
            for (y = 0; y < HEIGHT; y = y + 1) begin
                for (group = 0; group < GROUPS; group = group + 1) begin
                    word = 96'd0;
                    for (lane = 0; lane < 4; lane = lane + 1) begin
                        px = group * 4 + lane;
                        dx = px - WIDTH / 2;
                        dy = y - HEIGHT / 2;
                        rgb = use_cyan_background ?
                              cyan_background[y * WIDTH + px] : 24'h141414;
                        if (sign_size != 0 && dx >= -sign_size/2 && dx < sign_size/2 &&
                            dy >= -sign_size/2 && dy < sign_size/2) begin
                            sx = 48 + dx * 96 / sign_size + tilt * dy * 96 / (sign_size * 11);
                            sy = 48 + dy * 96 / sign_size - tilt * dx * 96 / (sign_size * 11);
                            if (sx >= 0 && sx < 96 && sy >= 0 && sy < 96) begin
                                rgb = photo[sy * 96 + sx];
                                rgb = {brighten(rgb[23:16], brightness),
                                       brighten(rgb[15:8], brightness),
                                       brighten(rgb[7:0], brightness)};
                            end
                        end
                        word[lane*24 +: 24] = rgb;
                    end
                    @(negedge clk);
                    tdata = word;
                    tvalid = 1'b1;
                    tuser = (y == 0 && group == 0);
                    tlast = (group == GROUPS - 1);
                    @(posedge clk);
                end
            end
            @(negedge clk);
            tvalid = 1'b0;
            tuser = 1'b0;
            tlast = 1'b0;
            // 帧尾证据分级计算；在结果提交后采样，避免读取上一帧输出。
            repeat (8) @(negedge clk);
        end
    endtask

    task run_case;
        input [7:0] truth;
        input integer sign_size;
        input integer brightness;
        input integer tilt;
        begin
            send_frame(sign_size, brightness, tilt);
            send_frame(sign_size, brightness, tilt);
            checks = checks + 1;
            $display("PHOTO truth=%c size=%0d bright=%0d tilt=%0d result=%c candidate=%b white=%0d mask=%h box=%0d,%0d:%0d,%0d",
                     truth, sign_size, brightness, tilt, result_ascii,
                     dut.result_stage_track_valid, dut.result_stage_white_total,
                     dut.result_stage_white_mask, dut.result_stage_x_min,
                     dut.result_stage_y_min, dut.result_stage_x_max,
                     dut.result_stage_y_max);
            if (result_ascii !== truth) begin
                mismatches = mismatches + 1;
                if (!dut.result_stage_track_valid) candidate_misses = candidate_misses + 1;
                if (!characterize)
                    $fatal(1, "photo replay mismatch: expected %c, got %c", truth, result_ascii);
            end
        end
    endtask

    initial begin
        characterize = $test$plusargs("CHARACTERIZE");
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        $readmemh("sign_left_96.mem", photo);
        run_case("L", 96, 100, 0);
        run_case("L", 64, 100, 0);
        run_case("L", 128, 100, 0);
        run_case("L", 192, 100, 0);
        run_case("L", 96, 75, 0);
        run_case("L", 96, 100, 1);
        run_case("L", 96, 100, -1);
        $readmemh("sign_right_96.mem", photo);
        run_case("R", 96, 100, 0);
        run_case("R", 64, 100, 0);
        run_case("R", 128, 100, 0);
        run_case("R", 192, 100, 0);
        run_case("R", 96, 75, 0);
        run_case("R", 96, 100, 1);
        run_case("R", 96, 100, -1);
        $readmemh("sign_straight_96.mem", photo);
        run_case("S", 96, 100, 0);
        run_case("S", 64, 100, 0);
        run_case("S", 128, 100, 0);
        run_case("S", 192, 100, 0);
        run_case("S", 96, 75, 0);
        run_case("S", 96, 100, 1);
        run_case("S", 96, 100, -1);
        run_case("?", 0, 100, 0);
        $readmemh("sign_cyan_background_320x240.mem", cyan_background);
        use_cyan_background = 1;
        run_case("?", 0, 100, 0);
        $readmemh("sign_left_96.mem", photo);
        run_case("L", 96, 75, 0);
        run_case("L", 128, 100, 0);
        run_case("L", 192, 100, 0);
        $readmemh("sign_right_96.mem", photo);
        run_case("R", 96, 75, 0);
        run_case("R", 128, 100, 0);
        run_case("R", 192, 100, 0);
        $readmemh("sign_straight_96.mem", photo);
        run_case("S", 96, 75, 0);
        run_case("S", 128, 100, 0);
        run_case("S", 192, 100, 0);
        run_case("?", 0, 100, 0);
        if (frame_drop !== 1'b0) $fatal(1, "unexpected frame drop");
        $display("SUMMARY photo checks=%0d mismatches=%0d candidate_misses=%0d", checks, mismatches, candidate_misses);
        if (mismatches != 0) $fatal(1, "photo replay存在%0d项失败，其中%0d项没有候选", mismatches, candidate_misses);
        $display("PASS traffic sign photo replay (%0d cases)", checks);
        $finish;
    end
endmodule
