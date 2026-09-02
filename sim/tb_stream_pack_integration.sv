`timescale 1ns/1ps

// 验证图像处理流与96位到128位打包器的边界标记连接。
module tb_stream_pack_integration;

    localparam integer IMG_WIDTH  = 16;
    localparam integer IMG_HEIGHT = 2;
    localparam integer GROUPS     = IMG_WIDTH / 4;
    localparam integer PROCESS_LATENCY = 4;

    reg         clk;
    reg         rst_n;
    reg         i_tuser;
    reg         i_tlast;
    reg         i_tvalid;
    reg  [95:0] i_tdata;

    wire        process_tuser;
    wire        process_tlast;
    wire        process_tvalid;
    wire [95:0] process_tdata;

    wire        packed_frame_start;
    wire        packed_valid;
    wire [127:0] packed_data;
    reg         process_tlast_d;
    wire        packed_tlast;

    integer error_count;
    integer packed_count;
    integer packed_tlast_count;
    integer packed_frame_start_count;
    reg expected_process_user [0:31];
    reg expected_process_last [0:31];
    integer process_queue_head;
    integer process_queue_tail;
    integer process_queue_count;

    image_process_stream_96 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_process (
        .I_clk           (clk),
        .I_rst_n         (rst_n),
        .I_tuser         (i_tuser),
        .I_tlast         (i_tlast),
        .I_tvalid        (i_tvalid),
        .I_tdata         (i_tdata),
        .I_algo_mode     (2'b00),
        .I_edge_threshold(11'd24),
        .O_tuser         (process_tuser),
        .O_tlast         (process_tlast),
        .O_tvalid        (process_tvalid),
        .O_tdata         (process_tdata)
    );

    data_96bit_to_128bit u_pack (
        .I_clk              (clk),
        .I_rst_n            (rst_n),
        .I_96b_frame_start  (process_tuser),
        .I_96b_valid        (process_tvalid),
        .I_96b_data         (process_tdata),
        .O_128b_frame_start (packed_frame_start),
        .O_128b_valid       (packed_valid),
        .O_128b_data        (packed_data)
    );

    assign packed_tlast = process_tlast_d && packed_valid;

    always #5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            process_tlast_d <= 1'b0;
        else
            process_tlast_d <= process_tlast;
    end

    task sample_outputs;
        begin
            #1;
            if (process_tvalid === 1'b1) begin
                if (process_queue_count == 0) begin
                    $display("[FAIL] process valid has no queued input");
                    error_count = error_count + 1;
                end
                else begin
                    if (process_tuser !== expected_process_user[process_queue_head] ||
                        process_tlast !== expected_process_last[process_queue_head]) begin
                        $display("[FAIL] delayed process marker mismatch");
                        error_count = error_count + 1;
                    end
                    if (process_queue_head == 31)
                        process_queue_head = 0;
                    else
                        process_queue_head = process_queue_head + 1;
                    process_queue_count = process_queue_count - 1;
                end
            end
            else if (process_tvalid !== 1'b0) begin
                $display("[FAIL] process valid is unknown");
                error_count = error_count + 1;
            end
            if (packed_valid)
                packed_count = packed_count + 1;
            if (packed_tlast)
                packed_tlast_count = packed_tlast_count + 1;
            if (packed_frame_start)
                packed_frame_start_count = packed_frame_start_count + 1;
        end
    endtask

    task send_group;
        input integer row;
        input integer column;
        reg [31:0] word_0;
        reg [31:0] word_1;
        reg [31:0] word_2;
        begin
            @(negedge clk);
            i_tvalid = 1'b1;
            i_tuser  = (row == 0) && (column == 0);
            i_tlast  = (column == GROUPS - 1);
            word_0 = 32'h10000000 + row * 16 + column;
            word_1 = 32'h20000000 + row * 16 + column;
            word_2 = 32'h30000000 + row * 16 + column;
            i_tdata  = {word_0, word_1, word_2};
            expected_process_user[process_queue_tail] = i_tuser;
            expected_process_last[process_queue_tail] = i_tlast;
            if (process_queue_tail == 31)
                process_queue_tail = 0;
            else
                process_queue_tail = process_queue_tail + 1;
            process_queue_count = process_queue_count + 1;
            @(posedge clk);
            sample_outputs;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        i_tuser = 1'b0;
        i_tlast = 1'b0;
        i_tvalid = 1'b0;
        i_tdata = 96'd0;
        process_tlast_d = 1'b0;
        error_count = 0;
        packed_count = 0;
        packed_tlast_count = 0;
        packed_frame_start_count = 0;
        process_queue_head = 0;
        process_queue_tail = 0;
        process_queue_count = 0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        send_group(0, 0);
        send_group(0, 1);
        send_group(0, 2);
        send_group(0, 3);
        send_group(1, 0);
        send_group(1, 1);
        send_group(1, 2);
        send_group(1, 3);

        @(negedge clk);
        i_tvalid = 1'b0;
        i_tuser = 1'b0;
        i_tlast = 1'b0;
        @(posedge clk);
        sample_outputs;
        repeat (PROCESS_LATENCY + 2) begin
            @(posedge clk);
            sample_outputs;
        end

        if (process_queue_count !== 0) begin
            $display("[FAIL] process outputs remain=%0d", process_queue_count);
            error_count = error_count + 1;
        end

        if (packed_count !== 6) begin
            $display("[FAIL] packed count=%0d expected=6", packed_count);
            error_count = error_count + 1;
        end
        if (packed_tlast_count !== 2) begin
            $display("[FAIL] packed tlast count=%0d expected=2", packed_tlast_count);
            error_count = error_count + 1;
        end
        if (packed_frame_start_count !== 1) begin
            $display("[FAIL] packed frame marker count=%0d expected=1", packed_frame_start_count);
            error_count = error_count + 1;
        end

        if (error_count == 0)
            $display("[RESULT] IMAGE STREAM TO PACKER INTEGRATION PASSED");
        else
            $display("[RESULT] IMAGE STREAM TO PACKER INTEGRATION FAILURES=%0d", error_count);
        $finish;
    end

endmodule
