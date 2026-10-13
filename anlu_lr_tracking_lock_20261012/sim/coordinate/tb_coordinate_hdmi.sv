`timescale 1ns/1ps
module tb_coordinate_hdmi;
reg clk=0,rst=0,toggle=0;
always #5 clk=~clk;
wire vs,hs,de,user,last,rd,ovs,ohs,ode;
wire [23:0] rgb;
reg [2:0] image_mode=3'd3;
reg sign_mode=0;
reg [7:0] ascii="L";
reg [50:0] meta={1'b1,11'd600,11'd679,10'd350,10'd429,8'd85};
uivtc #(.H_ActiveSize(1280),.H_FrameSize(1650),.H_SyncStart(1390),.H_SyncEnd(1430),
.V_ActiveSize(720),.V_FrameSize(750),.V_SyncStart(725),.V_SyncEnd(730)) vtc(
.I_vtc_rstn(rst),.I_vtc_clk(clk),.O_vtc_vs(vs),.O_vtc_hs(hs),.O_vtc_de_valid(de),.O_vtc_user(user),.O_vtc_last(last));
reg [11:0] ix=0,iy=0;
wire [23:0] pattern={iy,ix};
always @(posedge clk)begin
 if(!rst || user)begin ix<=0;iy<=0;end
 else if(de)begin if(last)begin ix<=0;iy<=iy+1;end else ix<=ix+1;end
end
hdmi_mixer mixer(.I_clk(clk),.I_rst_n(rst),.I_video_vsync(vs),.I_video_hsync(hs),
.I_video_de(de),.I_video_user(user),.I_video_last(last),.I_debug_status(4'd0),.I_image_mode(image_mode),
.I_traffic_sign_mode(sign_mode),.I_traffic_sign_busy(1'b0),.I_traffic_sign_result_toggle(toggle),
.I_traffic_sign_result_ascii(ascii),.I_traffic_sign_metadata(meta),.I_latency_bcd(20'd0),
.I_latency_valid(1'b0),.I_latency_overflow(1'b0),.I_latency_update(1'b0),.O_video_rd_en(rd),
.I_video_rd_data(pattern),.O_hdmi_vsync(ovs),.O_hdmi_hsync(ohs),.O_hdmi_de(ode),.O_hdmi_data(rgb));
reg [23:0] expected0=0,expected1=0,expected2=0;
reg [11:0] ex0=0,ex1=0,ex2=0,ey0=0,ey1=0,ey2=0;
reg ev0=0,ev1=0,ev2=0,vs0=0,vs1=0,vs2=0,hs0=0,hs1=0,hs2=0;
always @(posedge clk)begin
 expected0<=pattern;expected1<=expected0;expected2<=expected1;
 ex0<=ix;ex1<=ex0;ex2<=ex1;ey0<=iy;ey1<=ey0;ey2<=ey1;
 ev0<=de;ev1<=ev0;ev2<=ev1;vs0<=vs;vs1<=vs0;vs2<=vs1;hs0<=hs;hs1<=hs0;hs2<=hs1;
end
wire [14:0] golden_logo_addr=(ex2<160 && ey2<160)?ey2*160+ex2:15'd0;
wire [24:0] golden_logo_pixel;
anlogic_logo_rom golden_logo(.I_addr(golden_logo_addr),.O_pixel(golden_logo_pixel));
integer frames=-1,pixels=0,label_pixels=0,total_labels=0,checks=0;
reg started=0;
reg expect_label,expect_box,expect_sign;
integer bx0,bx1,by0,by1,cx,cy,lx,ly;
reg [7:0] direction;
reg [2:0] mode;
always @* begin
 expect_sign=(frames>=1 && frames<=8)||(frames>=11 && frames<=13);
 expect_box=(frames>=2 && frames<=6)||frames==8||frames==12||frames==13;
 expect_label=(frames>=2 && frames<=4)||frames==6||frames==8||frames==12||frames==13;
 bx0=600;bx1=679;by0=350;by1=429;cx=639;cy=389;lx=600;ly=328;direction="L";mode=0;
 case(frames)
  0,9:begin mode=3;direction="?";end
  1,11:direction="?";
  4:begin bx0=1170;bx1=1279;by0=20;by1=129;cx=1224;cy=74;lx=1072;ly=22;direction="R";end
  5:begin bx0=700;bx1=879;by0=350;by1=529;direction="?";end
  6:begin bx0=20;bx1=119;by0=2;by1=101;cx=69;cy=51;lx=160;ly=4;direction="R";end
  7:direction="L";
  8:begin bx0=1100;bx1=1279;by0=650;by1=719;cx=1189;cy=684;lx=1072;ly=628;direction="R";end
  10:begin mode=5;expect_sign=0;direction="?";end
  12,13:begin bx0=400;bx1=499;by0=150;by1=249;cx=449;cy=199;lx=591;ly=128;direction="R";end
 endcase
end
// Independent glyph reference checks every foreground and background pixel,
// including numeric values/leading zeros, punctuation and uniform glyph size.
function automatic [15:0] glyph(input [7:0] ch,input integer row);
 integer pair;
 begin
  pair=(row-1)/2;glyph=0;
  if(row>=1 && row<=14)case(ch)
   "L":case(pair)0,1,2,3,4,5:glyph=16'h1800;6:glyph=16'h1ff8;endcase
   "R":case(pair)0,3:glyph=16'h1fe0;1,2,6:glyph=16'h1818;4:glyph=16'h1980;5:glyph=16'h1860;endcase
   "0":case(pair)0,6:glyph=16'h07e0;1,5:glyph=16'h1818;2:glyph=16'h1878;3:glyph=16'h1998;4:glyph=16'h1e18;endcase
   "1":case(pair)0,2,3,4,5:glyph=16'h0180;1:glyph=16'h0780;6:glyph=16'h07e0;endcase
   "2":case(pair)0:glyph=16'h07e0;1:glyph=16'h1818;2:glyph=16'h0018;3:glyph=16'h0060;4:glyph=16'h0180;5:glyph=16'h0600;6:glyph=16'h1ff8;endcase
   "3":case(pair)0,6:glyph=16'h1fe0;1,2,4,5:glyph=16'h0018;3:glyph=16'h07e0;endcase
   "4":case(pair)0,5,6:glyph=16'h0060;1:glyph=16'h01e0;2:glyph=16'h0660;3:glyph=16'h1860;4:glyph=16'h1ff8;endcase
   "5":case(pair)0:glyph=16'h1ff8;1,2:glyph=16'h1800;3,6:glyph=16'h1fe0;4,5:glyph=16'h0018;endcase
   "6":case(pair)0,6:glyph=16'h07e0;1,2:glyph=16'h1800;3:glyph=16'h1fe0;4,5:glyph=16'h1818;endcase
   "7":case(pair)0:glyph=16'h1ff8;1:glyph=16'h0018;2:glyph=16'h0060;3:glyph=16'h0180;4,5,6:glyph=16'h0600;endcase
   "8":case(pair)0,3,6:glyph=16'h07e0;1,2,4,5:glyph=16'h1818;endcase
   "9":case(pair)0,6:glyph=16'h07e0;1,2:glyph=16'h1818;3:glyph=16'h07f8;4,5:glyph=16'h0018;endcase
   "(":case(pair)0,6:glyph=16'h0180;1,5:glyph=16'h0600;2,3,4:glyph=16'h1800;endcase
   ")":case(pair)0,6:glyph=16'h0600;1,5:glyph=16'h0180;2,3,4:glyph=16'h0060;endcase
   ",":case(pair)5:glyph=16'h0180;6:glyph=16'h0600;endcase
  endcase
 end
endfunction
function automatic [7:0] label_char(input integer char_cell,input integer x,input integer y,input [7:0] d);
 begin
  case(char_cell)
   0:label_char=d;1:label_char=" ";2:label_char="(";
   3:label_char="0"+x/1000;4:label_char="0"+(x/100)%10;
   5:label_char="0"+(x/10)%10;6:label_char="0"+x%10;
   7:label_char=",";
   8:label_char="0"+y/1000;9:label_char="0"+(y/100)%10;
   10:label_char="0"+(y/10)%10;11:label_char="0"+y%10;
   12:label_char=")";default:label_char=" ";
  endcase
 end
endfunction
reg [15:0] golden_glyph;
reg [23:0] golden_rgb;
integer local_x,local_y;
always @(negedge clk)if(rst)begin
 if(rd!==de)$fatal(1,"DDR read enable changed");
 if(started && (ode!==ev2 || ovs!==vs2 || ohs!==hs2))$fatal(1,"video timing latency changed");
 if(user && de)begin
  if(started)begin
   if(pixels!=921600)$fatal(1,"frame %0d pixel count %0d",frames,pixels);
   if(expect_label && label_pixels!=4160)$fatal(1,"missing/incomplete coordinate background");
   if(!expect_label && label_pixels!=0)$fatal(1,"coordinate appeared without accepted L/R");
   $display("COORD FRAME %0d mode=%0d dir=%c box=%0d label=%0d center=(%0d,%0d)",frames,mode,direction,expect_box,expect_label,cx,cy);
   checks=checks+1;frames=frames+1;
   if(frames==14)begin $display("PASS COORDINATE HDMI: 14 full720 frames, %0d checked label pixels, SIG-only L/R, candidate/no-box hidden, held tracking, clamping, OSD avoidance, coherent center/direction, unchanged RGB/DE/sync",total_labels);$finish;end
  end
  started=1;pixels=0;label_pixels=0;
 end
 if(started && ode)begin
  pixels=pixels+1;
  if(mixer.S_image_mode_frame!==mode || mixer.S_sign_ascii_frame!==direction || mixer.S_sign_box!==expect_box)
   $fatal(1,"metadata epoch/coherence error frame %0d actualmode=%0d dir=%c box=%b expectedmode=%0d dir=%c box=%b user=%b x=%0d y=%0d",frames,mixer.S_image_mode_frame,mixer.S_sign_ascii_frame,mixer.S_sign_box,mode,direction,expect_box,user,ex2,ey2);
  if(expect_label && ex2>=lx && ex2<lx+208 && ey2>=ly && ey2<ly+20)begin
   local_x=ex2-lx;local_y=ey2-ly;
   golden_glyph=glyph(label_char(local_x/16,cx,cy,direction),local_y-2);
   golden_rgb=24'h20ff40;
   if(local_y>=2 && local_y<18 && golden_glyph[15-local_x%16])golden_rgb=24'h101820;
   if(rgb!==golden_rgb)$fatal(1,"coordinate pixel frame=%0d x=%0d y=%0d actual=%h expected=%h char=%c",frames,ex2,ey2,rgb,golden_rgb,label_char(local_x/16,cx,cy,direction));
   label_pixels=label_pixels+1;total_labels=total_labels+1;
  end else if(expect_box && ex2>=bx0 && ex2<=bx1 && ey2>=by0 && ey2<=by1 &&
     !(ex2>=375 && ex2<591 && ey2>=120 && ey2<240) &&
     (ex2<bx0+2 || ex2+2>bx1 || ey2<by0+2 || ey2+2>by1))begin
   if(rgb!==(direction=="L"||direction=="R"?24'h20ff40:24'hfff200))$fatal(1,"ROI border changed at x=%0d y=%0d frame=%0d",ex2,ey2,frames);
  end else if(ex2<160 && ey2<160)begin
   if(golden_logo_pixel[24])begin if(rgb!==golden_logo_pixel[23:0])$fatal(1,"logo changed");end
   else if(rgb!==expected2)$fatal(1,"RGB behind logo shifted");
  end else if(ex2>=375 && ex2<591 && ey2>=120 && ey2<240)begin
   // Existing count/mode/DIR/MATCH font separately checked by tb_lr_hdmi.
  end else if(rgb!==expected2)$fatal(1,"RGB/coordinate leak x=%0d y=%0d frame=%0d expected=%h actual=%h",ex2,ey2,frames,expected2,rgb);
 end
end
task midframe;begin wait(iy==400 && ix==0);@(negedge clk);end endtask
task nextframe;begin @(posedge user);repeat(3)@(negedge clk);end endtask
task result(input [7:0] a,input box,input integer x0,input integer x1,input integer y0,input integer y1,input integer score);
 begin ascii=a;meta={box,11'(x0),11'(x1),10'(y0),10'(y1),8'(score)};toggle=~toggle;end
endtask
initial begin
 #1;frames=0;
 repeat(5)@(negedge clk);rst=1;
 nextframe;midframe;image_mode=0;sign_mode=1;toggle=1;
 nextframe;midframe;result("L",1,600,679,350,429,85);
 nextframe;midframe;meta[7:0]=38; // held L/R remains labelled despite lower score
 nextframe;midframe;result("R",1,1170,1279,20,129,93);
 nextframe;midframe;result("?",1,700,879,350,529,43);
 nextframe;midframe;result("R",1,20,119,2,101,84);
 nextframe;midframe;result("L",0,600,679,350,429,88);
 nextframe;midframe;result("R",1,1100,1279,650,719,92);
 nextframe;midframe;image_mode=3;sign_mode=0;
 nextframe;midframe;image_mode=5;sign_mode=1;
 nextframe;midframe;image_mode=0;
 nextframe;midframe;result("R",1,400,499,150,249,82);
 nextframe;midframe;meta[7:0]=22;
end
initial begin #190000000;$fatal(1,"coordinate HDMI timeout");end
endmodule
