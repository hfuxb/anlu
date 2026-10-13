`timescale 1ns/1ps
module tb_motion_full720;
reg clk=0,rst=0,v=0,u=0,l=0,en=0;always #5 clk=~clk;
reg [95:0] din=0;wire vo,uo,lo;wire [95:0] dout;
motion_stream_96 dut(.I_clk(clk),.I_rst_n(rst),.I_tvalid(v),.I_tuser(u),.I_tlast(l),
 .I_enable(en),.I_tdata(din),.O_tvalid(vo),.O_tuser(uo),.O_tlast(lo),.O_tdata(dout));
reg [98:0] old_expected=0;
integer count=0,f,x,y,rows,value;reg moving;reg [23:0] pixel;
task beat(input bit vv,uu,ll,enable_pin,input [95:0] d,e);
begin
 v=vv;u=uu;l=ll;en=enable_pin;din=d;
 @(posedge clk);#1;
 if({vo,uo,lo}!==old_expected[98:96])$fatal(1,"motion full720 markers frame=%0d x=%0d y=%0d",f,x,y);
 if(vo && dout!==old_expected[95:0])$fatal(1,"motion full720 pixels frame=%0d x=%0d y=%0d got=%h exp=%h",f,x,y,dout,old_expected[95:0]);
 if(vo)count=count+1;
 old_expected={vv,vv&&uu,vv&&ll,e};
 @(negedge clk);
end endtask
initial begin
 repeat(4)@(negedge clk);rst=1;
 for(f=0;f<9;f=f+1)begin
  rows=f==7?4:720;
  for(y=0;y<rows;y=y+1)begin
   for(x=0;x<320;x=x+1)begin
    value=80;moving=0;
    if(f==2 || f==3)begin
     value=(x>=70&&x<100&&y>=200&&y<300)?150:80;
     if(f==3)value=value+5;
     moving=f==2&&x>=70&&x<100&&y>=200&&y<300;
    end
    if(f==4)value=10;
    if(f==5 || f==6)begin value=40;
     if(f==6 && x>=70&&x<100&&y>=200&&y<300)begin value=100;moving=1;end
    end
    if(f==7)begin value=80;moving=1;end
    if(f==8)value=180; // Partial prior frame MUST NOT trigger a red screen.
    pixel={8'(value),8'(value),8'(value)};
    beat(1,x==0&&y==0,x==319,f!=4,{4{pixel}},moving?{4{24'(24'hff0000|((value/2)<<8)|(value/2))}}:{4{pixel}});
   end
   beat(0,0,0,f!=4,0,0);
  end
  repeat(3)beat(0,0,0,f!=4,0,0);
  $display("MOTION FRAME %0d rows=%0d checked",f,rows);
 end
 repeat(3)beat(0,0,0,0,0,0);
 if(count!=1844480)$fatal(1,"motion full count=%0d",count);
 $display("PASS MOTION FULL720 8 complete frames plus truncated frame, 1844480 groups: red 4x4 mask, no static/noise false positives, reentry and partial-frame recovery");$finish;
end
endmodule
