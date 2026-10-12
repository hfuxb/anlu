`timescale 1ns/1ps
module tb_sig_only;
reg clk=0,dclk=0;always #5 clk=~clk;always #7 dclk=~dclk;
reg rst=0,user=0,last=0,valid=0,request=0;
reg [1:0] mode=3;
reg [95:0] data=0;
wire enabled,busy,done,ok,drop,box;
wire [4:0] cls;
wire [7:0] ascii,score;
wire [10:0] x0,x1;
wire [9:0] y0,y1;
traffic_sign_sig_only_96 #(.IMG_WIDTH(640),.IMG_HEIGHT(360)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tuser(user),.I_tlast(last),.I_tvalid(valid),.I_tdata(data),
 .I_algo_mode(mode),.I_recognition_request(request),.O_enabled(enabled),.O_busy(busy),
 .O_done(done),.O_result_valid(ok),.O_result_class(cls),.O_result_ascii(ascii),
 .O_frame_drop(drop),.O_box_valid(box),.O_x_min(x0),.O_x_max(x1),.O_y_min(y0),.O_y_max(y1),.O_score(score));
wire [50:0] metadata={box,x0,x1,y0,y1,score};
reg source_toggle=0;
always @(posedge clk) if(!rst)source_toggle<=0;else if(done)source_toggle<=~source_toggle;
wire dst_toggle,dst_valid;
wire [7:0] dst_ascii;
wire [50:0] dst_metadata;
traffic_sign_result_cdc cdc(.I_src_clk(clk),.I_src_rst_n(rst),.I_src_toggle(source_toggle),
 .I_src_ascii(ascii),.I_src_metadata(metadata),.I_dst_clk(dclk),.I_dst_rst_n(rst),
 .O_dst_toggle(dst_toggle),.O_dst_valid(dst_valid),.O_dst_ascii(dst_ascii),.O_dst_metadata(dst_metadata));
reg [95:0] image[0:57599];
integer events=0,frames=0,checks=0;
always @(posedge clk)begin
 if(rst && drop)$fatal(1,"core dropped a permitted frame");
 if(done)begin events=events+1;$display("event=%0d mode=%b enabled=%0d ascii=%c score=%0d box=%0d",events,mode,enabled,ascii,score,box);end
 if(rst && !request && dut.core_input_valid)$fatal(1,"disabled mode fed recognizer");
end
task check(input bit condition,input string message);
begin checks=checks+1;if(!condition)$fatal(1,"SIG boundary: %s",message);end endtask
task select_mode(input [1:0] value);
begin @(negedge clk);mode=value;request=(value==0);repeat(20)@(negedge clk);end endtask
task frame(input string filename,input integer switch_row,input [1:0] switch_mode);
integer x,y;
begin
 $readmemh(filename,image);
 for(y=0;y<360;y=y+1)begin
  if(y==switch_row)begin mode=switch_mode;request=(switch_mode==0);end
  for(x=0;x<160;x=x+1)begin
   @(negedge clk);valid=1;user=(x==0 && y==0);last=(x==159);data=image[y*160+x];
   if(x%17==8)begin @(negedge clk);valid=0;user=0;last=0;end
  end
  @(negedge clk);valid=0;user=0;last=0;repeat(12)@(negedge clk);
 end
 repeat(1000)@(negedge clk);frames=frames+1;
end endtask
integer event_baseline,n;
initial begin
 repeat(5)@(negedge clk);rst=1;repeat(300)@(negedge clk);
 event_baseline=events;
 for(n=0;n<2;n=n+1)frame("../tracking/left.hex",-1,3);
 select_mode(2);frame("../tracking/left.hex",-1,2);
 select_mode(1);frame("../tracking/right_same_position.hex",-1,1);
 check(events==event_baseline && !enabled && !busy && !ok && ascii=="?" && metadata==0,"RAW/ERO/DIL recognized a sign");
 // A transient 00 on the multi-bit mode bus is not a genuine SIG request.
 @(negedge clk);mode=0;request=0;repeat(300)@(negedge clk);
 frame("../tracking/right_same_position.hex",-1,0);
 check(events==event_baseline && !enabled && !dut.core_run,"false 00 decode enabled core");
 select_mode(3);
 // Enabling halfway through RAW initializes, but must not score a partial frame.
 frame("../tracking/left.hex",150,0);
 check(events==event_baseline && !enabled && ascii=="?" && metadata==0,"mid-frame entry used partial image");
 frame("../tracking/left.hex",-1,0);check(events==event_baseline+1 && enabled && ascii=="?","first complete SIG frame missing");
 frame("../tracking/left.hex",-1,0);check(ascii=="?","early left confirmation");
 frame("../tracking/left.hex",-1,0);check(ascii=="?","early left confirmation");
 frame("../tracking/left.hex",-1,0);check(ascii=="L" && ok && cls==1 && box,"SIG failed to confirm left");
 check(dst_ascii=="L" && dst_metadata==metadata,"SIG result CDC not coherent");
 // Leaving halfway through a frame emits one clear event, never another L.
 event_baseline=events;
 frame("../tracking/left.hex",100,2);
 check(events==event_baseline+1 && !enabled && !ok && ascii=="?" && metadata==0,"mid-frame exit retained old lock");
 check(dst_ascii=="?" && dst_metadata==0,"clear packet did not cross CDC");
 event_baseline=events;
 select_mode(1);frame("../tracking/right_same_position.hex",-1,1);
 select_mode(3);frame("../tracking/right_same_position.hex",-1,3);
 check(events==event_baseline && ascii=="?" && metadata==0,"non-SIG generated recognition after lock");
 // Enter exactly at SOF: skip warmup frame rather than missing its first pixels.
 @(negedge clk);mode=0;request=1;
 frame("../tracking/right_same_position.hex",-1,0);
 check(events==event_baseline && !enabled && ascii=="?" && metadata==0,"warmup frame scored or revived left");
 frame("../tracking/right_same_position.hex",-1,0);check(ascii=="?" && events==event_baseline+1,"new right ROI frame");
 frame("../tracking/right_same_position.hex",-1,0);check(ascii=="?","new right first vote");
 frame("../tracking/right_same_position.hex",-1,0);check(ascii=="?","new right second vote");
 frame("../tracking/right_same_position.hex",-1,0);check(ascii=="R" && ok && cls==2 && box,"new SIG did not acquire right");
 // Disable during frame-end scoring, event_baseline core_done: neutral overrides result.
 $readmemh("../tracking/right_same_position.hex",image);
 for(n=0;n<57600;n=n+1)begin
  @(negedge clk);valid=1;user=(n==0);last=(n%160==159);data=image[n];
 end
 @(negedge clk);valid=0;user=0;last=0;repeat(10)@(negedge clk);
 event_baseline=events;select_mode(3);repeat(1000)@(negedge clk);
 check(events==event_baseline+1 && ascii=="?" && metadata==0 && !enabled,"late scoring leaked after disable");
 check(dst_ascii=="?" && dst_metadata==0,"final disable not coherent at destination");
 $display("PASS SIG ONLY detector: %0d frames / %0d checks / mode gating, RAM warmup, complete SOF, partial abort, reset lock, fresh reentry, clear CDC",frames+1,checks);
 $finish;
end
initial begin #100000000;$fatal(1,"SIG-only timeout");end
endmodule
