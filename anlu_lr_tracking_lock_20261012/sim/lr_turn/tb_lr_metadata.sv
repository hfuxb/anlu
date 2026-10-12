`timescale 1ns/1ps
module tb_lr_metadata;
reg src_clk=0,dst_clk=0,rst=0,toggle=0;
always #8.333 src_clk=~src_clk;
always #6.667 dst_clk=~dst_clk;
reg [7:0] ascii="?";
reg [50:0] metadata=0;
wire dst_toggle,dst_valid;
wire [7:0] dst_ascii;
wire [50:0] dst_metadata;
traffic_sign_result_cdc dut(.I_src_clk(src_clk),.I_src_rst_n(rst),.I_src_toggle(toggle),
.I_src_ascii(ascii),.I_src_metadata(metadata),.I_dst_clk(dst_clk),.I_dst_rst_n(rst),
.O_dst_toggle(dst_toggle),.O_dst_ascii(dst_ascii),.O_dst_metadata(dst_metadata),.O_dst_valid(dst_valid));
integer n,received=0;
always @(negedge dst_clk)if(rst && dst_valid)begin
 if(dst_ascii!==ascii || dst_metadata!==metadata || dst_toggle!==toggle)$fatal(1,"incoherent metadata CDC");
 received=received+1;
end
initial begin
 repeat(5)@(negedge src_clk);rst=1;
 for(n=0;n<100;n=n+1)begin
  repeat(9+n%7)@(negedge src_clk);
  // Alternate edge phases; ISP changes its toggle just AFTER a source posedge.
  if(n%2==0)begin @(posedge src_clk);#0.001;end
  ascii=n%3==0?"?":n%3==1?"L":"R";
  metadata={1'b1,11'(n+300),11'(n+400),10'(n+100),10'(n+200),8'(n)};
  toggle=~toggle;
  repeat(12)@(negedge src_clk);
  if(dst_ascii!==ascii || dst_metadata!==metadata)$fatal(1,"CDC failed delivery");
 end
 if(received!=100)$fatal(1,"wrong CDC event count");
 $display("PASS LR metadata CDC 100 coherent packets");$finish;
end
endmodule
