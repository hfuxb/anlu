`timescale 1ns/1ps
module tb_lr_hdmi;
reg clk=0,rst=0,toggle=0;
always #5 clk=~clk;
wire vs,hs,de,user,last,rd,ovs,ohs,ode;
wire [23:0] rgb;
reg [2:0] image_mode=3'd3;
reg sign_mode=0;
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
.I_video_de(de),.I_video_user(user),.I_video_last(last),.I_debug_status(4'd0),.I_image_mode(image_mode),
.I_traffic_sign_mode(sign_mode),.I_traffic_sign_busy(1'b0),.I_traffic_sign_result_toggle(toggle),
.I_traffic_sign_result_ascii(ascii),.I_traffic_sign_metadata(meta),.O_video_rd_en(rd),
.I_video_rd_data(pattern),.O_hdmi_vsync(ovs),.O_hdmi_hsync(ohs),.O_hdmi_de(ode),.O_hdmi_data(rgb));
reg [23:0] expected0=0,expected1=0,expected2=0;
reg [11:0] ex0=0,ex1=0,ex2=0,ey0=0,ey1=0,ey2=0;
reg ev0=0,ev1=0,ev2=0;
// Golden logo uses independently delayed coordinates, not the DUT address.
wire [14:0] golden_logo_addr=(ex2<160 && ey2<160)?ey2*160+ex2:15'd0;
wire [24:0] golden_logo_pixel;
anlogic_logo_rom golden_logo(.I_addr(golden_logo_addr),.O_pixel(golden_logo_pixel));
integer frames=0,pixels=0,border_pixels=0,score_pixels=0,dir_pixels=0,logo_pixels=0,logo_colored=0,mode_pixels=0,count_pixels=0;
reg started=0;
wire expect_sign=(frames==1 || frames==2 || frames==3 || frames==7 || frames==8);
wire expect_box=(frames==2 || frames==3 || frames==8);
// New coordinate label is checked pixel-for-pixel by sim/coordinate. Here its
// fixed extent is permitted only when the coherent SIG L/R box is present.
wire in_coordinate_label=ex2>=700 && ex2<908 && ey2>=328 && ey2<348;
reg [2:0] expected_mode=3'd3;
reg [7:0] expected_ascii="?",expected_score=0;
always @(*)begin
 case(frames)
  0,6: expected_mode=3'd3;
  4: expected_mode=3'd2;
  5: expected_mode=3'd1;
  10: expected_mode=3'd4;
  11: expected_mode=3'd5;
  default: expected_mode=3'd0;
 endcase
 case(frames)
  2:begin expected_ascii="R";expected_score=90;end
  3:begin expected_ascii="L";expected_score=88;end
  8:begin expected_ascii="R";expected_score=91;end
  default:begin expected_ascii="?";expected_score=0;end
 endcase
end
always @(posedge clk)begin
 expected0<=pattern;expected1<=expected0;expected2<=expected1;
 ex0<=ix;ex1<=ex0;ex2<=ex1;ey0<=iy;ey1<=ey0;ey2<=ey1;
 ev0<=de;ev1<=ev0;ev2<=ev1;
end
always @(negedge clk)if(rst)begin
 if(rd!==de)$fatal(1,"extra DDR reads");
 if(started && ode!==ev2)$fatal(1,"DE latency changed");
 if(user && de)begin
  if(started)begin
   if(pixels!=921600)$fatal(1,"frame %0d active pixel count %0d",frames,pixels);
   if(expect_box && border_pixels<1000)$fatal(1,"missing SIG target border");
   if(!expect_box && border_pixels!=0)$fatal(1,"stale target border leaked");
   if(expect_sign && (score_pixels==0 || dir_pixels==0))$fatal(1,"SIG status missing");
   if(!expect_sign && (score_pixels!=0 || dir_pixels!=0))$fatal(1,"recognition status leaked outside SIG");
   if(mode_pixels==0 || count_pixels==0)$fatal(1,"mode or frame count was hidden");
   if(logo_pixels!=25600 || logo_colored==0)$fatal(1,"Logo coverage %0d/%0d",logo_pixels,logo_colored);
   $display("HDMI FRAME %0d mode=%b sign=%0d box=%0d pixels=%0d",frames,expected_mode,expect_sign,expect_box,pixels);
   frames=frames+1;
   if(frames==12)begin
    $display("PASS LR HDMI 12 full720 frames: SIG-only OSD / RAW-ERO-DIL-MOT-DEH hidden / stale epoch clearing / frame mode latch / RGB alignment / full 160x160 Logo");$finish;
   end
  end
  started=1;pixels=0;border_pixels=0;score_pixels=0;dir_pixels=0;logo_pixels=0;logo_colored=0;mode_pixels=0;count_pixels=0;
 end
 if(started && ode)begin
  pixels=pixels+1;
  // Check coherent state throughout the frame, including the mid-frame switch.
  if(mixer.S_image_mode_frame!==expected_mode || mixer.S_traffic_sign_mode_frame!==expect_sign)
   $fatal(1,"mode changed inside frame %0d actual=%b/%b expected=%b/%b",frames,mixer.S_image_mode_frame,mixer.S_traffic_sign_mode_frame,expected_mode,expect_sign);
  if(mixer.S_sign_ascii_frame!==expected_ascii || mixer.S_sign_score!==expected_score || mixer.S_sign_box!==expect_box)
   $fatal(1,"stale/incoherent metadata frame=%0d ascii=%c score=%0d box=%0d",frames,mixer.S_sign_ascii_frame,mixer.S_sign_score,mixer.S_sign_box);
  if(ex2<160 && ey2<160)begin
   logo_pixels=logo_pixels+1;
   if(golden_logo_pixel[24])begin
    if(rgb!==golden_logo_pixel[23:0])$fatal(1,"Logo misalignment x=%0d y=%0d",ex2,ey2);
    logo_colored=logo_colored+1;
   end else if(rgb!==expected2)$fatal(1,"RGB shifted behind transparent Logo");
  end else if(in_coordinate_label && expect_box)begin
   if(rgb!==24'h20ff40 && rgb!==24'h101820)$fatal(1,"coordinate label color invalid");
  end else if(ex2>=700 && ex2<=879 && ey2>=350 && ey2<=529)begin
   if(expect_box && (ex2<702 || ex2>877 || ey2<352 || ey2>527))begin
    if(rgb!==24'h20ff40)$fatal(1,"ROI border wrong x=%0d y=%0d",ex2,ey2);
    border_pixels=border_pixels+1;
   end else if(rgb!==expected2)$fatal(1,"RGB shifted or stale ROI border");
  end else if(ex2>=375 && ex2<591 && ey2>=120 && ey2<240)begin
   if(ey2>=214)begin
    if(rgb!==expected2)score_pixels=score_pixels+1;
    if(!expect_sign && rgb!==expected2)$fatal(1,"MATCH leaked outside SIG");
   end else if(ey2>=150 && ey2<174)begin
    if(rgb!==expected2)dir_pixels=dir_pixels+1;
    if(!expect_sign && rgb!==expected2)$fatal(1,"DIR leaked outside SIG");
   end else if(ey2>=180 && ey2<204)begin
    if(rgb!==expected2)mode_pixels=mode_pixels+1;
   end else if(ey2>=120 && ey2<144)begin
    if(rgb!==expected2)count_pixels=count_pixels+1;
   end else if(rgb!==expected2)$fatal(1,"RGB shifted between status rows");
  end else if(rgb!==expected2)$fatal(1,"RGB shifted outside OSD");
 end
end
task midframe;begin wait(iy==400 && ix==0);@(negedge clk);end endtask
task nextframe;begin @(posedge user);repeat(3)@(negedge clk);end endtask
initial begin
 repeat(5)@(negedge clk);rst=1;
 // First complete frame is RAW, despite a stale L packet in the CDC input.
 nextframe;
 midframe;image_mode=2'b00;sign_mode=1;toggle=1;
 nextframe; // frame 1: enter SIG; stale L must not be displayed.
 midframe;ascii="R";meta[7:0]=90;toggle=0;
 nextframe; // frame 2: fresh R now visible.
 midframe;ascii="L";meta[7:0]=88;toggle=1;
 nextframe; // frame 3: fresh L now visible.
 midframe;image_mode=2'b10;sign_mode=0;
 nextframe; // frame 4: ERO, all recognition overlays absent.
 midframe;image_mode=2'b01;
 nextframe; // frame 5: DIL, all recognition overlays absent.
 midframe;image_mode=2'b11;
 nextframe; // frame 6: RAW, all recognition overlays absent.
 midframe;image_mode=2'b00;sign_mode=1;
 nextframe; // frame 7: re-enter SIG, no toggle and old L must be cleared.
 midframe;ascii="R";meta[7:0]=91;toggle=0;
 nextframe; // frame 8: only fresh R appears.
 midframe;sign_mode=0;
 nextframe; // frame 9: even image_mode SIG cannot enable recognition alone.
 midframe;image_mode=3'd4;sign_mode=1;
 nextframe; // frame 10: MOT low two bits are 00; must still hide SIG overlays.
 midframe;image_mode=3'd5;
 nextframe; // frame 11: DEH likewise never enables SIG.
end
initial begin #190000000;$fatal(1,"HDMI timeout");end
endmodule
