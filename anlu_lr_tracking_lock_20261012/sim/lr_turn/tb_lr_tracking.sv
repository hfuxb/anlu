`timescale 1ns/1ps
module tb_lr_tracking;
reg clk=0; always #5 clk=~clk;
reg rst=0,user=0,last=0,valid=0;
reg [95:0] data=0;
wire busy,done,ok,drop,box;
wire [4:0] cls;
wire [7:0] ascii,score;
wire [10:0] x0,x1;
wire [9:0] y0,y1;
traffic_sign_detector_96 #(.IMG_WIDTH(640),.IMG_HEIGHT(360)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tuser(user),.I_tlast(last),.I_tvalid(valid),.I_tdata(data),
 .O_busy(busy),.O_done(done),.O_result_valid(ok),.O_result_class(cls),.O_result_ascii(ascii),
 .O_frame_drop(drop),.O_box_valid(box),.O_x_min(x0),.O_x_max(x1),.O_y_min(y0),.O_y_max(y1),.O_score(score));
reg [95:0] image[0:57599];
integer done_count=0,checks=0;
reg [41:0] saved_box;
always @(posedge clk)begin
 if(drop)$fatal(1,"frame dropped");
 if(done)begin
  done_count=done_count+1;
  $display("frame=%0d ascii=%c locked=%0d score=%0d box=%0d x=%0d..%0d missing=%0d vote=%0d",done_count,ascii,dut.locked,score,box,x0,x1,dut.missing_count,dut.vote_count);
 end
end
task reset_core;
begin
 valid=0;user=0;last=0;rst=0;repeat(4)@(negedge clk);
 rst=1;repeat(300)@(negedge clk);
end endtask
task frame(input string filename,input [7:0] expected,input expected_box);
integer x,y,previous;
begin
 $display("SCENE %s expected %c",filename,expected);
 $readmemh(filename,image);previous=done_count;
 for(y=0;y<360;y=y+1)begin
  for(x=0;x<160;x=x+1)begin
   @(negedge clk);valid=1;user=(x==0 && y==0);last=(x==159);data=image[y*160+x];
   if(x%17==8)begin @(negedge clk);valid=0;user=0;last=0;end
  end
  @(negedge clk);valid=0;user=0;last=0;repeat(12)@(negedge clk);
 end
 repeat(1000)@(negedge clk);
 checks=checks+1;
 if(done_count!=previous+1)$fatal(1,"completion count wrong");
 if(ascii!==expected || box!==expected_box)$fatal(1,"expected %c box=%0d got %c box=%0d",expected,expected_box,ascii,box);
 if(expected=="L" && (!ok || cls!==1))$fatal(1,"left command/class not stable");
 if(expected=="R" && (!ok || cls!==2))$fatal(1,"right command/class not stable");
 if(expected=="?" && (ok || cls!==0))$fatal(1,"unconfirmed direction published");
end endtask
integer n;
initial begin
 reset_core;
 frame("../tracking/left.hex","?",1);
 frame("../tracking/left.hex","?",1);
 frame("../tracking/left.hex","?",1);
 frame("../tracking/left.hex","L",1);
 frame("../tracking/left_moved.hex","L",1);
 if(x0<52 || x0>64)$fatal(1,"box failed to follow movement");
 frame("../tracking/no_arrow.hex","L",1);
 if(score>=50)$fatal(1,"low-confidence test did not lower score");
 frame("../tracking/opposite_in_lock.hex","L",1);
 if(dut.score_r<=dut.score_l)$fatal(1,"opposite-label test not exercised");
 frame("../tracking/two_signs.hex","L",1);
 if(x0>100)$fatal(1,"distant larger candidate stole target");
 saved_box={x0,x1,y0,y1};
 frame("../tracking/only_distractor.hex","L",1);
 if({x0,x1,y0,y1}!==saved_box)$fatal(1,"unrelated target replaced held box");
 frame("../tracking/blank.hex","L",1);
 frame("../tracking/blank.hex","L",1);
 frame("../tracking/left_return.hex","L",1);
 if(dut.missing_count!=0)$fatal(1,"recovery did not clear loss count");
 for(n=0;n<7;n=n+1)begin
  frame("../tracking/blank.hex","L",1);
 end
 frame("../tracking/blank.hex","?",0);
 if(dut.locked)$fatal(1,"persistent loss failed to unlock");
 frame("../tracking/right_new.hex","?",1);
 frame("../tracking/right_new.hex","?",1);
 frame("../tracking/right_new.hex","?",1);
 frame("../tracking/right_new.hex","R",1);
 reset_core;
 frame("../tracking/blank.hex","?",0);
 // Alternating credible L/R at the same position must not pass confirmation.
 frame("../tracking/left.hex","?",1);
 frame("../tracking/right_same_position.hex","?",1);
 if(dut.vote_count!=1 || dut.vote_ascii!=="R")$fatal(1,"credible right vote was not exercised");
 frame("../tracking/left.hex","?",1);
 if(dut.vote_count!=1 || dut.vote_ascii!=="L")$fatal(1,"direction change failed to reset confirmation");
 frame("../tracking/right_same_position.hex","?",1);
 if(dut.locked)$fatal(1,"alternating votes incorrectly locked");
 $display("PASS LR tracking lock %0d frames: confirm / low score / opposite direction / movement / distractor / short loss / expiry / rearm / reset",checks);
 $finish;
end
initial begin #100000000;$fatal(1,"tracking timeout");end
endmodule
