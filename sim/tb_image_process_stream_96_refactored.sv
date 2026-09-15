`timescale 1ns/1ps

// 独立参考模型覆盖四像素组内、组边界、行边界和帧边界。
module tb_image_process_stream_96_refactored;
    localparam integer IMG_WIDTH  = 16;
    localparam integer IMG_HEIGHT = 4;
    localparam integer GROUPS     = IMG_WIDTH / 4;

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
    wire o_gray_tuser;
    wire o_gray_tlast;
    wire o_gray_tvalid;
    wire [31:0] o_gray_data;
    wire [1:0] o_gray_mode;

    reg [23:0] frame_rgb [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    reg [7:0] frame_gray [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    integer errors;
    integer x;
    integer y;
    integer group;
    integer lane;
    reg inject_midframe_mode_change;
    reg [1:0] changed_mode;

    image_process_stream_96 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_tuser(tuser), .I_tlast(tlast),
        .I_tvalid(tvalid), .I_tdata(tdata), .I_algo_mode(algo_mode),
        .I_edge_threshold(edge_threshold), .O_tuser(o_tuser),
        .O_tlast(o_tlast), .O_tvalid(o_tvalid), .O_tdata(o_tdata),
        .O_gray_tuser(o_gray_tuser), .O_gray_tlast(o_gray_tlast),
        .O_gray_tvalid(o_gray_tvalid), .O_gray_data(o_gray_data),
        .O_gray_mode(o_gray_mode)
    );

    always #5 clk = ~clk;

    function [7:0] gray_ref;
        input [23:0] pixel;
        integer sum;
        begin
            sum = pixel[23:16] * 77 + pixel[15:8] * 150 + pixel[7:0] * 29;
            gray_ref = sum >> 8;
        end
    endfunction

    function [7:0] gray_at;
        input integer px;
        input integer py;
        begin
            if ((px < 0) || (px >= IMG_WIDTH) ||
                (py < 0) || (py >= IMG_HEIGHT))
                gray_at = 8'd0;
            else
                gray_at = frame_gray[py][px];
        end
    endfunction

    function sobel_ref;
        input integer px;
        input integer py;
        input [10:0] threshold;
        integer gx;
        integer gy;
        begin
            gx = gray_at(px, py - 2) + (gray_at(px - 1, py - 1) << 1) +
                 gray_at(px, py) - gray_at(px - 2, py - 2) -
                 (gray_at(px - 2, py - 1) << 1) - gray_at(px - 2, py);
            gy = gray_at(px - 2, py) + (gray_at(px - 1, py) << 1) +
                 gray_at(px, py) - gray_at(px - 2, py - 2) -
                 (gray_at(px - 1, py - 2) << 1) - gray_at(px, py - 2);
            if (gx < 0) gx = -gx;
            if (gy < 0) gy = -gy;
            sobel_ref = ((gx + gy) > threshold);
        end
    endfunction

    function morph_ref;
        input integer px;
        input integer py;
        input dilation;
        integer dx;
        integer dy;
        reg any_bit;
        reg all_bit;
        begin
            any_bit = 1'b0;
            all_bit = 1'b1;
            if (py < 2) begin
                morph_ref = 1'b0;
            end
            else begin
                for (dy = -2; dy <= 0; dy = dy + 1) begin
                    for (dx = -2; dx <= 0; dx = dx + 1) begin
                        any_bit = any_bit | sobel_ref(px + dx, py + dy, edge_threshold);
                        all_bit = all_bit & sobel_ref(px + dx, py + dy, edge_threshold);
                    end
                end
                morph_ref = dilation ? any_bit : all_bit;
            end
        end
    endfunction

    task run_mode;
        input [1:0] mode;
        reg [95:0] word;
        reg [95:0] expected_data;
        reg [31:0] expected_gray_word;
        reg [7:0] expected_gray;
        reg expected_bit;
        reg pending_valid;
        reg pending_tuser;
        reg pending_tlast;
        reg [95:0] pending_data;
        reg [31:0] pending_gray_data;
        reg [1:0] pending_mode;
        reg pending2_valid;
        reg pending2_tuser;
        reg pending2_tlast;
        reg [95:0] pending2_data;
        reg [31:0] pending2_gray_data;
        reg [1:0] pending2_mode;
        reg pending3_valid;
        reg pending3_tuser;
        reg pending3_tlast;
        reg [95:0] pending3_data;
        reg [31:0] pending3_gray_data;
        reg [1:0] pending3_mode;
        integer px;
        begin
            pending_valid = 1'b0;
            pending_tuser = 1'b0;
            pending_tlast = 1'b0;
            pending_data = 96'd0;
            pending_gray_data = 32'd0;
            pending_mode = 2'b11;
            pending2_valid = 1'b0;
            pending2_tuser = 1'b0;
            pending2_tlast = 1'b0;
            pending2_data = 96'd0;
            pending2_gray_data = 32'd0;
            pending2_mode = 2'b11;
            pending3_valid = 1'b0;
            pending3_tuser = 1'b0;
            pending3_tlast = 1'b0;
            pending3_data = 96'd0;
            pending3_gray_data = 32'd0;
            pending3_mode = 2'b11;
            for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
                for (group = 0; group < GROUPS; group = group + 1) begin
                    word = 96'd0;
                    expected_data = 96'd0;
                    expected_gray_word = 32'd0;
                    for (lane = 0; lane < 4; lane = lane + 1) begin
                        px = group * 4 + lane;
                        case (lane)
                            0: word[23:0]  = frame_rgb[y][px];
                            1: word[47:24] = frame_rgb[y][px];
                            2: word[71:48] = frame_rgb[y][px];
                            default: word[95:72] = frame_rgb[y][px];
                        endcase
                        expected_gray = frame_gray[y][px];
                        case (lane)
                            0: expected_gray_word[7:0] = expected_gray;
                            1: expected_gray_word[15:8] = expected_gray;
                            2: expected_gray_word[23:16] = expected_gray;
                            default: expected_gray_word[31:24] = expected_gray;
                        endcase
                        if (mode == 2'b10)
                            expected_bit = morph_ref(px, y, 1'b0);
                        else if (mode == 2'b01)
                            expected_bit = morph_ref(px, y, 1'b1);
                        else
                            expected_bit = 1'b0;
                        if (mode == 2'b10 || mode == 2'b01) begin
                            case (lane)
                                0: expected_data[23:0]  = expected_bit ? 24'hffffff : 24'h000000;
                                1: expected_data[47:24] = expected_bit ? 24'hffffff : 24'h000000;
                                2: expected_data[71:48] = expected_bit ? 24'hffffff : 24'h000000;
                                default: expected_data[95:72] = expected_bit ? 24'hffffff : 24'h000000;
                            endcase
                        end
                    end
                    if ((mode != 2'b10) && (mode != 2'b01))
                        expected_data = word;

                    @(negedge clk);
                    tdata = word;
                    tvalid = 1'b1;
                    tuser = (y == 0) && (group == 0);
                    tlast = (group == GROUPS - 1);
                    algo_mode = (inject_midframe_mode_change &&
                                 (y == 1) && (group == 1)) ? changed_mode : mode;
                    @(posedge clk);
                    #1;
                    if ((o_tvalid !== pending3_valid) ||
                        (o_gray_tvalid !== pending3_valid)) begin
                        $display("FAIL missing output mode=%b y=%0d group=%0d", mode, y, group);
                        errors = errors + 1;
                    end
                    if (pending3_valid) begin
                        if ((o_tuser !== pending3_tuser) || (o_tlast !== pending3_tlast) ||
                            (o_gray_tuser !== pending3_tuser) || (o_gray_tlast !== pending3_tlast)) begin
                            $display("FAIL stream marker mode=%b y=%0d group=%0d", mode, y, group);
                            errors = errors + 1;
                        end
                        if (o_tdata !== pending3_data) begin
                            $display("FAIL image mode=%b y=%0d group=%0d got=%h expected=%h", mode, y, group, o_tdata, pending3_data);
                            errors = errors + 1;
                        end
                        if (o_gray_data !== pending3_gray_data || o_gray_mode !== pending3_mode) begin
                            $display("FAIL gray mode=%b y=%0d group=%0d got=%h expected=%h", mode, y, group, o_gray_data, pending3_gray_data);
                            errors = errors + 1;
                        end
                    end

                    pending3_valid = pending2_valid;
                    pending3_tuser = pending2_tuser;
                    pending3_tlast = pending2_tlast;
                    pending3_data = pending2_data;
                    pending3_gray_data = pending2_gray_data;
                    pending3_mode = pending2_mode;
                    pending2_valid = pending_valid;
                    pending2_tuser = pending_tuser;
                    pending2_tlast = pending_tlast;
                    pending2_data = pending_data;
                    pending2_gray_data = pending_gray_data;
                    pending2_mode = pending_mode;
                    pending_valid = 1'b1;
                    pending_tuser = tuser;
                    pending_tlast = tlast;
                    pending_data = expected_data;
                    pending_gray_data = expected_gray_word;
                    pending_mode = mode;
                end
            end
            @(negedge clk);
            tvalid = 1'b0;
            tuser = 1'b0;
            tlast = 1'b0;
            @(posedge clk);
            #1;
            if (!o_tvalid || !o_gray_tvalid ||
                (o_tuser !== pending3_tuser) || (o_tlast !== pending3_tlast) ||
                (o_gray_tuser !== pending3_tuser) || (o_gray_tlast !== pending3_tlast) ||
                (o_tdata !== pending3_data) ||
                (o_gray_data !== pending3_gray_data) || (o_gray_mode !== pending3_mode)) begin
                $display("FAIL pipeline flush mode=%b", mode);
                errors = errors + 1;
            end
            pending3_valid = pending2_valid;
            pending3_tuser = pending2_tuser;
            pending3_tlast = pending2_tlast;
            pending3_data = pending2_data;
            pending3_gray_data = pending2_gray_data;
            pending3_mode = pending2_mode;
            pending2_valid = pending_valid;
            pending2_tuser = pending_tuser;
            pending2_tlast = pending_tlast;
            pending2_data = pending_data;
            pending2_gray_data = pending_gray_data;
            pending2_mode = pending_mode;
            @(posedge clk);
            #1;
            if (!o_tvalid || !o_gray_tvalid ||
                (o_tuser !== pending3_tuser) || (o_tlast !== pending3_tlast) ||
                (o_gray_tuser !== pending3_tuser) || (o_gray_tlast !== pending3_tlast) ||
                (o_tdata !== pending3_data) ||
                (o_gray_data !== pending3_gray_data) || (o_gray_mode !== pending3_mode)) begin
                $display("FAIL final pipeline flush mode=%b", mode);
                errors = errors + 1;
            end
            @(posedge clk);
            #1;
            if (!o_tvalid || !o_gray_tvalid ||
                (o_tuser !== pending2_tuser) || (o_tlast !== pending2_tlast) ||
                (o_gray_tuser !== pending2_tuser) || (o_gray_tlast !== pending2_tlast) ||
                (o_tdata !== pending2_data) ||
                (o_gray_data !== pending2_gray_data) || (o_gray_mode !== pending2_mode)) begin
                $display("FAIL final window pipeline flush mode=%b", mode);
                errors = errors + 1;
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
        algo_mode = 2'b11;
        edge_threshold = 11'd10;
        errors = 0;
        inject_midframe_mode_change = 1'b0;
        changed_mode = 2'b11;

        for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
            for (x = 0; x < IMG_WIDTH; x = x + 1) begin
                if ((x >= 4) && (x < 12) && (y >= 1))
                    frame_rgb[y][x] = 24'hffffff;
                else
                    frame_rgb[y][x] = 24'h000000;
                frame_gray[y][x] = gray_ref(frame_rgb[y][x]);
            end
        end

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        inject_midframe_mode_change = 1'b1;
        changed_mode = 2'b01;
        run_mode(2'b10);
        inject_midframe_mode_change = 1'b0;
        run_mode(2'b11);
        run_mode(2'b01);
        run_mode(2'b10);
        run_mode(2'b00);

        if (errors == 0)
            $display("PASS image process stream");
        $finish;
    end
endmodule
