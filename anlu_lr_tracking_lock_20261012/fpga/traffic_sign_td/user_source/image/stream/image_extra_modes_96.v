`timescale 1ns/1ps
// The six-mode chain adds equal delay to every mode. Original ERO/DIL pixels
// pass unchanged; only DEH enables dehaze, only MOT enables temporal detection.
module image_extra_modes_96 #(parameter integer IMG_WIDTH=1280,IMG_HEIGHT=720,PRE_DEHAZED=0)(
    input wire I_clk,I_rst_n,I_tuser,I_tlast,I_tvalid,
    input wire [95:0] I_tdata,
    input wire [2:0] I_mode,
    input wire I_enhance,
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
    generate if(PRE_DEHAZED==0)begin: g_standalone_dehaze
    dehaze_stream_96 #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) u_dehaze(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_tuser(I_tuser),.I_tlast(I_tlast),.I_tvalid(I_tvalid),
        .I_tdata(I_tdata),.I_enable(I_mode==3'd5),
        .O_tuser(deh_user),.O_tlast(deh_last),.O_tvalid(deh_valid),.O_tdata(deh_data));
    end else begin: g_pre_dehazed
        assign deh_user=I_tuser;assign deh_last=I_tlast;assign deh_valid=I_tvalid;assign deh_data=I_tdata;
    end endgenerate
    wire enhanced_user,enhanced_last,enhanced_valid;
    wire [95:0] enhanced_data;
    generate if(PRE_DEHAZED!=0)begin: g_enhancement
        dehaze_enhance_96 #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) u_enhance(
          .I_clk(I_clk),.I_rst_n(I_rst_n),.I_tuser(deh_user),.I_tlast(deh_last),
          .I_tvalid(deh_valid),.I_tdata(deh_data),.I_enable(I_enhance),
          .O_tuser(enhanced_user),.O_tlast(enhanced_last),.O_tvalid(enhanced_valid),.O_tdata(enhanced_data));
    end else begin: g_no_enhancement
        assign enhanced_user=deh_user;assign enhanced_last=deh_last;
        assign enhanced_valid=deh_valid;assign enhanced_data=deh_data;
    end endgenerate
    reg motion_frame;reg [6:0] motion_pipe;
    always @(posedge I_clk or negedge I_rst_n)begin
       if(!I_rst_n)begin motion_frame<=0;motion_pipe<=0;end
       else begin
           if(I_tvalid&&I_tuser)motion_frame<=I_mode==4;
           motion_pipe<={motion_pipe[5:0],I_tvalid&&I_tuser?I_mode==4:motion_frame};
       end
    end
    motion_stream_96 #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) u_motion(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_tuser(enhanced_user),.I_tlast(enhanced_last),.I_tvalid(enhanced_valid),
        .I_tdata(enhanced_data),.I_enable(PRE_DEHAZED!=0?motion_pipe[6]:motion_enable_pipe[10]),
        .O_tuser(O_tuser),.O_tlast(O_tlast),.O_tvalid(O_tvalid),.O_tdata(O_tdata));
endmodule
