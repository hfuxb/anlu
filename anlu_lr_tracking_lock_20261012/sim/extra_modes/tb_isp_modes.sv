`timescale 1ns/1ps
// Actual isp_top routing + spatial/extra RTL. Stub only unchanged camera/AWB,
// recognition core; use the actual DDR packer and observe both boundaries.
module tb_isp_modes;
reg clk=0,rst=0,v=0,u=0,l=0;always #5 clk=~clk;
reg [2:0] mode=3;reg [39:0] din=0;wire [127:0] data;wire packed_valid,packed_last,packed_user;
isp_top #(.IMG_WIDTH(64),.IMG_HEIGHT(12)) dut(
 .axi4s_video_aclk(clk),.I_rst_n(rst),.I_tlast(l),.I_tuser(u),.I_tdata(din),
 .I_tvalid(v),.I_tdest(0),.I_algo_mode(mode),.I_recognition_request(mode==0),.I_force_normal(1'b0),
 .O_tready(1),.O_tdata(data),.O_tvalid(packed_valid),.O_tlast(packed_last),.O_tuser(packed_user));
wire gu,gl,gv;wire [95:0] gd;
integer frame_mode=3,f,x,y,count=0;reg [2:0] modes[0:5];
reg [255:0] reservoir=0;integer bits_available=0,packed_count=0;
reg expected_pv,expected_pl;reg [127:0] expected_packet;
always @(posedge clk)if(rst)begin
 expected_pv=0;expected_pl=0;
 if(u)begin bits_available=0;reservoir=0;end
 if(gv)begin
  reservoir=(reservoir<<96)|gd;bits_available=bits_available+96;
  if(bits_available>=128)begin
   bits_available=bits_available-128;
   expected_packet=reservoir>>bits_available;expected_pv=1;expected_pl=gl;
  end
 end
 #1;
 if(packed_valid!==expected_pv || packed_last!==expected_pl || packed_user!==u)
  $fatal(1,"ISP actual DDR packer markers wrong frame=%0d",f);
 if(packed_valid)begin
  if(data!==expected_packet)$fatal(1,"ISP actual DDR packed bits wrong frame=%0d packet=%0d",f,packed_count);
  packed_count=packed_count+1;
 end
end
image_extra_modes_96 #(.IMG_WIDTH(64),.IMG_HEIGHT(12),.PRE_DEHAZED(1)) reference(
 .I_clk(clk),.I_rst_n(rst),.I_tuser(dut.process_O_tuser),.I_tlast(dut.process_O_tlast),
 .I_tvalid(dut.process_O_tvalid),.I_tdata(dut.process_O_tdata),.I_mode(3'(frame_mode)),.I_enhance(frame_mode==5),
 .O_tuser(gu),.O_tlast(gl),.O_tvalid(gv),.O_tdata(gd));
always @(negedge clk)if(rst)begin
 if(dut.extra_O_tvalid!==gv || dut.extra_O_tuser!==gu || dut.extra_O_tlast!==gl)
  $fatal(1,"ISP extra markers mismatch");
 if(gv)begin
  if(dut.extra_O_tdata!==gd)$fatal(1,"ISP mode pipeline wrong frame=%0d",f);
  count=count+1;
 end
 if(dut.process_O_tuser && dut.process_O_tvalid && dut.process_mode_pipe[4]!==3'(frame_mode))
  $fatal(1,"ISP mode not aligned at SOF");
 if(mode==4 && dut.u_traffic_sign_detector_96.I_recognition_request)
  $fatal(1,"MOT low bits falsely requested SIG");
end
initial begin
 modes[0]=3;modes[1]=2;modes[2]=1;modes[3]=4;modes[4]=5;modes[5]=0;
 repeat(5)@(negedge clk);rst=1;
 for(f=0;f<6;f=f+1)begin
  frame_mode=modes[f];mode=modes[f];
  for(y=0;y<12;y=y+1)begin for(x=0;x<16;x=x+1)begin
   v=1;u=x==0&&y==0;l=x==15;din=24'h80c0e0;
   @(negedge clk);u=0;
   // change configuration mid-frame, after the first beat has been staged.
   if(x==2)mode=3'd3;
  end
  v=0;l=0;repeat(3)@(negedge clk);end
  v=0;u=0;l=0;repeat(35)@(negedge clk);
 end
 if(count!=1152)$fatal(1,"ISP count=%0d",count);
 if(packed_count!=864 || bits_available!=0)$fatal(1,"ISP packing count %0d remaining %0d",packed_count,bits_available);
 $display("PASS ISP UPGRADED SIX MODES: true three-bit routing, frame-mode alignment across spatial pipeline, actual DDR packing 864 words/72 rows with no offset and SIG request gate");$finish;
end
endmodule
module demosaic #(parameter IMG_HEIGHT=720,IMG_WIDTH=1280,data_complete_delay=50,BAYER_MODE="BGGR")(
 input I_clk,I_rst_n,input [39:0] axi4s_video_tdata,input [9:0] axi4s_video_tdest,
 input axi4s_video_tlast,axi4s_video_tvalid,axi4s_video_tuser,O_tready,
 output axi4s_video_tready,O_tlast,O_tuser,O_tvalid,output [127:0] O_tdata);
assign axi4s_video_tready=1;assign O_tlast=axi4s_video_tlast;assign O_tuser=axi4s_video_tuser;
assign O_tvalid=axi4s_video_tvalid;assign O_tdata={32'd0,{4{axi4s_video_tdata[23:0]}}};
endmodule
module data128_96(input [127:0] I_tdata,output [95:0] O_tdata);assign O_tdata=I_tdata[95:0];endmodule
module awb #(parameter IMG_HEIGHT=720,IMG_WIDTH=1280)(input I_clk,I_rst_n,I_tlast,I_tuser,I_tvalid,O_tready,
 input [95:0] I_tdata,output I_tready,O_tlast,O_tuser,O_tvalid,output [95:0] O_tdata);
assign I_tready=1;assign O_tlast=I_tlast;assign O_tuser=I_tuser;assign O_tvalid=I_tvalid;assign O_tdata=I_tdata;
endmodule
module traffic_sign_sig_only_96 #(parameter IMG_WIDTH=1280,IMG_HEIGHT=720)(
 input I_clk,I_rst_n,I_tuser,I_tlast,I_tvalid,input [95:0] I_tdata,input [1:0] I_algo_mode,input I_recognition_request,
 output O_enabled,O_busy,O_done,O_result_valid,O_box_valid,O_frame_drop,
 output [4:0] O_result_class,output [7:0] O_result_ascii,O_score,output [10:0] O_x_min,O_x_max,output [9:0] O_y_min,O_y_max);
assign {O_enabled,O_busy,O_done,O_result_valid,O_box_valid,O_frame_drop}=0;
assign {O_result_class,O_result_ascii,O_score,O_x_min,O_x_max,O_y_min,O_y_max}=0;
endmodule
