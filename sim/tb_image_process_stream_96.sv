`timescale 1ns/1ps

module tb_image_process_stream_96;

    localparam integer IMG_WIDTH   = 16;
    localparam integer IMG_HEIGHT  = 6;
    localparam integer GROUP_WIDTH = IMG_WIDTH / 4;
    localparam integer STREAM_LATENCY = 4;

    localparam [1:0] MODE_RAW      = 2'b00;
    localparam [1:0] MODE_SOBEL    = 2'b01;
    localparam [1:0] MODE_EROSION  = 2'b10;
    localparam [1:0] MODE_DILATION = 2'b11;

    reg clk;
    reg rst_n;
    reg tuser;
    reg tlast;
    reg tvalid;
    reg [95:0] tdata;
    reg [1:0] algo_mode;
    reg [10:0] edge_threshold;

    wire o_tuser;
    wire o_tlast;
    wire o_tvalid;
    wire [95:0] o_tdata;

    reg [95:0] model_input [0:IMG_HEIGHT-1][0:GROUP_WIDTH-1];
    reg [7:0] model_gray [0:IMG_HEIGHT-1][0:GROUP_WIDTH-1];
    reg model_sobel [0:IMG_HEIGHT-1][0:GROUP_WIDTH-1];
    reg [95:0] expected_data_queue [0:255];
    reg expected_user_queue [0:255];
    reg expected_last_queue [0:255];
    integer queue_head;
    integer queue_tail;
    integer queue_count;
    integer error_count;

    image_process_stream_96 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) dut (
        .I_clk           (clk),
        .I_rst_n         (rst_n),
        .I_tuser         (tuser),
        .I_tlast         (tlast),
        .I_tvalid        (tvalid),
        .I_tdata         (tdata),
        .I_algo_mode     (algo_mode),
        .I_edge_threshold(edge_threshold),
        .O_tuser         (o_tuser),
        .O_tlast         (o_tlast),
        .O_tvalid        (o_tvalid),
        .O_tdata         (o_tdata)
    );

    always #5 clk = ~clk;

    function [7:0] model_gray_pixel;
        input [23:0] pixel;
        integer weighted_sum;
        begin
            weighted_sum = pixel[23:16] * 77
                         + pixel[15:8]  * 150
                         + pixel[7:0]   * 29;
            model_gray_pixel = weighted_sum >> 8;
        end
    endfunction

    function [95:0] make_input_word;
        input integer x;
        input integer y;
        input integer raw_pattern;
        integer level;
        reg [23:0] pixel_0;
        reg [23:0] pixel_1;
        reg [23:0] pixel_2;
        reg [23:0] pixel_3;
        begin
            if (raw_pattern == 0) begin
                level = 0;
                pixel_0 = {level[7:0], level[7:0], level[7:0]};
                pixel_1 = pixel_0;
                pixel_2 = pixel_0;
                pixel_3 = pixel_0;
            end
            else if (raw_pattern == 2) begin
                level = (x >= 2) ? 255 : 0;
                pixel_0 = {level[7:0], level[7:0], level[7:0]};
                pixel_1 = pixel_0;
                pixel_2 = pixel_0;
                pixel_3 = pixel_0;
            end
            else if (raw_pattern == 3) begin
                level = (y >= 3) ? 255 : 0;
                pixel_0 = {level[7:0], level[7:0], level[7:0]};
                pixel_1 = pixel_0;
                pixel_2 = pixel_0;
                pixel_3 = pixel_0;
            end
            else if (raw_pattern == 4) begin
                level = x * 20;
                pixel_0 = {level[7:0], level[7:0], level[7:0]};
                pixel_1 = pixel_0;
                pixel_2 = pixel_0;
                pixel_3 = pixel_0;
            end
            else if (raw_pattern == 5) begin
                level = ((x == 2) && (y == 2)) ? 255 : 0;
                pixel_0 = {level[7:0], level[7:0], level[7:0]};
                pixel_1 = pixel_0;
                pixel_2 = pixel_0;
                pixel_3 = pixel_0;
            end
            else begin
                pixel_0[23:16] = x * 17 + y * 3 + 1;
                pixel_0[15:8]  = x * 5 + y * 11 + 2;
                pixel_0[7:0]   = x * 9 + y * 7 + 3;
                pixel_1[23:16] = x * 13 + y * 2 + 4;
                pixel_1[15:8]  = x * 3 + y * 19 + 5;
                pixel_1[7:0]   = x * 7 + y * 23 + 6;
                pixel_2[23:16] = x * 29 + y * 4 + 7;
                pixel_2[15:8]  = x * 31 + y * 6 + 8;
                pixel_2[7:0]   = x * 37 + y * 8 + 9;
                pixel_3[23:16] = x * 41 + y * 10 + 10;
                pixel_3[15:8]  = x * 43 + y * 12 + 11;
                pixel_3[7:0]   = x * 47 + y * 14 + 12;
            end
            make_input_word = {pixel_3, pixel_2, pixel_1, pixel_0};
        end
    endfunction

    function [7:0] model_group_gray;
        input [95:0] data_word;
        reg [7:0] gray_0;
        reg [7:0] gray_1;
        reg [7:0] gray_2;
        reg [7:0] gray_3;
        integer gray_sum;
        begin
            gray_0 = model_gray_pixel(data_word[23:0]);
            gray_1 = model_gray_pixel(data_word[47:24]);
            gray_2 = model_gray_pixel(data_word[71:48]);
            gray_3 = model_gray_pixel(data_word[95:72]);
            gray_sum = gray_0 + gray_1 + gray_2 + gray_3;
            model_group_gray = gray_sum >> 2;
        end
    endfunction

    function model_edge_bit;
        input integer x;
        input integer y;
        input integer threshold;
        integer gx_value;
        integer gy_value;
        integer magnitude;
        begin
            if ((x < 2) || (y < 2)) begin
                model_edge_bit = 1'b0;
            end
            else begin
                gx_value = model_gray[y-2][x] + (model_gray[y-1][x] << 1)
                         + model_gray[y][x]
                         - model_gray[y-2][x-2] - (model_gray[y-1][x-2] << 1)
                         - model_gray[y][x-2];
                gy_value = model_gray[y][x-2] + (model_gray[y][x-1] << 1)
                         + model_gray[y][x]
                         - model_gray[y-2][x-2] - (model_gray[y-2][x-1] << 1)
                         - model_gray[y-2][x];
                if (gx_value < 0)
                    gx_value = -gx_value;
                if (gy_value < 0)
                    gy_value = -gy_value;
                magnitude = gx_value + gy_value;
                model_edge_bit = magnitude > threshold;
            end
        end
    endfunction

    function model_morphology_bit;
        input integer x;
        input integer y;
        input integer dilation;
        integer row_index;
        integer col_index;
        reg all_on;
        reg any_on;
        begin
            if ((x < 2) || (y < 2)) begin
                model_morphology_bit = 1'b0;
            end
            else begin
                all_on = 1'b1;
                any_on = 1'b0;
                for (row_index = y - 2; row_index <= y; row_index = row_index + 1) begin
                    for (col_index = x - 2; col_index <= x; col_index = col_index + 1) begin
                        all_on = all_on & model_sobel[row_index][col_index];
                        any_on = any_on | model_sobel[row_index][col_index];
                    end
                end
                model_morphology_bit = dilation ? any_on : all_on;
            end
        end
    endfunction

    function [95:0] expected_word;
        input [1:0] mode;
        input integer x;
        input integer y;
        reg binary_value;
        begin
            case (mode)
                MODE_SOBEL: begin
                    binary_value = model_sobel[y][x];
                    expected_word = binary_value ? {96{1'b1}} : 96'd0;
                end
                MODE_EROSION: begin
                    binary_value = model_morphology_bit(x, y, 0);
                    expected_word = binary_value ? {96{1'b1}} : 96'd0;
                end
                MODE_DILATION: begin
                    binary_value = model_morphology_bit(x, y, 1);
                    expected_word = binary_value ? {96{1'b1}} : 96'd0;
                end
                default: expected_word = model_input[y][x];
            endcase
        end
    endfunction

    task build_model;
        input integer raw_pattern;
        input integer threshold;
        integer x;
        integer y;
        begin
            for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
                for (x = 0; x < GROUP_WIDTH; x = x + 1) begin
                    model_input[y][x] = make_input_word(x, y, raw_pattern);
                    model_gray[y][x] = model_group_gray(model_input[y][x]);
                end
            end
            for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
                for (x = 0; x < GROUP_WIDTH; x = x + 1)
                    model_sobel[y][x] = model_edge_bit(x, y, threshold);
            end
        end
    endtask

    task enqueue_expected;
        input [1:0] requested_mode;
        input integer x;
        input integer y;
        begin
            expected_data_queue[queue_tail] = expected_word(requested_mode, x, y);
            expected_user_queue[queue_tail] = (x == 0) && (y == 0);
            expected_last_queue[queue_tail] = (x == GROUP_WIDTH - 1);
            if (queue_tail == 255)
                queue_tail = 0;
            else
                queue_tail = queue_tail + 1;
            queue_count = queue_count + 1;
        end
    endtask

    task check_output;
        begin
            #1;
            if (o_tvalid === 1'b1) begin
                if (queue_count == 0) begin
                    $display("[FAIL] output valid has no queued input");
                    error_count = error_count + 1;
                end
                else begin
                    if (o_tuser !== expected_user_queue[queue_head]) begin
                        $display("[FAIL] delayed tuser mismatch");
                        error_count = error_count + 1;
                    end
                    if (o_tlast !== expected_last_queue[queue_head]) begin
                        $display("[FAIL] delayed tlast mismatch");
                        error_count = error_count + 1;
                    end
                    if (o_tdata !== expected_data_queue[queue_head]) begin
                        $display("[FAIL] delayed data mismatch got=%h expected=%h", o_tdata, expected_data_queue[queue_head]);
                        error_count = error_count + 1;
                    end
                    if (queue_head == 255)
                        queue_head = 0;
                    else
                        queue_head = queue_head + 1;
                    queue_count = queue_count - 1;
                end
            end
            else if (o_tvalid !== 1'b0) begin
                $display("[FAIL] output valid is unknown");
                error_count = error_count + 1;
            end
        end
    endtask

    task check_frame;
        input [1:0] requested_mode;
        input integer threshold;
        input integer raw_pattern;
        integer x;
        integer y;
        begin
            build_model(raw_pattern, threshold);
            for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
                for (x = 0; x < GROUP_WIDTH; x = x + 1) begin
                    @(negedge clk);
                    tvalid = 1'b1;
                    tuser = (x == 0) && (y == 0);
                    tlast = (x == GROUP_WIDTH - 1);
                    tdata = model_input[y][x];
                    if ((x == 0) && (y == 0)) begin
                        algo_mode = requested_mode;
                        edge_threshold = threshold;
                    end
                    else begin
                        algo_mode = requested_mode ^ 2'b01;
                        edge_threshold = (threshold == 24) ? 11'd0 : 11'd1023;
                    end

                    enqueue_expected(requested_mode, x, y);

                    @(posedge clk);
                    check_output;
                end
            end

            @(negedge clk);
            tvalid = 1'b0;
            tuser = 1'b0;
            tlast = 1'b0;
            repeat (STREAM_LATENCY + 2) begin
                @(posedge clk);
                check_output;
            end
            if (queue_count !== 0) begin
                $display("[FAIL] mode=%b queued outputs remain=%0d", requested_mode, queue_count);
                error_count = error_count + 1;
            end
            else begin
                $display("[PASS] mode=%b threshold=%0d", requested_mode, threshold);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        tuser = 1'b0;
        tlast = 1'b0;
        tvalid = 1'b0;
        tdata = 96'd0;
        algo_mode = MODE_RAW;
        edge_threshold = 11'd24;
        queue_head = 0;
        queue_tail = 0;
        queue_count = 0;
        error_count = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        check_frame(MODE_RAW, 24, 1);
        check_frame(MODE_SOBEL, 24, 0);
        check_frame(MODE_SOBEL, 24, 2);
        check_frame(MODE_SOBEL, 24, 3);
        check_frame(MODE_SOBEL, 1019, 2);
        check_frame(MODE_SOBEL, 1020, 2);
        check_frame(MODE_SOBEL, 1021, 2);
        check_frame(MODE_EROSION, 24, 0);
        check_frame(MODE_EROSION, 24, 4);
        check_frame(MODE_EROSION, 24, 5);
        check_frame(MODE_DILATION, 24, 0);
        check_frame(MODE_DILATION, 24, 4);
        check_frame(MODE_DILATION, 24, 5);

        if (error_count == 0)
            $display("[RESULT] ALL TESTS PASSED");
        else
            $display("[RESULT] FAILURES=%0d", error_count);
        $finish;
    end

endmodule
