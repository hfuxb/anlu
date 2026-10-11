`timescale 1ns / 1ps

module tb_traffic_sign_joint_replay;
    localparam integer WIDTH = 320;
    localparam integer HEIGHT = 240;
    reg clk = 0;
    reg rst_n = 0;
    reg tuser = 0;
    reg tlast = 0;
    reg tvalid = 0;
    reg [95:0] tdata = 0;
    reg [23:0] photo [0:9215];
    wire result_valid, bbox_valid, done, frame_drop;
    wire [7:0] ascii;
    wire [4:0] result_class;
    wire [10:0] xmin, xmax;
    wire [9:0] ymin, ymax;
    integer results = 0;
    integer checks = 0;
    integer correct_left = 0, correct_right = 0, correct_straight = 0;
    integer unknown_left = 0, unknown_right = 0, unknown_straight = 0;
    integer wrong = 0;
    integer baseline;
    integer blank_cycles = 20;
    integer check_frame_count = 1;
    integer burst_events;
    integer direction, dx, dy;
    reg [7:0] truth;
    reg [2047:0] fixture_root;
    reg [2047:0] fixture_file;

    traffic_sign_detector_96 #(.IMG_WIDTH(WIDTH), .IMG_HEIGHT(HEIGHT)) dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_tuser(tuser), .I_tlast(tlast),
        .I_tvalid(tvalid), .I_tdata(tdata), .O_busy(), .O_done(done),
        .O_result_valid(result_valid), .O_result_class(result_class),
        .O_result_ascii(ascii), .O_bbox_valid(bbox_valid),
        .O_x_min(xmin), .O_x_max(xmax), .O_y_min(ymin), .O_y_max(ymax),
        .O_frame_drop(frame_drop)
    );
    always #5 clk = ~clk;
    always @(posedge clk) begin
        if (rst_n && done !== result_valid) $fatal(1, "完成脉冲与结果脉冲不同步");
        if (rst_n && result_valid) results = results + 1;
    end

    task send_frame;
        input integer move_x;
        input integer move_y;
        input integer size;
        input integer brightness;
        input integer shape;
        integer y, group, lane, x, rx, ry, sx, sy, red, green, blue;
        integer initial_results;
        reg [23:0] rgb;
        reg [95:0] word;
        begin
            initial_results = results;
            for (y = 0; y < HEIGHT; y = y + 1) begin
                for (group = 0; group < WIDTH / 4; group = group + 1) begin
                    word = 0;
                    for (lane = 0; lane < 4; lane = lane + 1) begin
                        x = group * 4 + lane;
                        rx = x - WIDTH / 2 - move_x;
                        ry = y - HEIGHT / 2 - move_y;
                        rgb = 24'h141414;
                        if (size > 0 && rx >= -size/2 && rx < size/2 &&
                            ry >= -size/2 && ry < size/2) begin
                            sx = (rx + size/2) * 96 / size;
                            sy = (ry + size/2) * 96 / size;
                            rgb = photo[sy * 96 + sx];
                            red = rgb[23:16] * brightness / 100;
                            green = rgb[15:8] * brightness / 100;
                            blue = rgb[7:0] * brightness / 100;
                            rgb = {red[7:0], green[7:0], blue[7:0]};
                        end
                        // 负样本保持蓝色圆牌，单独替换其中的白色形状。
                        if (shape > 0) begin
                            rgb = 24'h141414;
                            if (rx*rx + ry*ry < 48*48) begin
                                rgb = 24'h1441b4;
                                if ((shape == 2 && ry >= -8 && ry <= 8) ||
                                    (shape == 3 && ((rx >= -8 && rx <= 8) || (ry >= -8 && ry <= 8))) ||
                                    (shape == 4 && rx*rx + ry*ry < 15*15))
                                    rgb = 24'hffffff;
                            end
                            if (shape == 5) rgb = 24'h6a7d99;
                            if (shape == 6) begin
                                rgb = 24'hbe8469;
                                if (rx*rx + ry*ry < 15*15) rgb = 24'hffffff;
                            end
                        end
                        word[lane*24 +: 24] = rgb;
                    end
                    @(negedge clk);
                    tvalid = 1;
                    tuser = y == 0 && group == 0;
                    tlast = group == WIDTH/4 - 1;
                    tdata = word;
                end
            end
            if (blank_cycles > 0) begin
                @(negedge clk);
                tvalid = 0; tuser = 0; tlast = 0; tdata = 0;
                repeat (blank_cycles) @(negedge clk);
                if (check_frame_count && results != initial_results + 1)
                    $fatal(1, "每帧结果数错误: %0d", results-initial_results);
                if (frame_drop !== 0 || done !== 0 || result_valid !== 0) $fatal(1, "结果脉冲未结束");
                if (ascii == "?" && (bbox_valid || xmin || xmax || ymin || ymax)) $fatal(1, "未知结果未清框");
                if (ascii != "?" && (!bbox_valid || xmin >= xmax || ymin >= ymax)) $fatal(1, "已识别结果框错误");
                if ((ascii == "L" && result_class != 1) || (ascii == "R" && result_class != 2) ||
                    (ascii == "S" && result_class != 3) || (ascii == "?" && result_class != 0))
                    $fatal(1, "类别与字符不同步");
            end
        end
    endtask

    task check_turn;
        input [7:0] expected;
        begin
            checks = checks + 1;
            $display("POSE expected=%c dx=%0d dy=%0d result=%c mask=%h roi=%0d,%0d:%0d,%0d",
                     expected, dx, dy, ascii, dut.result_stage_white_mask,
                     dut.result_stage_x_min, dut.result_stage_y_min,
                     dut.result_stage_x_max, dut.result_stage_y_max);
            if (ascii == expected) begin
                if (expected == "L") correct_left = correct_left + 1;
                if (expected == "R") correct_right = correct_right + 1;
                if (expected == "S") correct_straight = correct_straight + 1;
            end else if (ascii == "?") begin
                if (expected == "L") unknown_left = unknown_left + 1;
                if (expected == "R") unknown_right = unknown_right + 1;
                if (expected == "S") unknown_straight = unknown_straight + 1;
            end else wrong = wrong + 1;
            if (!baseline && expected != "S" && ascii !== expected)
                $fatal(1, "左右转位移失败: expected=%c got=%c dx=%0d dy=%0d", expected, ascii, dx, dy);
        end
    endtask

    initial begin
        baseline = $test$plusargs("BASELINE");
        if (!$value$plusargs("FIXTURES=%s", fixture_root)) fixture_root = ".";
        repeat (3) @(negedge clk);
        rst_n = 1;
        for (direction = 0; direction < 3; direction = direction + 1) begin
            case (direction)
                0: begin truth = "L"; fixture_file = {fixture_root, "/sign_left_96.mem"}; end
                1: begin truth = "R"; fixture_file = {fixture_root, "/sign_right_96.mem"}; end
                2: begin truth = "S"; fixture_file = {fixture_root, "/sign_straight_96.mem"}; end
            endcase
            $readmemh(fixture_file, photo);
            send_frame(0, 0, 96, 100, 0);
            send_frame(0, 0, 96, 100, 0);
            for (dy = -4; dy <= 4; dy = dy + 1) begin
                for (dx = -4; dx <= 4; dx = dx + 1) begin
                    send_frame(0, 0, 96, 100, 0);
                    send_frame(dx, dy, 96, 100, 0);
                    check_turn(truth);
                end
            end
        end
        $display("SUMMARY L=%0d/81 ?=%0d R=%0d/81 ?=%0d S=%0d/81 ?=%0d wrong=%0d",
                 correct_left, unknown_left, correct_right, unknown_right,
                 correct_straight, unknown_straight, wrong);
        if (baseline) begin
            if (correct_left == 81 && correct_right == 81) $fatal(1, "基线未复现左右转失败");
            $display("BASELINE 左右转位移失败已复现");
        end else begin
            if (wrong != 0 || correct_straight < 80) $fatal(1, "直行退步或发生错向");
            $readmemh("sign_left_96.mem", photo);
            send_frame(0, 0, 96, 100, 0);
            send_frame(0, 0, 96, 100, 0);
            send_frame(5, 0, 96, 100, 0);
`ifdef JOINT_FEATURES
            if (dut.result_candidate_matches !== 0) $fatal(1, "超过1/24仍启用补充证据");
`endif
            // 连续帧没有消隐间隔时，结果计数与取样框仍须属于同一帧。
            burst_events = results;
            blank_cycles = 0;
            send_frame(5, 0, 96, 100, 0);
            send_frame(5, 0, 96, 100, 0);
            blank_cycles = 20;
            // 排空流水时还会收到上一帧结果，改为检查整个连续帧组的总数。
            check_frame_count = 0;
            send_frame(5, 0, 96, 100, 0);
            check_frame_count = 1;
            if (results != burst_events + 3 || ascii !== "L") $fatal(1, "连续帧结果丢失或串帧");
            for (direction = 1; direction <= 6; direction = direction + 1) begin
                send_frame(0, 0, 0, 100, direction);
                send_frame(0, 0, 0, 100, direction);
                if (ascii !== "?") $fatal(1, "负样本%0d误识别为%c", direction, ascii);
            end
            send_frame(0, 0, 0, 100, 0);
            send_frame(0, 0, 0, 100, 0);
            if (ascii !== "?") $fatal(1, "移走路牌未清除");
            @(negedge clk); rst_n = 0;
            @(negedge clk);
            if (ascii !== "?" || bbox_valid || result_valid) $fatal(1, "复位未清除");
            $display("PASS traffic sign joint replay (%0d poses, 6 negatives)", checks);
        end
        $finish;
    end
endmodule
