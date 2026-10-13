`timescale 1ns/1ps
`include "count.vh"
module tb_extra_modes;
reg clk=0,rst=0;always #5 clk=~clk;
reg [101:0] sample=0;
reg [101:0] inputs[0:`EXTRA_CYCLES-1];
reg [98:0] expected[0:`EXTRA_CYCLES-1];
wire valid,user,last;wire [95:0] data;
image_extra_modes_96 #(.IMG_WIDTH(64),.IMG_HEIGHT(12)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tvalid(sample[101]),.I_tuser(sample[100]),.I_tlast(sample[99]),
 .I_mode(sample[98:96]),.I_tdata(sample[95:0]),.O_tvalid(valid),.O_tuser(user),.O_tlast(last),.O_tdata(data));
integer n,count=0;
initial begin
 $readmemh("input.hex",inputs);$readmemh("expected.hex",expected);
 repeat(4)@(negedge clk);rst=1;
 for(n=0;n<`EXTRA_CYCLES;n=n+1)begin
  sample=inputs[n];@(posedge clk);#1;
  if({valid,user,last}!==expected[n][98:96])$fatal(1,"extra markers cycle=%0d actual=%b expected=%b",n,{valid,user,last},expected[n][98:96]);
  if(valid && data!==expected[n][95:0])$fatal(1,"extra pixels cycle=%0d actual=%h expected=%h",n,data,expected[n][95:0]);
  if(valid)count=count+1;
  @(negedge clk);
 end
 if(count!=2688)$fatal(1,"wrong valid count %0d",count);
 $display("PASS EXTRA MODES 14 frames 2688 groups: whole-image dehaze reference, 4x4 motion mask, static/noise/reentry, bubbles, frame mode latch, 13 stages");$finish;
end
endmodule
