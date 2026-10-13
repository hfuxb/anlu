`timescale 1ns/1ps
module tb_coordinate_latch;
reg clk=0,rst=0,user=0,toggle=0,sign_mode=0;
reg [2:0] mode=3;
reg [7:0] ascii="?";
reg [50:0] meta=0;
wire [23:0] rgb;
always #5 clk=~clk;
hdmi_mixer #(.ENABLE_LATENCY(1),.HDMI_CLK_HZ(1000),.LATENCY_REFRESH_MS(1000)) dut(
.I_clk(clk),.I_rst_n(rst),.I_video_vsync(1'b0),.I_video_hsync(1'b0),.I_video_de(1'b0),
.I_video_user(user),.I_video_last(1'b0),.I_debug_status(4'd0),.I_image_mode(mode),
.I_traffic_sign_mode(sign_mode),.I_traffic_sign_busy(1'b0),.I_traffic_sign_result_toggle(toggle),
.I_traffic_sign_result_ascii(ascii),.I_traffic_sign_metadata(meta),.I_latency_bcd(20'd0),
.I_latency_valid(1'b0),.I_latency_overflow(1'b0),.I_latency_update(1'b0),
.O_video_rd_en(),.I_video_rd_data(24'd0),.O_hdmi_vsync(),.O_hdmi_hsync(),.O_hdmi_de(),.O_hdmi_data(rgb));
integer checks=0;
function automatic [15:0] bcd(input integer value);
 begin bcd={(4'(value/1000)),(4'((value/100)%10)),(4'((value/10)%10)),(4'(value%10))};end
endfunction
task frame;begin @(negedge clk);user=1;@(negedge clk);user=0;repeat(12)@(negedge clk);end endtask
task packet(input [7:0] a,input present,input integer x0,input integer x1,input integer y0,input integer y1);
 begin @(negedge clk);ascii=a;meta={present,11'(x0),11'(x1),10'(y0),10'(y1),8'd82};toggle=~toggle;repeat(5)@(negedge clk);frame;end
endtask
task expect_label(input integer cx,input integer cy,input integer lx,input integer ly);
 begin
  if(!dut.S_coord_ready || dut.S_coord_bcd_x!==bcd(cx) || dut.S_coord_bcd_y!==bcd(cy) ||
     dut.S_coord_label_x!==lx || dut.S_coord_label_y!==ly)$fatal(1,"coordinate latch expected=(%0d,%0d) pos=(%0d,%0d) actual=%h/%h %0d/%0d ready=%b",cx,cy,lx,ly,dut.S_coord_bcd_x,dut.S_coord_bcd_y,dut.S_coord_label_x,dut.S_coord_label_y,dut.S_coord_ready);
  checks=checks+1;
 end
endtask
initial begin
 repeat(4)@(negedge clk);rst=1;
 mode=0;sign_mode=1;repeat(5)@(negedge clk);frame;
 if(dut.S_coord_ready)$fatal(1,"stale entry label");checks=checks+1;
 packet("L",1,600,679,350,429);expect_label(639,389,600,328);
 // Input changes in mid-frame cannot alter coordinate digits or direction.
 ascii="R";meta={1'b1,11'd1170,11'd1279,10'd20,10'd129,8'd82};
 repeat(50)@(negedge clk);expect_label(639,389,600,328);
 if(dut.S_sign_ascii_frame!=="L")$fatal(1,"label direction changed inside frame");checks=checks+1;
 frame;expect_label(1224,74,856,22); // right-top label moves left of the LAT panel
 packet("R",1,0,100,0,100);expect_label(50,50,160,2); // protect 160x160 logo
 packet("L",1,400,499,150,249);expect_label(449,199,591,128); // protect fixed status
 packet("R",1,1100,1279,650,719);expect_label(1189,684,1072,628);
 packet("?",1,600,679,350,429);
 if(dut.S_coord_ready || !dut.S_sign_box)$fatal(1,"candidate should have box but no coordinate");checks=checks+1;
 packet("L",0,600,679,350,429);
 if(dut.S_coord_ready)$fatal(1,"no-box label");checks=checks+1;
 packet("L",1,600,679,350,429);expect_label(639,389,600,328);
 mode=3;sign_mode=0;repeat(5)@(negedge clk);frame;
 if(dut.S_coord_ready || dut.S_sign_box)$fatal(1,"mode exit leaked coordinates");checks=checks+1;
 mode=0;sign_mode=1;repeat(5)@(negedge clk);frame;
 if(dut.S_coord_ready || dut.S_sign_box)$fatal(1,"mode re-entry reused old coordinates");checks=checks+1;
 packet("R",1,700,879,350,529);expect_label(789,439,700,328);
 $display("PASS COORDINATE LATCH: %0d checks, LAT/logo/status avoidance, atomic frame metadata, decimal center, edge clamp, candidate/no-box and mode epoch clearing",checks);$finish;
end
initial begin #100000;$fatal(1,"coordinate latch timeout");end
endmodule
