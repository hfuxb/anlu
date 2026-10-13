`timescale 1ns/1ps
module tb_video_latency;
reg sys=0,cam=0,ddr=0,pix=0,rst=0;
always #5 sys=~sys;
always #7 cam=~cam;
always #3 ddr=~ddr;
always #11 pix=~pix;
reg csi_sof=0,isp_sof=0,cam_valid=0,err=0,vsync=0;
reg [32:0] capture_stamp=0;
wire [31:0] clock_gray;
wire [32:0] clock_stamp,display_stamp;
wire [131:0] bank_stamps;
wire wr_busy,wr_en,wr_req;wire [1:0] rp;
wire [24:0] wr_addr,rd_addr;wire [127:0] wr_data;
reg [1:0] read_bank=0;
wire rd_busy,rd_en,rd_req;wire [23:0] video_data;
video_latency_clock #(.CLK_HZ(1000000)) clock_dut(
 .I_clk(sys),.I_rst_n(rst),.I_camera_clk(cam),.I_camera_frame_start(csi_sof),
 .O_time_gray(clock_gray),.O_capture_stamp(clock_stamp));
video_in #(.FRAME_WORDS(240)) capture(
 .I_rst_n(rst),.I_camera_clk(cam),.I_camera_frame_start(isp_sof),.I_capture_stamp(capture_stamp),
 .O_bank_stamps(bank_stamps),.I_camera_valid(cam_valid),.I_camera_data(128'h123456),
 .I_mipi_rx_error(err),.I_ddr_clk(ddr),.I_display_pause(1'b0),.I_video_out_rd_busy(1'b0),
 .O_video_in_wr_busy(wr_busy),.O_video_out_rp(rp),.O_ddr_user_wr_en(wr_en),
 .O_ddr_user_addr(wr_addr),.O_ddr_user_wr_data(wr_data),.I_ddr_user_ready(1'b1),.O_ddr_user_req(wr_req));
video_out display(
 .I_rst_n(rst),.I_ddr_clk(ddr),.O_video_out_rd_busy(rd_busy),.I_video_in_wr_busy(1'b0),
 .I_video_out_rp(read_bank),.I_bank_stamps(bank_stamps),.O_display_stamp(display_stamp),
 .O_ddr_user_rd_en(rd_en),.O_ddr_user_addr(rd_addr),.I_ddr_user_ready(1'b0),.O_ddr_user_req(rd_req),
 .I_ddr_user_rd_valid(1'b0),.I_ddr_user_rd_data(128'd0),.I_dsi_clk(pix),
 .I_video_vsync(vsync),.I_video_rd_en(1'b0),.O_vdieo_data(video_data));
reg [31:0] synthetic_gray=0;
reg [32:0] synthetic_stamp=0;
reg output_sof=0;
wire [19:0] bcd;wire valid,overflow,update;
video_frame_latency meter(.I_clk(pix),.I_rst_n(rst),.I_frame_start(output_sof),
 .I_time_gray(synthetic_gray),.I_display_stamp(synthetic_stamp),
 .O_bcd(bcd),.O_valid(valid),.O_overflow(overflow),.O_update(update));
integer checks=0,writes=0;
reg [31:0] previous_gray=0;
always @(negedge sys)if(rst)begin
 if($countones(clock_gray^previous_gray)>1)$fatal(1,"Gray timebase changed more than one bit");
 previous_gray=clock_gray;
end else previous_gray=0;
always @(negedge ddr)if(wr_en && rst)writes=writes+1;
task check(input bit condition,input string message);begin
 if(!condition)$fatal(1,"%s",message);checks=checks+1;
end endtask
task frame(input integer stamp,input integer expected_bank,input integer count);
integer baseline;
begin
 baseline=writes;
 @(negedge cam);capture_stamp={1'b1,32'(stamp)};isp_sof=1;
 @(negedge cam);isp_sof=0;
 repeat(25)@(negedge cam);
 check(wr_addr===25'(expected_bank*7000000),"timestamp bank disagrees with real write address");
 check(bank_stamps[expected_bank*33+32]===1'b0,"bank became valid before frame complete");
 cam_valid=1;repeat(count)@(negedge cam);cam_valid=0;
 if(count==240)begin wait(writes==baseline+240 && !wr_busy);repeat(5)@(negedge ddr);end
 else repeat(40)@(negedge ddr);
 check(bank_stamps[expected_bank*33+:32]===32'(stamp),"frame timestamp attached to wrong bank");
 check(bank_stamps[expected_bank*33+32]===(count==240 && !err),"partial/bad frame validity incorrect");
end endtask
task read_frame(input integer bank,input bit expected_valid,input integer stamp);begin
 @(negedge pix);read_bank=2'(bank);vsync=1;
 @(negedge pix);check(display_stamp[32]===0,"old timestamp survived display VSYNC");
 repeat(10)@(negedge pix);vsync=0;repeat(10)@(negedge pix);
 check(rd_addr===25'(bank*7000000),"read frame bank address incorrect");
 check(display_stamp==={expected_valid,32'(stamp)},"read-bank timestamp did not cross atomically");
end endtask
function [19:0] decimal_bcd(input integer v);
 integer j;begin decimal_bcd=0;for(j=0;j<5;j=j+1)begin decimal_bcd[j*4+:4]=v%10;v=v/10;end end
endfunction
task measure(input reg [31:0] now,input reg [31:0] start,input bit stamp_valid,input integer expected,input bit ov);begin
 @(negedge pix);synthetic_gray=now^(now>>1);synthetic_stamp={stamp_valid,start};
 repeat(6)@(negedge pix);output_sof=1;
 @(negedge pix);output_sof=0;
 if(!update)begin wait(update);@(negedge pix);end
 check(valid===stamp_valid,"measurement validity incorrect");
 check(overflow===ov,"latency overflow flag incorrect");
 check(bcd===decimal_bcd(expected),"measured decimal latency wrong");
 check(meter.steps==0,"conversion did not finish before overlay");
end endtask
integer f;
initial begin
 repeat(8)@(negedge sys);rst=1;
 repeat(230)@(negedge sys);
 @(negedge cam);csi_sof=1;@(negedge cam);csi_sof=0;
 check(clock_stamp[32] && clock_stamp[31:0]==2,"capture timestamp/timebase tick wrong");
 read_frame(2,0,0); // startup: this bank has never received a complete frame.
 for(f=0;f<6;f=f+1)frame(1000+f,f%4,240);
 read_frame(0,1,1004);
 read_bank=2;repeat(12)@(negedge pix);
 check(rd_addr==0 && display_stamp=={1'b1,32'd1004},"midframe bank change retagged displayed pixels");
 read_frame(2,1,1002); // choose an older stored frame, not the latest capture.
 frame(2000,2,100);
 read_frame(2,0,2000);
 err=1;frame(3000,2,240); // error rewind writes previous bank, not wp=3.
 err=0;frame(4000,3,240);read_frame(3,1,4000);
 measure(4234,4000,1,234,0); // 23.4 ms
 measure(4400,4000,1,400,0); // repeated older frame ages to 40.0 ms
 measure(7,32'hffff_fffc,1,11,0); // modular counter wrap
 measure(55,12,0,0,0); // incomplete/error frame => dashes
 measure(100099,100,1,99999,0);
 measure(100100,100,1,99999,1); // >=10 seconds => OVFL, never a wrapped low value
 measure(1,32'hffff_f123,1,3806,0);
 @(negedge sys);rst=0;repeat(8)@(negedge pix);
 check(bank_stamps==0 && display_stamp==0 && clock_stamp==0 && !valid,"reset retained stale timestamp");
 $display("PASS VIDEO LATENCY %0d checks: shared Gray ticks, actual four DDR banks, full-frame validity, rewind, read latching, repeat age, wrap, BCD and overflow",checks);$finish;
end
initial begin #1000000;$fatal(1,"latency test timeout");end
endmodule

// Behavioral async FIFO for video_in/video_out integration, not a replacement
// for the vendor FIFO in the FPGA project. Track actual write/read words.
module w128_d512_fifo(input rst,clkw,we,input [127:0] di,input clkr,re,
 output reg [127:0] dout=0,output [8:0] wrusedw,rdusedw,
 output afull,full_flag,empty_flag,aempty,output reg valid=0);
 reg [127:0] mem[0:511];integer wp=0,rp=0;
 wire [31:0] used=wp-rp;
 assign wrusedw=used[8:0];assign rdusedw=used[8:0];
 assign afull=used>=480;assign full_flag=used>=512;assign empty_flag=used==0;assign aempty=used<4;
 always @(posedge clkw or posedge rst)begin
  if(rst)wp<=0;else if(we)begin if(full_flag)$fatal(1,"test FIFO overflow");mem[wp%512]<=di;wp<=wp+1;end
 end
 always @(posedge clkr or posedge rst)begin
  if(rst)begin rp<=0;dout<=0;valid<=0;end
  else begin valid<=0;if(re)begin if(empty_flag)$fatal(1,"test FIFO underflow");dout<=mem[rp%512];rp<=rp+1;valid<=1;end end
 end
endmodule
