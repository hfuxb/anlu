`timescale 1ns/1ps
// Actual environment controller + shared dehaze + real tracking detector.
// Synthetic fog over the two user-reference sign scenes is not a field test.
module tb_auto_recognition;
reg clk=0,rst=0,v=0,u=0,l=0,force_normal=0,req=1;always #5 clk=~clk;
reg [95:0] input_rgb=0;wire pv,pu,pl,en,active,manual,stats,fog;
wire [7:0] contrast;wire [95:0] processed;
recognition_environment_96 #(.IMG_WIDTH(320),.IMG_HEIGHT(240),.CLK_HZ(1000000),
 .ENTER_MS(30),.EXIT_MS(60),.HOLD_MS(100),.ENTER_FRAMES(3),.EXIT_FRAMES(4)) env(
 .I_clk(clk),.I_rst_n(rst),.I_tvalid(v),.I_tuser(u),.I_tlast(l),.I_tdata(input_rgb),
 .I_mode(3'd0),.I_recognition_request(req),.I_force_normal(force_normal),
 .O_enable_dehaze(en),.O_dehaze_active(active),.O_force_active(manual),
 .O_stats_valid(stats),.O_fog_candidate(fog),.O_contrast(contrast));
dehaze_stream_96 #(.IMG_WIDTH(320),.IMG_HEIGHT(240)) deh(
 .I_clk(clk),.I_rst_n(rst),.I_tvalid(v),.I_tuser(u),.I_tlast(l),.I_tdata(input_rgb),.I_enable(en),
 .O_tvalid(pv),.O_tuser(pu),.O_tlast(pl),.O_tdata(processed));
wire enabled,busy,done,ok,box,drop;wire [7:0] ascii,score;wire [4:0] cls;
wire [10:0] x0,x1;wire [9:0] y0,y1;
traffic_sign_sig_only_96 #(.IMG_WIDTH(320),.IMG_HEIGHT(240)) detector(
 .I_clk(clk),.I_rst_n(rst),.I_tvalid(pv),.I_tuser(pu),.I_tlast(pl),.I_tdata(processed),
 .I_algo_mode(2'd0),.I_recognition_request(req),.O_enabled(enabled),.O_busy(busy),
 .O_done(done),.O_result_valid(ok),.O_result_ascii(ascii),.O_result_class(cls),.O_box_valid(box),
 .O_score(score),.O_x_min(x0),.O_x_max(x1),.O_y_min(y0),.O_y_max(y1),.O_frame_drop(drop));
reg [95:0] image[0:19199];integer frames=0,results=0,checks=0,x,y,p,c,f;reg [95:0] word;
always @(negedge clk)begin
 if(drop)$fatal(1,"auto detector frame drop");
 if(done)begin results=results+1;$display("auto result=%c score=%0d active=%b fresh=%b",ascii,score,active,detector.u_detector.accept_result);end
end
task frame(input integer haze);
 begin
  for(y=0;y<240;y=y+1)begin
   for(x=0;x<80;x=x+1)begin
    word=image[y*80+x];
    if(haze)for(p=0;p<4;p=p+1)for(c=0;c<3;c=c+1)
     word[p*24+c*8+:8]=(word[p*24+c*8+:8]*3+240*7+5)/10;
    @(negedge clk);input_rgb=word;v=1;u=x==0&&y==0;l=x==79;
    if(x%17==8)begin @(negedge clk);v=0;u=0;l=0;end
   end
   @(negedge clk);v=0;u=0;l=0;repeat(12)@(negedge clk);
  end
  repeat(1000)@(negedge clk);frames=frames+1;
 end
endtask
task case_run(input string file_name,input [7:0] direction);
 begin
  $readmemh(file_name,image);rst=0;v=0;u=0;l=0;force_normal=0;
  repeat(4)@(negedge clk);rst=1;repeat(300)@(negedge clk);
  for(f=0;f<6;f=f+1)frame(0);
  if(active || ascii!==direction || !ok || score<50)$fatal(1,"clear normal path failed %c/%0d",ascii,score);checks=checks+1;
  for(f=0;f<9;f=f+1)frame(1);
  if(!active || ascii!==direction || !ok || score<50 || !detector.u_detector.accept_result)
   $fatal(1,"auto haze path did not freshly recognize %c score=%0d active=%b contrast=%0d",ascii,score,active,contrast);checks=checks+1;
  force_normal=1;frame(1);if(active || !manual)$fatal(1,"force normal routing");checks=checks+1;
  force_normal=0;for(f=0;f<7;f=f+1)frame(1);
  if(!active || ascii!==direction || score<50)$fatal(1,"AUTO return failed");checks=checks+1;
  for(f=0;f<9;f=f+1)frame(0);
  if(active || ascii!==direction || !ok || score<50)$fatal(1,"clear return failed");checks=checks+1;
 end
endtask
initial begin
 case_run("../../../lr_turn/left120.hex","L");
 case_run("../../../lr_turn/right160.hex","R");
 if(results<50)$fatal(1,"result completions missing");
 $display("PASS AUTO RECOGNITION %0d checks %0d frames %0d results: real reference L/R, synthetic haze automatic enter/recover, clear return, KEY3 lock, no new detector/held-MATCH decision",checks,frames,results);$finish;
end
initial begin #25000000;$fatal(1,"auto timeout");end
endmodule
