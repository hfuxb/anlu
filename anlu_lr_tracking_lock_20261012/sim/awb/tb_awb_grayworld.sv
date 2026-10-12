`timescale 1ns/1ps
module signal_delay #(
    parameter IMG_HEIGHT=720, IMG_WIDTH=1280,
    parameter DATA_WIDTH=96, DELAY_CYCLE=50
) (
    input I_clk, I_rst_n, I_tuser, I_valid,
    input [DATA_WIDTH-1:0] I_data,
    output O_valid,
    output [DATA_WIDTH-1:0] O_data,
    output O_tuser
);
    // Unit-test stub: the vendor BRAM delay is unchanged by this work.
    assign O_valid = I_valid;
    assign O_data = I_data;
    assign O_tuser = I_tuser;
endmodule

module tb_awb_grayworld;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    reg tuser=0, tlast=0, tvalid=0;
    reg [95:0] tdata=0;
    wire [95:0] out_data;
    wire out_valid, out_last, out_user, in_ready;
    awb #(.IMG_WIDTH(1280), .IMG_HEIGHT(720)) dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_tlast(tlast),
        .I_tuser(tuser), .I_tdata(tdata), .I_tvalid(tvalid),
        .I_tready(in_ready), .O_tlast(out_last), .O_tuser(out_user),
        .O_tdata(out_data), .O_tvalid(out_valid), .O_tready(1'b1)
    );
    integer i;
    integer seen_corrected=0;
    reg watch_corrected=0;
    reg [8:0] gain_r_previous;
    reg [8:0] gain_b_previous;
    reg [8:0] gain_r_before_black;
    reg [8:0] gain_b_before_black;
    reg tuser_last=0;
    always @(posedge clk) begin
        if (rst_n && !tuser && !tuser_last) begin
            if (dut.gain_r !== gain_r_previous ||
                dut.gain_b !== gain_b_previous)
                $fatal(1, "gain changed inside a frame");
        end
        gain_r_previous <= dut.gain_r;
        gain_b_previous <= dut.gain_b;
        tuser_last <= tuser;
        if (watch_corrected && out_valid) begin
            if (out_data[95:72] !== out_data[23:0] ||
                out_data[71:48] !== out_data[23:0] ||
                out_data[47:24] !== out_data[23:0])
                $fatal(1, "four RGB lanes differ");
            if (out_data[23:16] > 8'd80 && out_data[15:8] == 8'd120 &&
                out_data[7:0] > 8'd90)
                seen_corrected <= seen_corrected + 1;
        end
    end

    task start_frame;
    begin
        @(negedge clk);
        tvalid=0;
        tuser=1;
        @(negedge clk);
        tuser=0;
    end
    endtask

    task send_frame(input [7:0] r, input [7:0] g, input [7:0] b);
        integer k;
        reg [23:0] pixel;
    begin
        start_frame();
        pixel={r,g,b};
        tdata={4{pixel}};
        for (k=0; k<4096; k=k+1) begin
            tvalid=1;
            @(negedge clk);
        end
        tvalid=0;
        repeat (8) @(negedge clk);
    end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n=1;
        if (!in_ready) $fatal(1, "ready not propagated");
        send_frame(8'd100,8'd100,8'd100);
        send_frame(8'd100,8'd100,8'd100);
        if (dut.gain_r !== 9'd256 || dut.gain_b !== 9'd256)
            $fatal(1, "neutral frame changed gains");

        for (i=0; i<28; i=i+1)
            send_frame(8'd80,8'd120,8'd90);
        start_frame(); // Commit the previous frame's color statistics.
        #1;
        if (dut.gain_r <= 9'd300 || dut.gain_b <= 9'd300)
            $fatal(1, "green cast did not increase R/B gains");
        if (dut.gain_r > 9'd448 || dut.gain_b > 9'd448)
            $fatal(1, "gain exceeded clamp");

        watch_corrected=1;
        tdata={4{24'h50785a}};
        for (i=0; i<100; i=i+1) begin
            tvalid=1;
            @(negedge clk);
        end
        tvalid=0;
        repeat (8) @(negedge clk);
        watch_corrected=0;
        if (seen_corrected < 50)
            $fatal(1, "corrected RGB did not reach output");

        send_frame(8'd0,8'd0,8'd0);
        gain_r_before_black=dut.gain_r;
        gain_b_before_black=dut.gain_b;
        start_frame();
        #1;
        if (dut.gain_r !== gain_r_before_black ||
            dut.gain_b !== gain_b_before_black)
            $fatal(1, "black frame changed gain");

        for (i=0; i<12; i=i+1)
            send_frame(8'd150,8'd80,8'd150);
        start_frame();
        #1;
        if (dut.gain_r >= gain_r_before_black ||
            dut.gain_b >= gain_b_before_black)
            $fatal(1, "warm/magenta cast did not lower R/B gains");
        $display("PASS AWB frame-based gray-world control");
        $finish;
    end
endmodule
