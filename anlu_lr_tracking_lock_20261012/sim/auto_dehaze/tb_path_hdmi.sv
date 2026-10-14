`timescale 1ns/1ps
module tb_path_hdmi;
reg clk=0,rst=0;always #5 clk=~clk;
wire vs,hs,de,user,last,rd,ovs,ohs,ode;wire [23:0] rgb;
reg [1:0] path=0;reg [2:0] mode=0;reg sign_mode=1;
uivtc #(.H_ActiveSize(1280),.H_FrameSize(1650),.H_SyncStart(1390),.H_SyncEnd(1430),
 .V_ActiveSize(720),.V_FrameSize(750),.V_SyncStart(725),.V_SyncEnd(730)) vtc(
 .I_vtc_rstn(rst),.I_vtc_clk(clk),.O_vtc_vs(vs),.O_vtc_hs(hs),.O_vtc_de_valid(de),.O_vtc_user(user),.O_vtc_last(last));
reg [11:0] ix=0,iy=0;
wire [23:0] pattern={iy,ix};
always @(posedge clk)begin
 if(!rst || user)begin ix<=0;iy<=0;end
 else if(de)begin if(last)begin ix<=0;iy<=iy+1;end else ix<=ix+1;end
end
hdmi_mixer #(.ENABLE_PATH(1)) dut(.I_clk(clk),.I_rst_n(rst),.I_video_vsync(vs),.I_video_hsync(hs),
 .I_video_de(de),.I_video_user(user),.I_video_last(last),.I_debug_status(0),.I_image_mode(mode),
 .I_recognition_path(path),.I_traffic_sign_mode(sign_mode),.I_traffic_sign_busy(0),
 .I_traffic_sign_result_toggle(0),.I_traffic_sign_result_ascii("?"),.I_traffic_sign_metadata(0),
 .O_video_rd_en(rd),.I_video_rd_data(pattern),.O_hdmi_vsync(ovs),.O_hdmi_hsync(ohs),.O_hdmi_de(ode),.O_hdmi_data(rgb));
reg [11:0] x0=0,x1=0,x2=0,y0=0,y1=0,y2=0;
reg [23:0] p0=0,p1=0,p2=0;reg dv0=0,dv1=0,dv2=0;
always @(posedge clk)begin
 x0<=ix;x1<=x0;x2<=x1;y0<=iy;y1<=y0;y2<=y1;
 p0<=pattern;p1<=p0;p2<=p1;dv0<=de;dv1<=dv0;dv2<=dv1;
end
integer frames=0,count=0,hits=0,pixels=0;reg started=0;
reg [7:0] ch;wire [15:0] bits;
wire [11:0] lx=x2-375;wire [3:0] row=y2-248;
always @*begin
 case(lx[7:4])
 0:ch="P";1:ch="A";2:ch="T";3:ch="H";4:ch=8'h3a;
 5:ch=frames==1?"D":"N";6:ch=" ";
 7:ch=frames==2?"L":"A";8:ch=frames==2?"O":"U";
 9:ch=frames==2?"C":"T";10:ch=frames==2?"K":"O";default:ch=" ";
 endcase
end
osd_char_lib reference_font(.I_char(ch),.I_row(row),.O_row_bits(bits));
always @(negedge clk)if(rst)begin
 if(rd!==de)$fatal(1,"extra reads");
 if(user&&de)begin
  if(started)begin
   if(pixels!=921600)$fatal(1,"pixel count");
   frames=frames+1;pixels=0;
   if(frames==4)begin
    if(count!=16896 || hits<300)$fatal(1,"path missing checks %0d hits %0d",count,hits);
    $display("PASS PATH HDMI four full720 frames: %0d independently checked pixels, N/D/AUTO/LOCK glyphs, midframe latch, hidden outside SIG, unchanged DDR read/DE",count);$finish;
   end
  end
  started=1;
 end
 if(started&&ode)begin
  pixels=pixels+1;if(ode!==dv2)$fatal(1,"DE shifted");
  if(x2>=375&&x2<551&&y2>=244&&y2<268)begin
   count=count+1;
   if(frames<3&&y2>=248&&y2<264&&bits[15-lx[3:0]])begin
    if(rgb!==24'hfff200)$fatal(1,"PATH glyph/color wrong frame=%0d x=%0d y=%0d actual=%h",frames,x2,y2,rgb);
    hits=hits+1;
   end else if(rgb!==p2)$fatal(1,"PATH RGB shift/leak frame=%0d x=%0d y=%0d",frames,x2,y2);
  end
 end
end
task next_frame;begin @(posedge user);repeat(3)@(negedge clk);end endtask
task middle;begin wait(iy==400&&ix==0);@(negedge clk);end endtask
initial begin
 repeat(5)@(negedge clk);rst=1;
 next_frame;middle;path=1;
 next_frame;middle;path=2;
 next_frame;middle;path=0;mode=3;sign_mode=0;
end
initial begin #100000000;$fatal(1,"path timeout");end
endmodule
