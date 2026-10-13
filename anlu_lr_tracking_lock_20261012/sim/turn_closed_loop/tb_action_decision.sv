`timescale 1ns/1ps
module tb_action_decision;
localparam CLK_HZ=10000;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,arm_pulse=0,estop=0,obstacle=0,slow=0,result_valid=0,link_ok=0;
reg [7:0] result_ascii="?",flag_stop=0;
reg action_status_valid=0;reg [7:0] feedback_action_seq=0,feedback_action_state=0,feedback_action_fault=0;
wire armed,force_zero,result_stale,action_active;wire [2:0] state;wire [7:0] action_seq;
wire signed [15:0] cmd_vx,cmd_vy,cmd_wz,action_angle_cdeg,action_forward_mm_s;
wire [15:0] action_max_wz_mrad;
car_decision #(.CLK_HZ(CLK_HZ)) dut(.*);
integer checks=0,k;reg [7:0] last_id;
task tick(input integer n);repeat(n)begin @(posedge clk);#1;end endtask
task check(input bit cond,input string msg);begin checks=checks+1;if(!cond)$fatal(1,"action decision: %s state=%0d seq=%0d",msg,state,action_seq);end endtask
task fresh(input [7:0] code);begin @(negedge clk);result_ascii=code;result_valid=1;tick(1);@(negedge clk);result_valid=0;end endtask
task feedback(input [7:0] id,st,err);begin
 @(negedge clk);feedback_action_seq=id;feedback_action_state=st;feedback_action_fault=err;action_status_valid=1;
 tick(1);@(negedge clk);action_status_valid=0;
end endtask
task arm;begin @(negedge clk);arm_pulse=1;tick(1);@(negedge clk);arm_pulse=0;end endtask
task reset;begin @(negedge clk);rst_n=0;link_ok=0;estop=0;obstacle=0;slow=0;flag_stop=0;result_valid=0;action_status_valid=0;arm_pulse=0;
 tick(3);@(negedge clk);rst_n=1;tick(3);end endtask
task ready;begin link_ok=1;feedback(42,3,0);fresh("?");arm;check(armed&&state==1,"healthy peer and vision permit manual ARM");end endtask
task left;begin fresh("L");fresh("L");fresh("L");check(state==2&&action_active&&action_angle_cdeg==9000&&cmd_wz==0&&cmd_vx==0,"left is an angle action, no FPGA yaw-speed output");end endtask
initial begin
 reset;check(force_zero&&!armed,"reset stop");arm;check(!armed,"no feedback cannot arm");
 link_ok=1;arm;check(!armed,"no vision cannot arm");ready;
 fresh("L");fresh("R");fresh("L");fresh("?");fresh("L");fresh("L");check(!action_active,"unstable signs rejected");
 fresh("L");check(action_active&&action_seq==43&&action_max_wz_mrad==700&&action_forward_mm_s==0,"new ID follows STM32 terminal ID after FPGA reset");last_id=action_seq;
 feedback(last_id+1,3,0);check(state==2,"wrong-sequence DONE ignored");
 feedback(last_id,3,0);check(state==2&&!dut.ack_seen,"pre-ACK stale DONE ignored");
 feedback(last_id,1,0);check(dut.ack_seen,"matching ACCEPTED acknowledged");
 for(k=0;k<17;k=k+1)begin tick(500);feedback(last_id,2,0);end
 check(state==2&&armed&&action_active&&result_stale,"800 ms does not finish turn; sign may leave view during maneuver");
 feedback(last_id,2,0);check(state==2,"RUNNING never completes action");
 fresh("?");feedback(last_id,3,0);check(state==1&&!action_active&&cmd_vx==100,"only matching ACK then DONE completes turn");
 fresh("L");fresh("L");fresh("L");check(state==1,"same held sign cannot retrigger");
 fresh("?");fresh("?");fresh("?");fresh("R");fresh("R");fresh("R");
 check(state==3&&action_angle_cdeg==-9000&&action_seq==last_id+1,"right has negative angle and a new ID");
 feedback(action_seq,2,0);estop=1;#1;check(force_zero&&!action_active,"ESTOP immediately suppresses action");tick(1);check(!armed&&state==0,"ESTOP disarms");
 estop=0;fresh("?");tick(3);check(!armed,"cleared ESTOP does not resume");arm;left;
 obstacle=1;#1;check(force_zero&&!action_active,"obstacle immediate stop");tick(1);check(!armed&&state==4,"obstacle disarms");
 reset;ready;left;tick(5001);check(force_zero,"missing ACK timeout");tick(1);check(!armed&&state==6,"ACK timeout latches fault");
 reset;ready;left;last_id=action_seq;feedback(last_id,2,0);
 for(k=0;k<161;k=k+1)begin tick(500);feedback(last_id,2,0);end
 check(!armed&&state==6,"total action timeout despite continuing matching RUNNING");
 reset;ready;left;last_id=action_seq;feedback(last_id,2,0);
 for(k=0;k<11;k=k+1)begin tick(500);feedback(last_id+1,2,0);end
 check(!armed&&state==6,"wrong-sequence traffic cannot refresh acknowledged turn heartbeat");
 reset;ready;left;feedback(action_seq,5,3);tick(1);check(!armed&&state==6&&force_zero,"STM32 feedback fault aborts");
 reset;ready;left;feedback(action_seq,4,0);tick(1);check(!armed&&state==6,"unexpected cancellation aborts");
 reset;ready;left;feedback(action_seq,2,0);link_ok=0;#1;check(force_zero&&!action_active,"loss of either channel gates action");tick(1);check(!armed,"link loss disarms");
 reset;ready;flag_stop=1;tick(1);check(!armed&&force_zero,"STM32 disabled blocks motion");
 reset;ready;slow=1;tick(1);check(cmd_vx==50&&state==5,"normal slow command preserved");
 slow=0;fresh("?");tick(5001);check(!armed&&force_zero,"vision timeout outside turn still disarms");
 $display("PASS ACTION DECISION %0d checks: matching ACK/DONE, angle targets, reset sequence sync, no timed completion, stale vision during turn, timeout/fault/stop and manual rearm",checks);$finish;
end
endmodule
