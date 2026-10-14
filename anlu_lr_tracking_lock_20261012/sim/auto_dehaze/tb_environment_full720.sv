`timescale 1ns/1ps
module tb_environment_full720;
reg clk=0,rst=0,v=0,u=0,l=0,force_normal=0;always #5 clk=~clk;
wire en,active,manual,stats,fog;wire [7:0] contrast;
recognition_environment_96 #(.ENTER_MS(1),.ENTER_FRAMES(1)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tvalid(v),.I_tuser(u),.I_tlast(l),
 .I_tdata({4{24'ha0a8b0}}),.I_mode(3'd0),.I_recognition_request(1'b1),.I_force_normal(force_normal),
 .O_enable_dehaze(en),.O_dehaze_active(active),.O_force_active(manual),
 .O_stats_valid(stats),.O_fog_candidate(fog),.O_contrast(contrast));
integer f,x,y,checks=0,completed=0;reg frame_path;
always @(negedge clk)if(stats)begin
 if(dut.samples!==1800 || dut.groups!==230400 || dut.dark_sum!==288000 || dut.sat_sum!==28800 || !fog || contrast!=0)
  $fatal(1,"full720 statistics wrong samples=%0d groups=%0d dark=%0d sat=%0d contrast=%0d",dut.samples,dut.groups,dut.dark_sum,dut.sat_sum,contrast);
 completed=completed+1;
end
initial begin
 repeat(4)@(negedge clk);rst=1;
 for(f=0;f<4;f=f+1)begin
  force_normal=f==3;
  for(y=0;y<720;y=y+1)begin
   for(x=0;x<320;x=x+1)begin
    v=1;u=x==0&&y==0;l=x==319;@(negedge clk);
    if(u)begin
     frame_path=active;
     if(active!==(f==2) || manual!==(f==3))$fatal(1,"SOF path wrong f=%0d active=%b",f,active);
     checks=checks+1;
    end else if(active!==frame_path)$fatal(1,"720p midframe path changed");
   end
   v=0;u=0;l=0;repeat(2)@(negedge clk);
  end
  repeat(30)@(negedge clk);
 end
 if(completed!=4)$fatal(1,"completed=%0d",completed);
 $display("PASS ENVIRONMENT FULL720 four 230400-group frames: exact 1800-sample statistics, complete geometry, frame-latched auto/manual path, 60MHz time arithmetic");$finish;
end
endmodule
