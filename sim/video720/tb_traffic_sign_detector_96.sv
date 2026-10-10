`timescale 1ns/1ps

module tb_traffic_sign_detector_96;
    localparam integer IMG_WIDTH = 1280;
    localparam integer IMG_HEIGHT = 720;
    localparam integer GROUPS = IMG_WIDTH / 4;

    reg clk = 0;
    reg rst_n = 0;
    reg tuser = 0;
    reg tlast = 0;
    reg tvalid = 0;
    reg [95:0] tdata = 0;
    wire busy;
    wire done;
    wire result_valid;
    wire [4:0] result_class;
    wire [7:0] result_ascii;
    wire bbox_valid;
    wire [10:0] x_min, x_max;
    wire [9:0] y_min, y_max;
    wire frame_drop;
    integer checks = 0;
    integer result_events = 0;

    traffic_sign_detector_96 #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tuser(tuser), .I_tlast(tlast), .I_tvalid(tvalid), .I_tdata(tdata),
        .O_busy(busy), .O_done(done), .O_result_valid(result_valid),
        .O_result_class(result_class), .O_result_ascii(result_ascii),
        .O_bbox_valid(bbox_valid), .O_x_min(x_min), .O_x_max(x_max),
        .O_y_min(y_min), .O_y_max(y_max), .O_frame_drop(frame_drop)
    );

    always #5 clk = ~clk;
    always @(posedge clk)
        if (rst_n && result_valid)
            result_events = result_events + 1;

    task send_frame;
        input integer scene;
        integer y;
        integer group;
        integer lane;
        integer pixel_x;
        integer center_x;
        integer center_y;
        integer radius;
        integer direction;
        integer dx;
        integer dy;
        integer rel_x;
        integer rel_y;
        integer cell_x;
        integer cell_y;
        integer face_dx;
        integer face_dy;
        integer patch_blue;
        reg [15:0] arrow_mask;
        reg [7:0] red;
        reg [7:0] green;
        reg [7:0] blue;
        reg [95:0] word;
        begin
            center_x = 1120;
            center_y = 640;
            radius = 32;
            direction = 0;
            case (scene)
                1: direction = 3; // 直行
                2: direction = 1; // 左转
                3: direction = 2; // 右转
                6: direction = 4; // 不符合路牌箭头模板
                7: begin center_x = 8; center_y = 320; direction = 1; end
                8: begin center_x = 500; center_y = 300; radius = 14; direction = 3; end
                9: begin center_x = 900; center_y = 360; radius = 64; direction = 2; end
                10: direction = 1; // 左转箭头缺少一个模板格
                11: direction = 1; // 真路牌旁有较小的蓝色干扰圆
                12: direction = 0; // 圆形蓝底但没有白色箭头
                14: direction = 2; // 右转图像模糊时少一个白格
                15: direction = 3; // 直行原图缩小后的白格分布
                default: direction = 0;
            endcase

            // 左右转掩码取自用户路牌图片的蓝色外接框，经4x4白像素量化得到。
            case (direction)
                1: arrow_mask = 16'h4472;
                2: arrow_mask = 16'h22E4;
                3: arrow_mask = 16'h6666;
                4: arrow_mask = 16'h0FF0;
                default: arrow_mask = 16'd0;
            endcase
            if (scene == 14) arrow_mask = 16'h2264;
            if (scene == 15) arrow_mask = 16'h6466;

            for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
                for (group = 0; group < GROUPS; group = group + 1) begin
                    word = 96'd0;
                    for (lane = 0; lane < 4; lane = lane + 1) begin
                        pixel_x = group * 4 + lane;
                        red = 8'd20;
                        green = 8'd20;
                        blue = 8'd20;

                        // 模拟皮肤、眼睛和高光；这些白色细节不能单独触发检测。
                        face_dx = pixel_x - 480;
                        face_dy = y - 320;
                        if ((scene == 4) &&
                            (face_dx * face_dx + 2 * face_dy * face_dy < 9000)) begin
                            red = 8'd190;
                            green = 8'd132;
                            blue = 8'd105;
                            if (((face_dx >= -22 && face_dx <= -10) ||
                                 (face_dx >= 10 && face_dx <= 22)) &&
                                (face_dy >= -8 && face_dy <= -3)) begin
                                red = 8'd240; green = 8'd240; blue = 8'd240;
                            end
                            if ((face_dx >= -10 && face_dx <= 10) &&
                                (face_dy >= 18 && face_dy <= 22)) begin
                                red = 8'd240; green = 8'd240; blue = 8'd240;
                            end
                        end

                        // 分开的蓝色小块不能拼成一个全帧大框。
                        if ((scene == 13) &&
                            (((pixel_x >= 1070 && pixel_x < 1086) &&
                              (y >= 600 && y < 616)) ||
                             ((pixel_x >= 1140 && pixel_x < 1156) &&
                              (y >= 664 && y < 680)))) begin
                            red = 8'd20; green = 8'd50; blue = 8'd220;
                        end

                        patch_blue = 0;
                        if ((scene == 11) &&
                            ((pixel_x - 700) * (pixel_x - 700) +
                             (y - 300) * (y - 300) <= 20 * 20))
                            patch_blue = 1;
                        if (patch_blue != 0) begin
                            red = 8'd20; green = 8'd50; blue = 8'd220;
                        end

                        dx = pixel_x - center_x;
                        dy = y - center_y;
                        if ((scene == 1) || (scene == 2) || (scene == 3) ||
                            (scene == 6) || (scene == 7) || (scene == 8) ||
                            (scene == 9) || (scene == 10) || (scene == 11) ||
                            (scene == 12) || (scene == 14) || (scene == 15)) begin
                            if (dx * dx + dy * dy <= radius * radius) begin
                                red = 8'd20;
                                green = 8'd50;
                                blue = 8'd220;
                                rel_x = pixel_x - (center_x - radius);
                                rel_y = y - (center_y - radius);
                                cell_x = (rel_x * 4) / (radius * 2 + 1);
                                cell_y = (rel_y * 4) / (radius * 2 + 1);
                                if ((direction != 0) &&
                                    arrow_mask[cell_y * 4 + cell_x] &&
                                    !((scene == 10) && (cell_x == 1) && (cell_y == 0))) begin
                                    red = 8'd240;
                                    green = 8'd240;
                                    blue = 8'd240;
                                end
                            end
                        end

                        case (lane)
                            0: word[23:0] = {red, green, blue};
                            1: word[47:24] = {red, green, blue};
                            2: word[71:48] = {red, green, blue};
                            default: word[95:72] = {red, green, blue};
                        endcase
                    end
                    @(negedge clk);
                    tdata = word;
                    tvalid = 1'b1;
                    tuser = (y == 0) && (group == 0);
                    tlast = (group == GROUPS - 1);
                    @(posedge clk);
                end
            end
            @(negedge clk);
            tvalid = 1'b0;
            tuser = 1'b0;
            tlast = 1'b0;
            repeat (4) @(posedge clk);
            @(negedge clk);
        end
    endtask

    task check_scene;
        input integer scene;
        input [7:0] expected_ascii;
        input integer expected_x_min;
        input integer expected_x_max;
        input integer expected_y_min;
        input integer expected_y_max;
        input expected_box;
        integer events_before;
        begin
            events_before = result_events;
            send_frame(scene);
            send_frame(scene);
            checks = checks + 1;
            if ((result_events != events_before + 2) ||
                (result_ascii !== expected_ascii) || (bbox_valid !== expected_box)) begin
                $fatal(1, "scene %0d: events=%0d result=%c box=%b expected=%c/%b",
                       scene, result_events - events_before, result_ascii, bbox_valid,
                       expected_ascii, expected_box);
            end
            if (expected_box &&
                ((x_min < expected_x_min - 8) || (x_min > expected_x_min + 8) ||
                 (x_max < expected_x_max - 8) || (x_max > expected_x_max + 8) ||
                 (y_min < expected_y_min - 8) || (y_min > expected_y_min + 8) ||
                 (y_max < expected_y_max - 8) || (y_max > expected_y_max + 8))) begin
                $fatal(1, "scene %0d: bbox x=%0d..%0d y=%0d..%0d expected near %0d..%0d,%0d..%0d",
                       scene, x_min, x_max, y_min, y_max,
                       expected_x_min, expected_x_max, expected_y_min, expected_y_max);
            end
            if (!expected_box &&
                ((x_min != 0) || (x_max != 0) || (y_min != 0) || (y_max != 0)))
                $fatal(1, "scene %0d: invalid box retained coordinates", scene);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        check_scene(1, "S", 1088, 1152, 608, 672, 1'b1);
        check_scene(2, "L", 1088, 1152, 608, 672, 1'b1);
        check_scene(3, "R", 1088, 1152, 608, 672, 1'b1);
        check_scene(4, "?", 0, 0, 0, 0, 1'b0);
        check_scene(6, "?", 0, 0, 0, 0, 1'b0);
        check_scene(7, "?", 0, 0, 0, 0, 1'b0);
        check_scene(8, "S", 486, 514, 286, 314, 1'b1);
        check_scene(9, "R", 836, 964, 296, 424, 1'b1);
        check_scene(10, "L", 1088, 1152, 608, 672, 1'b1);
        check_scene(11, "L", 1088, 1152, 608, 672, 1'b1);
        check_scene(12, "?", 0, 0, 0, 0, 1'b0);
        check_scene(13, "?", 0, 0, 0, 0, 1'b0);
        check_scene(14, "R", 1088, 1152, 608, 672, 1'b1);
        check_scene(15, "S", 1088, 1152, 608, 672, 1'b1);
        check_scene(0, "?", 0, 0, 0, 0, 1'b0);

        if (frame_drop !== 1'b0)
            $fatal(1, "unexpected frame drop");
        $display("PASS traffic sign detector (%0d scenes)", checks);
        $finish;
    end
endmodule
