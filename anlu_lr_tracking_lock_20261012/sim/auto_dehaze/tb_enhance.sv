`timescale 1ns/1ps
`include "count.vh"
module tb_enhance;
reg clk=0,rst=0;always #5 clk=~clk;
reg [99:0] sample=0;reg [99:0] inputs[0:`N-1];reg [98:0] expected[0:`N-1];
wire v,u,l;wire [95:0] data;
dehaze_enhance_96 #(.IMG_WIDTH(1280),.IMG_HEIGHT(12)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tvalid(sample[99]),.I_tuser(sample[98]),.I_tlast(sample[97]),
 .I_enable(sample[96]),.I_tdata(sample[95:0]),.O_tvalid(v),.O_tuser(u),.O_tlast(l),.O_tdata(data));
integer n,count=0;
initial begin
 $readmemh("input.hex",inputs);$readmemh("expected.hex",expected);
 repeat(4)@(negedge clk);rst=1;
 for(n=0;n<`N;n=n+1)begin
  sample=inputs[n];@(posedge clk);#1;
  if({v,u,l}!==expected[n][98:96])$fatal(1,"enhance markers n=%0d",n);
  if(v)begin
   if(data!==expected[n][95:0])$fatal(1,"enhance golden mismatch n=%0d actual=%h expected=%h",n,data,expected[n][95:0]);
   count=count+1;
  end
  @(negedge clk);
 end
 if(count!=`GROUPS)$fatal(1,"count wrong");
 $display("PASS ENHANCE independent Gamma0.85/causal2x2/deadband/clamp RGB reference: %0d groups, width1280, bubbles, frame-latched bypass, row/frame boundaries, no displacement",count);$finish;
end
endmodule
