`timescale 1ns/1ps
module tb_latency_hdmi #(parameter integer DISPLAY_REFRESH_MS=0);
localparam integer FRAME_COUNT=DISPLAY_REFRESH_MS==0?7:11;
reg clk=0,rst=0;always #5 clk=~clk;
wire vs,hs,de,user,last,rd,ovs,ohs,ode;wire [23:0] rgb;
reg [2:0] mode=3'd3;
reg [31:0] time_gray=0;
reg [32:0] stamp=0;
wire [19:0] latency_bcd;wire latency_valid,latency_overflow,latency_update;
uivtc #(.H_ActiveSize(1280),.H_FrameSize(1650),.H_SyncStart(1390),.H_SyncEnd(1430),
 .V_ActiveSize(720),.V_FrameSize(750),.V_SyncStart(725),.V_SyncEnd(730)) vtc(
 .I_vtc_rstn(rst),.I_vtc_clk(clk),.O_vtc_vs(vs),.O_vtc_hs(hs),
 .O_vtc_de_valid(de),.O_vtc_user(user),.O_vtc_last(last));
video_frame_latency measure(.I_clk(clk),.I_rst_n(rst),.I_frame_start(user),
 .I_time_gray(time_gray),.I_display_stamp(stamp),.O_bcd(latency_bcd),
 .O_valid(latency_valid),.O_overflow(latency_overflow),.O_update(latency_update));
reg [11:0] ix=0,iy=0;
wire [23:0] pattern={iy,ix};
always @(posedge clk)begin
 if(!rst || user)begin ix<=0;iy<=0;end
 else if(de)begin if(last)begin ix<=0;iy<=iy+1;end else ix<=ix+1;end
end
// Fast compatibility run validates each exact glyph; display holding has its
// own timer test and a separate full720 run at production refresh semantics.
hdmi_mixer #(.ENABLE_LATENCY(1),.LATENCY_REFRESH_MS(DISPLAY_REFRESH_MS)) mixer(.I_clk(clk),.I_rst_n(rst),
 .I_video_vsync(vs),.I_video_hsync(hs),.I_video_de(de),.I_video_user(user),.I_video_last(last),
 .I_debug_status(4'd0),.I_image_mode(mode),.I_traffic_sign_mode(1'b0),.I_traffic_sign_busy(1'b0),
 .I_traffic_sign_result_toggle(1'b0),.I_traffic_sign_result_ascii(8'h3f),.I_traffic_sign_metadata(51'd0),
 .I_latency_bcd(latency_bcd),.I_latency_valid(latency_valid),
 .I_latency_overflow(latency_overflow),.I_latency_update(latency_update),
 .O_video_rd_en(rd),.I_video_rd_data(pattern),.O_hdmi_vsync(ovs),.O_hdmi_hsync(ohs),
 .O_hdmi_de(ode),.O_hdmi_data(rgb));
reg [23:0] expected0=0,expected1=0,expected2=0;
reg [11:0] ex0=0,ex1=0,ex2=0,ey0=0,ey1=0,ey2=0;
reg ev0=0,ev1=0,ev2=0;
always @(posedge clk)begin
 expected0<=pattern;expected1<=expected0;expected2<=expected1;
 ex0<=ix;ex1<=ex0;ex2<=ex1;ey0<=iy;ey1<=ey0;ey2<=ey1;
 ev0<=de;ev1<=ev0;ev2<=ev1;
end
integer frame=0,pixels=0,label_pixels=0,ink_pixels=0,fd=0;
reg started=0;
function [7:0] golden_char(input integer f,input integer char_index);
 reg [95:0] text;
 begin
  if(DISPLAY_REFRESH_MS!=0)begin
   case(f)
    0,8:text="LAT:----.-MS";
    1,2:text="LAT:0213.4MS";
    3:text="LAT:OVFL  MS";
    4,5,6:text="LAT:0000.7MS";
    7:text="LAT:0009.6MS";
    9,10:text="LAT:0001.2MS";
    default:text="LAT:----.-MS";
   endcase
  end else case(f)
   0:text="LAT:----.-MS";
   1:text="LAT:0213.4MS";
   2:text="LAT:0002.1MS";
   3:text="LAT:OVFL  MS";
   4:text="LAT:0000.7MS";
   5:text="LAT:0005.8MS";
   6:text="LAT:0009.6MS";
   default:text="LAT:----.-MS";
  endcase
  golden_char=char_index>=0 && char_index<12?text[95-char_index*8-:8]:8'h20;
 end
endfunction
wire in_label=ex2>=1064 && ex2<1272 && ey2>=8 && ey2<40;
wire in_text=ex2>=1072 && ex2<1264 && ey2>=16 && ey2<32;
wire [7:0] wanted_char=golden_char(frame,(ex2-1072)/16);
wire [15:0] golden_rows;
osd_char_lib golden_font(.I_char(wanted_char),.I_row(4'(ey2-16)),.O_row_bits(golden_rows));
wire glyph=in_text && golden_rows[15-((ex2-1072)%16)];
wire [23:0] golden_color=glyph?((frame==0 || frame==3 || (DISPLAY_REFRESH_MS!=0 && frame==8))?24'hc0c0c0:24'h40ffff):24'h101820;
always @(negedge clk)if(rst)begin
 if(rd!==de)$fatal(1,"latency overlay changed DDR reads");
 if(started && ode!==ev2)$fatal(1,"latency overlay changed DE pipeline");
 if(user && de)begin
  if(started)begin
   if(pixels!=921600 || label_pixels!=6656 || ink_pixels<100)
    $fatal(1,"frame=%0d pixels=%0d label=%0d ink=%0d",frame,pixels,label_pixels,ink_pixels);
   $fclose(fd);$display("LATENCY HDMI FRAME %0d pixels=%0d right_top_glyph_pixels=%0d",frame,pixels,ink_pixels);
   frame=frame+1;
   if(frame==FRAME_COUNT)begin
    if(DISPLAY_REFRESH_MS==0)
     $display("PASS LATENCY HDMI 7 full720 frames: dashes, 213.4ms, wrap 2.1ms, OVFL, all six modes, exact top-right glyphs and unchanged RGB/DE/read timing");
    else
     $display("PASS LATENCY HDMI HOLD 11 full720 frames: held digits despite new measurements, frame-boundary latest-value refresh, immediate invalid/OVFL/recovery, exact glyphs and unchanged RGB/DE/read timing");
    $finish;
   end
  end
  started=1;pixels=0;label_pixels=0;ink_pixels=0;
  fd=$fopen($sformatf("latency_frame_%0d.hex",frame),"w");
 end
 if(started && ode)begin
  pixels=pixels+1;
  if(in_label)begin
   label_pixels=label_pixels+1;
   if(rgb!==golden_color)$fatal(1,"label mismatch frame=%0d x=%0d y=%0d char=%c actual=%h expected=%h",frame,ex2,ey2,wanted_char,rgb,golden_color);
   if(glyph)ink_pixels=ink_pixels+1;
   $fwrite(fd,"%06x\n",rgb);
  end else if(!(ex2<160 && ey2<160) && !(ex2>=375 && ex2<591 && ey2>=120 && ey2<240))begin
   if(rgb!==expected2)$fatal(1,"video shifted outside overlay x=%0d y=%0d",ex2,ey2);
  end
 end
end
task prepare(input [31:0] now,input [31:0] capture,input bit usable,input [2:0] m);begin
 @(negedge vs);@(negedge clk);time_gray=now^(now>>1);stamp={usable,capture};mode=m;
 @(posedge user);repeat(3)@(negedge clk);
end endtask
initial begin
 repeat(5)@(negedge clk);rst=1;
 prepare(2234,100,0,2'b11);
 prepare(2234,100,1,2'b10);
 prepare(5,32'hffff_fff0,1,2'b01);
 prepare(100100,100,1,2'b00);
 prepare(507,500,1,2'b11);
 prepare(558,500,1,3'd4);
 prepare(596,500,1,3'd5);
 if(DISPLAY_REFRESH_MS!=0)begin
  prepare(722,500,1,3'd0);
  prepare(750,500,0,3'd3);
  prepare(512,500,1,3'd4);
  prepare(580,500,1,3'd5);
 end
end
initial begin #190000000;$fatal(1,"latency HDMI timeout");end
endmodule

// Shortened refresh period exercises the production timer logic across real
// 720P frames without emitting 60 full-frame traces for each one-second step.
module tb_latency_hdmi_hold;
 tb_latency_hdmi #(.DISPLAY_REFRESH_MS(40)) test();
endmodule
