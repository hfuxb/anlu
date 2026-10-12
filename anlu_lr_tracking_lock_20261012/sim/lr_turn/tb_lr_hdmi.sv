`timescale 1ns/1ps
module tb_lr_hdmi;
reg clk=0,rst=0,toggle=0;
always #5 clk=~clk;
wire vs,hs,de,user,last,rd,ovs,ohs,ode;
wire [23:0] rgb;
reg [7:0] ascii="L";
reg [50:0] meta={1'b1,11'd700,11'd879,10'd350,10'd529,8'd85};
uivtc #(.H_ActiveSize(1280),.H_FrameSize(1650),.H_SyncStart(1390),.H_SyncEnd(1430),
.V_ActiveSize(720),.V_FrameSize(750),.V_SyncStart(725),.V_SyncEnd(730)) vtc(
.I_vtc_rstn(rst),.I_vtc_clk(clk),.O_vtc_vs(vs),.O_vtc_hs(hs),.O_vtc_de_valid(de),.O_vtc_user(user),.O_vtc_last(last));
// Independent input-coordinate pattern catches extra read latency/line wrap.
reg [11:0] ix=0,iy=0;
wire [23:0] pattern={iy,ix};
always @(posedge clk)begin
 if(!rst)begin ix<=0;iy<=0;end
 else if(user)begin ix<=0;iy<=0;end
 else if(de)begin if(last)begin ix<=0;iy<=iy+1;end else ix<=ix+1;end
end
hdmi_mixer mixer(.I_clk(clk),.I_rst_n(rst),.I_video_vsync(vs),.I_video_hsync(hs),
.I_video_de(de),.I_video_user(user),.I_video_last(last),.I_debug_status(4'd0),.I_image_mode(2'b11),
.I_traffic_sign_mode(1'b0),.I_traffic_sign_busy(1'b0),.I_traffic_sign_result_toggle(toggle),
.I_traffic_sign_result_ascii(ascii),.I_traffic_sign_metadata(meta),.O_video_rd_en(rd),
.I_video_rd_data(pattern),.O_hdmi_vsync(ovs),.O_hdmi_hsync(ohs),.O_hdmi_de(ode),.O_hdmi_data(rgb));
reg [23:0] expected0=0,expected1=0,expected2=0;
reg [11:0] ex0=0,ex1=0,ex2=0,ey0=0,ey1=0,ey2=0;
reg ev0=0,ev1=0,ev2=0;
// The golden lookup uses independently delayed video coordinates, not DUT address.
wire [14:0] golden_logo_addr=(ex2<160 && ey2<160)?ey2*160+ex2:15'd0;
wire [24:0] golden_logo_pixel;
anlogic_logo_rom golden_logo(.I_addr(golden_logo_addr),.O_pixel(golden_logo_pixel));
integer frames=0,pixels=0,border_pixels=0,score_pixels=0,dir_pixels=0,logo_pixels=0,logo_colored=0;
reg started=0;
always @(posedge clk)begin
 expected0<=pattern;expected1<=expected0;expected2<=expected1;
 ex0<=ix;ex1<=ex0;ex2<=ex1;ey0<=iy;ey1<=ey0;ey2<=ey1;
 ev0<=de;ev1<=ev0;ev2<=ev1;
end
always @(negedge clk)if(rst)begin
 if(rd!==de)$fatal(1,"extra DDR reads");
 if(user && de)begin
  if(started)begin
   if(pixels!=921600)$fatal(1,"HDMI active pixel count %0d",pixels);
   if(border_pixels<1000 || score_pixels==0 || dir_pixels==0)$fatal(1,"missing ROI/score/direction overlay");
   if(logo_pixels!=25600 || logo_colored==0)$fatal(1,"Logo pixel coverage %0d/%0d",logo_pixels,logo_colored);
   frames=frames+1;
   if(frames==2)begin $display("PASS LR HDMI 720P frame latch / box / score / RGB alignment / full 160x160 Logo");$finish;end
  end
  started=1;pixels=0;border_pixels=0;score_pixels=0;dir_pixels=0;logo_pixels=0;logo_colored=0;
 end
 if(started && ode)begin
  pixels=pixels+1;
  if(ode!==ev2)$fatal(1,"DE latency changed");
  if(ex2<160 && ey2<160)begin
   logo_pixels=logo_pixels+1;
   if(golden_logo_pixel[24])begin
    if(rgb!==golden_logo_pixel[23:0])$fatal(1,"Logo address misalignment x=%0d y=%0d",ex2,ey2);
    logo_colored=logo_colored+1;
   end else if(rgb!==expected2)$fatal(1,"RGB shifted behind transparent Logo");
  end else if(ex2>=700 && ex2<=879 && ey2>=350 && ey2<=529)begin
   if(ex2<702 || ex2>877 || ey2<352 || ey2>527)begin
    if(rgb!==24'h20ff40)$fatal(1,"ROI border at wrong coordinate x=%0d y=%0d",ex2,ey2);
    border_pixels=border_pixels+1;
   end else if(rgb!==expected2)$fatal(1,"RGB inside ROI shifted");
  end else if(ex2>=375 && ex2<591 && ey2>=120 && ey2<240)begin
   if(ey2>=214 && rgb!==expected2)score_pixels=score_pixels+1;
   if(ey2>=154 && ey2<170 && ex2>=439 && ex2<455 && rgb!==expected2)dir_pixels=dir_pixels+1;
  end else if(!(ex2<160 && ey2<160) && rgb!==expected2)$fatal(1,"RGB shifted outside OSD");
 end
end
initial begin
 repeat(5)@(negedge clk);rst=1;repeat(4)@(negedge clk);toggle=1;
 // VTC emits its first USER after initial partial frame; wait for that latch.
 @(posedge user);repeat(2)@(negedge clk);
 // Change source metadata in active video: should take effect NEXT frame only.
 wait(mixer.S_y==400);@(negedge clk);ascii="R";meta[7:0]=8'd90;toggle=0;
 repeat(40)@(negedge clk);
 if(mixer.S_sign_ascii_frame!=="L" || mixer.S_sign_score!==85)$fatal(1,"metadata changed inside a display frame");
 @(posedge user);repeat(2)@(negedge clk);
 if(mixer.S_sign_ascii_frame!=="R" || mixer.S_sign_score!==90)$fatal(1,"metadata failed next-frame update");
end
initial begin #50000000;$fatal(1,"HDMI timeout");end
endmodule
