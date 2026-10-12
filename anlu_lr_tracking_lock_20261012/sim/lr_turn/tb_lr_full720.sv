`timescale 1ns/1ps
module tb_lr_full720;
reg clk=0; always #5 clk=~clk;
reg rst=0,user=0,last=0,valid=0;
reg [95:0] data=0;
wire busy,done,ok,drop,box;
wire [4:0] cls;
wire [7:0] ascii,score;
wire [10:0] x0,x1;
wire [9:0] y0,y1;
traffic_sign_detector_96 #(.IMG_WIDTH(1280),.IMG_HEIGHT(720)) dut(
.I_clk(clk),.I_rst_n(rst),.I_tuser(user),.I_tlast(last),.I_tvalid(valid),.I_tdata(data),
.O_busy(busy),.O_done(done),.O_result_valid(ok),.O_result_class(cls),.O_result_ascii(ascii),
.O_frame_drop(drop),.O_box_valid(box),.O_x_min(x0),.O_x_max(x1),.O_y_min(y0),.O_y_max(y1),.O_score(score));
reg [95:0] image[0:230399];
integer done_count=0,errors=0;
always @(posedge clk)begin
 if(done)begin
 done_count=done_count+1;
 $display("result %c score=%0d L=%0d R=%0d box=%0d,%0d,%0d,%0d white=%0d",ascii,score,dut.score_l,dut.score_r,x0,x1,y0,y1,dut.white_cells);
 end
 if(drop)$fatal(1,"unexpected frame drop");
end
task run_case(input string filename,input [7:0] expected);
integer f,x,y,prev_done;
begin
 $display("CASE %s",filename);
 $readmemh(filename,image);
 rst=0; repeat(4)@(negedge clk);rst=1;repeat(300)@(negedge clk);
 prev_done=done_count;
 for(f=0;f<5;f=f+1)begin
  for(y=0;y<720;y=y+1)begin
   for(x=0;x<320;x=x+1)begin
    @(negedge clk);valid=1;user=(x==0 && y==0);last=(x==319);data=image[y*320+x];
    // Exercise gaps inside each sampled row and RMW forwarding.
    if(x%17==8)begin @(negedge clk);valid=0;user=0;last=0;end
   end
   @(negedge clk);valid=0;user=0;last=0;
   repeat(12)@(negedge clk);
  end
  repeat(1000)@(negedge clk);
 end
 if(done_count-prev_done!=5)$fatal(1,"incorrect frame completion count");
 if(ascii!==expected)begin errors=errors+1;$display("FAIL expected %c got %c",expected,ascii);end
 if(expected!="?" && (!box || !ok || score<50))$fatal(1,"missing accepted ROI");
end endtask
initial begin
 run_case("../right_full720.hex",8'h52);
 if(errors)$fatal(1,"%0d LR failures",errors);
 $display("PASS LR real-sign image scenes / rejection / RMW gaps");$finish;
end
initial begin #50000000;$fatal(1,"timeout");end
endmodule

