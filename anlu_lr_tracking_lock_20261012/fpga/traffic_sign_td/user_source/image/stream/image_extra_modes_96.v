`timescale 1ns/1ps
// The six-mode chain adds equal delay to every mode. Original ERO/DIL pixels
// pass unchanged; only DEH enables dehaze, only MOT enables temporal detection.
module image_extra_modes_96 #(parameter integer IMG_WIDTH=1280,IMG_HEIGHT=720)(
    input wire I_clk,I_rst_n,I_tuser,I_tlast,I_tvalid,
    input wire [95:0] I_tdata,
    input wire [2:0] I_mode,
    output wire O_tuser,O_tlast,O_tvalid,
    output wire [95:0] O_tdata
);
    wire deh_user,deh_last,deh_valid;
    wire [95:0] deh_data;
    reg frame_motion;
    reg [10:0] motion_enable_pipe;
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin frame_motion<=0;motion_enable_pipe<=0;end
        else begin
            if(I_tvalid && I_tuser)frame_motion<=I_mode==3'd4;
            motion_enable_pipe<={motion_enable_pipe[9:0],(I_tvalid&&I_tuser)?I_mode==3'd4:frame_motion};
        end
    end
    dehaze_stream_96 #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) u_dehaze(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_tuser(I_tuser),.I_tlast(I_tlast),.I_tvalid(I_tvalid),
        .I_tdata(I_tdata),.I_enable(I_mode==3'd5),
        .O_tuser(deh_user),.O_tlast(deh_last),.O_tvalid(deh_valid),.O_tdata(deh_data));
    motion_stream_96 #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) u_motion(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_tuser(deh_user),.I_tlast(deh_last),.I_tvalid(deh_valid),
        .I_tdata(deh_data),.I_enable(motion_enable_pipe[10]),
        .O_tuser(O_tuser),.O_tlast(O_tlast),.O_tvalid(O_tvalid),.O_tdata(O_tdata));
endmodule
