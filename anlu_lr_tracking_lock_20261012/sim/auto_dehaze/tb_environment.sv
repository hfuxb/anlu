`timescale 1ns/1ps
module tb_environment;
reg clk=0,rst=0,v=0,u=0,l=0,force_normal=0,req=1;always #5 clk=~clk;
reg [2:0] mode=0;reg [95:0] data=0;wire enable_deh,active,manual,stat,fog;wire [7:0] contrast;
recognition_environment_96 #(.IMG_WIDTH(64),.IMG_HEIGHT(12),.CLK_HZ(1000),
 .SAMPLE_X_STEP(1),.SAMPLE_Y_STEP(1),.ENTER_MS(500),.EXIT_MS(1000),.HOLD_MS(2000),
 .ENTER_FRAMES(3),.EXIT_FRAMES(4)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tvalid(v),.I_tuser(u),.I_tlast(l),.I_tdata(data),
 .I_mode(mode),.I_recognition_request(req),.I_force_normal(force_normal),
 .O_enable_dehaze(enable_deh),.O_dehaze_active(active),.O_force_active(manual),
 .O_stats_valid(stat),.O_fog_candidate(fog),.O_contrast(contrast));
integer checks=0,stats=0,frames=0,x,y,k;reg frame_active;reg [23:0] p;
always @(negedge clk)if(stat)begin
 stats=stats+1;
 $display("stats frame=%0d fog=%b contrast=%0d next=%b active=%b enter=%0d hold=%0d",frames,fog,contrast,dut.auto_next,active,dut.enter_ticks,dut.hold_ticks);
end
task frame;
 input integer scene;input integer rows;
 begin
  for(y=0;y<rows;y=y+1)begin
   for(x=0;x<16;x=x+1)begin
    case(scene)
     0:p=24'ha0a8b0; // low contrast, low saturation, elevated dark channel
     1:p=x<8?24'h101010:24'hf0f0f0; // high contrast
     2:p=24'h080a0c; // dark is not fog
     3:p=24'h2050e0; // saturated blue is not fog
     default:p=x==3?24'hffffff:24'ha0a8b0; // >3% white: contrast rejects
    endcase
    v=1;u=x==0&&y==0;l=x==15;data={4{p}};
    @(negedge clk);
    if(x==0&&y==0)frame_active=active;
    else if(active!==frame_active)$fatal(1,"mid-frame path change");
   end
   v=0;u=0;l=0;repeat(2)@(negedge clk);
  end
  v=0;u=0;l=0;repeat(25)@(negedge clk);frames=frames+1;
 end
endtask
initial begin
 repeat(4)@(negedge clk);rst=1;
 frame(0,12);if(active)$fatal(1,"entered too early");checks=checks+1;
 frame(0,12);if(active)$fatal(1,"entered second frame");checks=checks+1;
 frame(0,12);frame(0,12);frame(0,12);if(!active)$fatal(1,"did not enter haze");checks=checks+1;
 // An isolated clear scene does not switch; HOLD blocks even persistent clear.
 frame(1,12);frame(0,12);if(!active)$fatal(1,"clear flicker");checks=checks+1;
 for(k=0;k<8;k=k+1)frame(1,12);
 frame(1,12);if(active)$fatal(1,"did not return normal after hold+exit");checks=checks+1;
 for(k=0;k<4;k=k+1)frame(2,12);if(active)$fatal(1,"dark falsely haze");checks=checks+1;
 for(k=0;k<4;k=k+1)frame(3,12);if(active)$fatal(1,"blue falsely haze");checks=checks+1;
 // Truncated frames cannot build enter evidence.
 for(k=0;k<5;k=k+1)frame(0,6);if(active)$fatal(1,"partial frame entered");checks=checks+1;
 for(k=0;k<12;k=k+1)frame(0,12);if(!active)$fatal(1,"recovery enter");checks=checks+1;
 force_normal=1;repeat(3)@(negedge clk);
 if(!active)$fatal(1,"manual changed mid-frame, must wait SOF");
 frame(0,12);if(active || !manual)$fatal(1,"manual lock failed");checks=checks+1;
 for(k=0;k<5;k=k+1)frame(0,12);if(active)$fatal(1,"manual auto override");checks=checks+1;
 force_normal=0;frame(0,12);if(active)$fatal(1,"stale evidence reused on unlock");checks=checks+1;
 for(k=0;k<4;k=k+1)frame(0,12);if(!active)$fatal(1,"AUTO return");checks=checks+1;
 mode=3;frame(0,12);if(active)$fatal(1,"RAW dehaze");checks=checks+1;
 mode=5;force_normal=1;frame(0,12);if(!active)$fatal(1,"KEY3 must not disable dedicated DEH");checks=checks+1;
 if(stats<20)$fatal(1,"missing stats");
 $display("PASS ENVIRONMENT %0d checks %0d frames %0d complete statistics: time+frame debounce, enter/exit hysteresis, hold, KEY3 SOF override, dark/color rejection, truncated-frame recovery",checks,frames,stats);$finish;
end
endmodule
