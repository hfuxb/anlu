`timescale 1ns/1ps
module tb_morphology_opening;
localparam W=64,H=32,G=W/4,N=G*H;
reg clk=0; always #5 clk=~clk;
reg rst=0,valid=0,user=0,last=0;
reg [95:0] data=0;
reg [1:0] mode=3;
wire ov,ou,ol,gv,gu,gl;
wire [95:0] od;
wire [31:0] gd;
wire [1:0] gm;
wire packed_valid,packed_last,packed_user;
wire [127:0] packed_data;
image_process_stream_96 #(.IMG_WIDTH(W),.IMG_HEIGHT(H)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tvalid(valid),.I_tuser(user),.I_tlast(last),.I_tdata(data),
 .I_algo_mode(mode),.I_edge_threshold(11'd24),.O_tvalid(ov),.O_tuser(ou),.O_tlast(ol),.O_tdata(od),
 .O_gray_tvalid(gv),.O_gray_tuser(gu),.O_gray_tlast(gl),.O_gray_data(gd),.O_gray_mode(gm));
// Keep the official early frame notification and check the actual DDR packer.
data_96bit_to_128bit packer(.I_clk(clk),.I_rst_n(rst),.I_96b_frame_start(user),
 .I_96b_last(ol),.I_96b_valid(ov),.I_96b_data(od),.O_128b_frame_start(packed_user),
 .O_128b_last(packed_last),.O_128b_valid(packed_valid),.O_128b_data(packed_data));
reg [95:0] pixels[0:N-1],ero[0:N-1],opened[0:N-1],direct[0:N-1];
reg [127:0] raw128[0:N*3/4-1],ero128[0:N*3/4-1],open128[0:N*3/4-1];
reg [31:0] gray[0:N-1];
reg [95:0] qdata[0:3];
reg [31:0] qgray[0:3];
reg [1:0] qmode[0:3];
reg [3:0] qvalid=0,quser=0,qlast=0;
reg [95:0] expected_in;
reg [31:0] expected_gray;
reg [1:0] frame_mode;
integer i,x,y,f,count=0,different=0;
integer packed_count=0,packed_index=0,packed_frames=0;
reg [1:0] packed_mode;
always @(posedge clk) if(rst)begin
 if(user)begin packed_index=0;packed_mode=frame_mode;end
 #1;
 if(packed_user)packed_frames=packed_frames+1;
 if(packed_valid)begin
  if(packed_data!==(packed_mode==2?ero128[packed_index]:packed_mode==1?open128[packed_index]:raw128[packed_index]))
   $fatal(1,"DDR packed pixel mismatch frame=%0d beat=%0d",packed_frames,packed_index);
  if(packed_last!==(packed_index%(G*3/4)==G*3/4-1))$fatal(1,"DDR last marker mismatch");
  packed_count=packed_count+1;packed_index=packed_index+1;
 end
end
always @(posedge clk) if(rst) begin
 #1;
 if({ov,ou,ol}!=={qvalid[3],quser[3],qlast[3]})$fatal(1,"pixel markers/latency");
 if({gv,gu,gl}!=={qvalid[3],quser[3],qlast[3]})$fatal(1,"gray markers/latency");
 if(ov)begin
  if(od!==qdata[3])$fatal(1,"numeric morphology mismatch output=%0d got=%h expected=%h",count,od,qdata[3]);
  if(gd!==qgray[3] || gm!==qmode[3])$fatal(1,"gray data/mode not aligned");
  count=count+1;
 end
 for(i=3;i>0;i=i-1)begin qdata[i]=qdata[i-1];qgray[i]=qgray[i-1];qmode[i]=qmode[i-1];end
 qdata[0]=expected_in;qgray[0]=expected_gray;qmode[0]=frame_mode;
 qvalid={qvalid[2:0],valid};quser={quser[2:0],valid&&user};qlast={qlast[2:0],valid&&last};
end
initial begin
 $readmemh("../../opening_golden/input.hex",pixels);
 $readmemh("../../opening_golden/gray.hex",gray);
 $readmemh("../../opening_golden/erosion.hex",ero);
 $readmemh("../../opening_golden/opening.hex",opened);
 $readmemh("../../opening_golden/direct_dilation.hex",direct);
 $readmemh("../../opening_golden/input128.hex",raw128);
 $readmemh("../../opening_golden/erosion128.hex",ero128);
 $readmemh("../../opening_golden/opening128.hex",open128);
 for(i=0;i<N;i=i+1)if(opened[i]!=direct[i])different=different+1;
 if(different<1)$fatal(1,"opening reference does not distinguish direct dilation");
 repeat(4)@(negedge clk);rst=1;
 // No reset between modes; input bubbles include stalls at row/group boundaries.
 for(f=0;f<6;f=f+1)begin
  frame_mode=(f==0 || f==4)?3:(f==1?2:(f==2 || f==5?1:0));
  for(y=0;y<H;y=y+1)for(x=0;x<G;x=x+1)begin
   @(negedge clk);valid=1;user=(x==0&&y==0);last=(x==G-1);data=pixels[y*G+x];
   mode=user?frame_mode:((x%5==1)?frame_mode^2'b11:frame_mode);
   expected_in=frame_mode==2?ero[y*G+x]:frame_mode==1?opened[y*G+x]:data;
   expected_gray=gray[y*G+x];
   if(x%7==2 || x==G-1)begin @(negedge clk);valid=0;user=0;last=0;end
  end
  @(negedge clk);valid=0;user=0;last=0;repeat(8)@(negedge clk);
 end
 repeat(8)@(negedge clk);
 if(count!=N*6)$fatal(1,"input/output count mismatch %0d",count);
 if(packed_count!=N*6*3/4 || packed_frames!=6)$fatal(1,"DDR packed count mismatch");
 $display("PASS MORPHOLOGY OPENING: %0d stream words / %0d DDR words, independent Sobel/erosion/opening reference, RAW/gray/mode/markers, stalls and consecutive frames",count,packed_count);
 $finish;
end
initial begin #1000000;$fatal(1,"opening timeout");end
endmodule
