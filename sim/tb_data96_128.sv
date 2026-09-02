`timescale 1ns / 1ps

module tb_data96_128;

    reg clk;
    reg rst_n;
    reg frame_start;
    reg valid;
    reg [95:0] data_in;
    wire frame_start_out;
    wire valid_out;
    wire [127:0] data_out;
    integer error_count;
    integer beat;

    data_96bit_to_128bit dut (
        .I_clk              (clk),
        .I_rst_n            (rst_n),
        .I_96b_frame_start  (frame_start),
        .I_96b_valid        (valid),
        .I_96b_data         (data_in),
        .O_128b_frame_start (frame_start_out),
        .O_128b_valid       (valid_out),
        .O_128b_data        (data_out)
    );

    always #5 clk = ~clk;

    task send_group;
        input integer index;
        begin
            @(negedge clk);
            valid = 1'b1;
            frame_start = (index == 0);
            data_in = {32'h10000000 + index, 32'h20000000 + index, 32'h30000000 + index};
            @(posedge clk);
            #1;
            if (index == 0) begin
                if (frame_start_out !== 1'b1 || valid_out !== 1'b0) begin
                    $display("[FAIL] first group marker/valid mismatch");
                    error_count = error_count + 1;
                end
            end
            else if (index == 1) begin
                if (frame_start_out !== 1'b0 || valid_out !== 1'b1 ||
                    data_out !== {32'h10000000, 32'h20000000, 32'h30000000, 32'h10000001}) begin
                    $display("[FAIL] packed beat 0 mismatch got=%h", data_out);
                    error_count = error_count + 1;
                end
            end
            else if (index == 2) begin
                if (frame_start_out !== 1'b0 || valid_out !== 1'b1 ||
                    data_out !== {32'h20000001, 32'h30000001, 32'h10000002, 32'h20000002}) begin
                    $display("[FAIL] packed beat 1 mismatch got=%h", data_out);
                    error_count = error_count + 1;
                end
            end
            else if (index == 3) begin
                if (frame_start_out !== 1'b0 || valid_out !== 1'b1 ||
                    data_out !== {32'h30000002, 32'h10000003, 32'h20000003, 32'h30000003}) begin
                    $display("[FAIL] packed beat 2 mismatch got=%h", data_out);
                    error_count = error_count + 1;
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        frame_start = 1'b0;
        valid = 1'b0;
        data_in = 96'd0;
        error_count = 0;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        send_group(0);
        send_group(1);
        send_group(2);
        send_group(3);

        @(negedge clk);
        valid = 1'b0;
        frame_start = 1'b0;
        @(posedge clk);
        #1;
        if (valid_out !== 1'b0 || frame_start_out !== 1'b0) begin
            $display("[FAIL] invalid input did not clear output");
            error_count = error_count + 1;
        end

        if (error_count == 0)
            $display("[RESULT] ALL 96-to-128 PACKER TESTS PASSED");
        else
            $display("[RESULT] 96-to-128 PACKER FAILURES=%0d", error_count);
        $finish;
    end

endmodule
