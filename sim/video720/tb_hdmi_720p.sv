`timescale 1ns/1ps
module tb_hdmi_720p;
reg clk=0, rst_n=0, result_toggle=0, traffic_mode=1, bbox_valid=1;
reg [10:0] bbox_x_min=500, bbox_x_max=520;
reg [9:0] bbox_y_min=300, bbox_y_max=320;
always #5 clk=~clk;
wire vs,hs,de,user,last,rd,ovs,ohs,ode;
wire [23:0] rgb;
uivtc #(.H_ActiveSize(1280),.H_FrameSize(1650),.H_SyncStart(1390),.H_SyncEnd(1430),
        .V_ActiveSize(720),.V_FrameSize(750),.V_SyncStart(725),.V_SyncEnd(730)) vtc(
 .I_vtc_rstn(rst_n),.I_vtc_clk(clk),.O_vtc_vs(vs),.O_vtc_hs(hs),.O_vtc_de_valid(de),.O_vtc_user(user),.O_vtc_last(last));
hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.IMG_WIDTH(1280),.IMG_HEIGHT(720)) mixer(
 .I_clk(clk),.I_rst_n(rst_n),.I_video_vsync(vs),.I_video_hsync(hs),.I_video_de(de),.I_video_user(user),.I_video_last(last),
 .I_debug_status(4'b0),.I_image_mode(2'b00),.I_traffic_sign_mode(traffic_mode),.I_traffic_sign_busy(1'b0),
 .I_traffic_sign_result_toggle(result_toggle),.I_traffic_sign_result_ascii(8'h3f),
 .I_traffic_sign_bbox_valid(bbox_valid),.I_traffic_sign_x_min(bbox_x_min),.I_traffic_sign_x_max(bbox_x_max),
 .I_traffic_sign_y_min(bbox_y_min),.I_traffic_sign_y_max(bbox_y_max),
 .O_video_rd_en(rd),.I_video_rd_data(24'h123456),.O_hdmi_vsync(ovs),.O_hdmi_hsync(ohs),.O_hdmi_de(ode),.O_hdmi_data(rgb));
integer cycles=0,pixels=0,lines=0,line_pixels=0,reads=0,frames=0,mode_pixels=0,question_pixels=0,bbox_pixels=0;
reg counting=0;
always @(negedge clk) if(rst_n) begin
 if (rd !== de) $fatal(1,"DDR read-enable mismatch");
 if(user && de) begin
  if(counting) begin
   if(cycles!=1650*750 || pixels!=1280*720 || lines!=720 || reads!=1280*720 || line_pixels!=0)
    $fatal(1,"HDMI counts cycles=%0d pixels=%0d lines=%0d reads=%0d",cycles,pixels,lines,reads);
   if(mode_pixels==0) $fatal(1,"MODE:SIG OSD produced no pixels");
   if((frames==2 && question_pixels!=0) ||
      (frames!=2 && question_pixels==0))
    $fatal(1,"DIR text did not follow SIG mode in frame %0d",frames+1);
   if((frames<2 && bbox_pixels==0) ||
      (frames>=2 && bbox_pixels!=0))
    $fatal(1,"SIG box was stale or missing in frame %0d: pixels=%0d",frames+1,bbox_pixels);
   frames=frames+1;
   if(frames==4) begin
    $display("PASS HDMI 1280x720: frame-latched SIG box, mode hiding, and stale-box clearing checked");
    $finish;
   end
  end
  counting=1; cycles=0;pixels=0;lines=0;line_pixels=0;reads=0;mode_pixels=0;question_pixels=0;bbox_pixels=0;
 end
 if(counting) begin
  if(mixer.S_x_2d>=375 && mixer.S_x_2d<503 &&
     mixer.S_y_2d>=180 && mixer.S_y_2d<204 && mixer.S_osd_hit)
   mode_pixels=mode_pixels+1;
  if(mixer.S_x_2d>=439 && mixer.S_x_2d<455 &&
     mixer.S_y_2d>=150 && mixer.S_y_2d<174 && mixer.S_osd_hit)
   question_pixels=question_pixels+1;
  if(mixer.S_x_2d>=500 && mixer.S_x_2d<=520 &&
     mixer.S_y_2d>=300 && mixer.S_y_2d<=320 &&
     mixer.S_osd_hit && mixer.S_osd_color==24'h00ff00)
   bbox_pixels=bbox_pixels+1;
  cycles=cycles+1;
  if(rd) reads=reads+1;
  if(de) begin
   pixels=pixels+1;line_pixels=line_pixels+1;
   if(last) begin
    if(line_pixels!=1280) $fatal(1,"HDMI line width=%0d",line_pixels);
    lines=lines+1;line_pixels=0;
   end
  end
 end
end
initial begin
 repeat(5) @(negedge clk); rst_n=1;
 repeat(4) @(negedge clk); result_toggle=1;
 // 依次检查有框、切出SIG清框、重新进入SIG时不保留旧框。
 wait(frames==1);
 @(negedge clk); traffic_mode=0; result_toggle=0;
 wait(frames==2);
 @(negedge clk); traffic_mode=1;
end
// 四帧约需49.5 ms，留出复位和帧首等待时间。
initial begin #100000000; $fatal(1,"HDMI simulation timeout");end
endmodule
