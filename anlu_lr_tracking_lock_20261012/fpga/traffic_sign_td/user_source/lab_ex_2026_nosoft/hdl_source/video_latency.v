`timescale 1ns/1ps
// A single 0.1 ms timebase is shared by capture and display. Register Gray
// before crossing clock domains, so a counter carry cannot tear a timestamp.
module video_latency_clock #(parameter integer CLK_HZ=50000000)(
    input wire I_clk,I_rst_n,
    input wire I_camera_clk,I_camera_frame_start,
    output reg [31:0] O_time_gray,
    output reg [32:0] O_capture_stamp
);
    localparam integer TICK_CLOCKS=CLK_HZ/10000;
    reg [31:0] ticks;
    reg [12:0] prescale;
    wire [31:0] next_ticks=ticks+1'b1;
    (* ASYNC_REG="TRUE" *) reg [31:0] camera_gray_1,camera_gray_2;
    reg [2:0] camera_ready;
    function [31:0] gray_to_binary;
        input [31:0] value;
        integer k;
        begin
            for(k=0;k<32;k=k+1) gray_to_binary[k]=^(value>>k);
        end
    endfunction
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin ticks<=0;prescale<=0;O_time_gray<=0;end
        else if(prescale==TICK_CLOCKS-1) begin
            prescale<=0;ticks<=next_ticks;O_time_gray<=next_ticks^(next_ticks>>1);
        end else prescale<=prescale+1'b1;
    end
    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            camera_gray_1<=0;camera_gray_2<=0;camera_ready<=0;O_capture_stamp<=0;
        end else begin
            camera_gray_1<=O_time_gray;camera_gray_2<=camera_gray_1;
            camera_ready<={camera_ready[1:0],1'b1};
            if(I_camera_frame_start)
                O_capture_stamp<={camera_ready[2],gray_to_binary(camera_gray_2)};
        end
    end
endmodule

// Tags follow the ACTUAL write bank, including the existing MIPI-error rewind.
// A bank is usable only after all packed RGB words have entered the ordered
// DDR command FIFO. This FIFO preserves write-before-read ordering.
module video_latency_bank_tags #(parameter integer FRAME_WORDS=172800)(
    input wire I_clk,I_rst_n,I_frame_start,
    input wire [1:0] I_write_bank,
    input wire [32:0] I_capture_stamp,
    input wire I_write_en,I_frame_error,
    output wire [131:0] O_bank_stamps
);
    reg [32:0] stamps[0:3];
    reg [1:0] active_bank;
    reg [17:0] words;
    reg active,source_valid,bad;
    integer n;
    genvar g;
    generate for(g=0;g<4;g=g+1) begin: bank_bus
        assign O_bank_stamps[g*33+:33]=stamps[g];
    end endgenerate
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            for(n=0;n<4;n=n+1)stamps[n]<=0;
            active_bank<=0;words<=0;active<=0;source_valid<=0;bad<=0;
        end else if(I_frame_start) begin
            active_bank<=I_write_bank;words<=0;active<=1;
            source_valid<=I_capture_stamp[32];bad<=I_frame_error;
            stamps[I_write_bank]<={1'b0,I_capture_stamp[31:0]};
        end else if(active) begin
            if(I_frame_error)begin bad<=1;stamps[active_bank][32]<=0;end
            if(I_write_en && words<FRAME_WORDS) begin
                words<=words+1'b1;
                if(words==FRAME_WORDS-1)
                    stamps[active_bank][32]<=source_valid && !bad && !I_frame_error;
            end
        end
    end
endmodule

// The DDR read-frame event publishes the tag of the same bank used by the
// read-address generator. Source holds the bundle until destination ACK.
// Every display VSYNC clears freshness: a missing packet must show dashes,
// rather than reuse a previous display frame's timestamp.
module video_latency_read_tag_cdc(
    input wire I_src_clk,I_rst_n,I_src_frame_start,
    input wire [32:0] I_src_stamp,
    input wire I_dst_clk,I_dst_vsync,
    output reg [32:0] O_display_stamp
);
    reg req,ack;
    reg [32:0] mailbox;
    (* ASYNC_REG="TRUE" *) reg [1:0] ack_sync,req_sync;
    reg vsync_d;
    always @(posedge I_src_clk or negedge I_rst_n) begin
        if(!I_rst_n)begin req<=0;mailbox<=0;ack_sync<=0;end
        else begin
            ack_sync<={ack_sync[0],ack};
            if(I_src_frame_start && req==ack_sync[1])begin
                mailbox<=I_src_stamp;req<=~req;
            end
        end
    end
    always @(posedge I_dst_clk or negedge I_rst_n) begin
        if(!I_rst_n)begin ack<=0;req_sync<=0;vsync_d<=0;O_display_stamp<=0;end
        else begin
            req_sync<={req_sync[0],req};vsync_d<=I_dst_vsync;
            if(I_dst_vsync && !vsync_d)O_display_stamp<=0;
            else if(req_sync[1]!=ack)begin
                O_display_stamp<=mailbox;ack<=req_sync[1];
            end
        end
    end
endmodule

// Measure MIPI CSI frame start -> first HDMI active pixel for this read bank.
// Serial double-dabble needs 17 pixel clocks and uses no divider or DSP.
// It completes on line zero, before the overlay on line 16 is drawn.
module video_frame_latency(
    input wire I_clk,I_rst_n,I_frame_start,
    input wire [31:0] I_time_gray,
    input wire [32:0] I_display_stamp,
    output reg [19:0] O_bcd,
    output reg O_valid,O_overflow,O_update
);
    (* ASYNC_REG="TRUE" *) reg [31:0] time_gray_1,time_gray_2;
    reg [31:0] now_ticks;
    reg [16:0] shift_binary;
    reg [19:0] shift_bcd,adjusted_bcd;
    reg [4:0] steps;
    reg pending_overflow;
    wire [31:0] elapsed=now_ticks-I_display_stamp[31:0];
    integer k;
    function [31:0] gray_to_binary;
        input [31:0] value;
        integer j;
        begin
            for(j=0;j<32;j=j+1)gray_to_binary[j]=^(value>>j);
        end
    endfunction
    always @* begin
        adjusted_bcd=shift_bcd;
        for(k=0;k<5;k=k+1)
            if(shift_bcd[k*4+:4]>=5)adjusted_bcd[k*4+:4]=shift_bcd[k*4+:4]+4'd3;
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)begin
            time_gray_1<=0;time_gray_2<=0;now_ticks<=0;
            shift_binary<=0;shift_bcd<=0;steps<=0;pending_overflow<=0;
            O_bcd<=0;O_valid<=0;O_overflow<=0;O_update<=0;
        end else begin
            time_gray_1<=I_time_gray;time_gray_2<=time_gray_1;
            now_ticks<=gray_to_binary(time_gray_2);O_update<=0;
            if(I_frame_start)begin
                O_valid<=0;O_overflow<=0;shift_bcd<=0;
                pending_overflow<=elapsed>99999;
                if(I_display_stamp[32])begin
                    shift_binary<=elapsed>99999?17'd99999:elapsed[16:0];steps<=17;
                end else begin steps<=0;O_bcd<=0;O_update<=1;end
            end else if(steps!=0)begin
                shift_binary<={shift_binary[15:0],1'b0};
                shift_bcd<={adjusted_bcd[18:0],shift_binary[16]};steps<=steps-1'b1;
                if(steps==1)begin
                    O_bcd<={adjusted_bcd[18:0],shift_binary[16]};
                    O_valid<=1;O_overflow<=pending_overflow;O_update<=1;
                end
            end
        end
    end
endmodule
