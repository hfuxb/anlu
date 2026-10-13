`timescale 1ns/1ps
// End-to-end CDC, button policy and independent 8N1 wire monitor. The peer
// sends the real legacy 24-byte telemetry followed by the new action status.
module tb_action_control;
    reg clk=0,src_clk=0;
    always #500 clk=~clk;
    always #700 src_clk=~src_clk;
    reg rst_n=0,src_rst_n=0;
    reg [7:0] src_result_ascii="?";
    reg src_result_toggle=0;
    reg arm_n=1,stop_n=1,obstacle_n=1,slow_n=1,rx=1;
    reg src_mode_enable=1;
    reg mode_enable_sync1=0,mode_enable_sync2=0;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin mode_enable_sync1<=0; mode_enable_sync2<=0; end
        else begin mode_enable_sync1<=src_mode_enable; mode_enable_sync2<=mode_enable_sync1; end
    end
    wire tx,armed,link_ok,result_stale,status_valid;
    wire [2:0] state;
    wire signed [15:0] command_vx,command_vy,command_wz,actual_vx,actual_vy,actual_wz;
    wire [7:0] flag_stop;
    wire [15:0] battery_mv;
    wire [31:0] tx_count,rx_count,rx_error_count;
    car_control #(.CLK_HZ(1000000),.BAUD(100000),.SEND_HZ(500),
        .DEBOUNCE_MS(1),.RESULT_TIMEOUT_MS(50),.LINK_TIMEOUT_MS(100),
        .ACK_TIMEOUT_MS(30),.TURN_TIMEOUT_MS(100)) dut(
        .stop_n(stop_n && mode_enable_sync2),.*);
    reg [7:0] legacy[0:23],status[0:10],tx_bytes[0:10],monitor_byte,bcc;
    reg [7:0] last_tx_mode,last_tx_seq,left_seq,right_seq,active_seq;
    reg signed [15:0] last_tx_a,last_tx_b,last_tx_c;
    integer frames=0,zero_frames=0,forward_frames=0,action_frames=0;
    integer byte_index=0,checks=0,baseline,k,j;
    task tick(input integer n); repeat(n) begin @(posedge clk); #1; end endtask
    task check(input bit condition,input string message);
        checks=checks+1;
        if(!condition) $fatal(1,"action control: %s t=%0t armed=%0d state=%0d link=%0d stale=%0d rx=%0d wire=%0d",message,$time,armed,state,link_ok,result_stale,rx_count,frames);
    endtask
    task vision(input [7:0] code);
        @(negedge src_clk); src_result_ascii=code; src_result_toggle=~src_result_toggle;
        tick(20);
    endtask
    task press_arm;
        @(negedge clk); arm_n=0; tick(1050);
        @(negedge clk); arm_n=1; tick(1050);
    endtask
    task send_byte(input [7:0] value);
        @(negedge clk); rx=0; repeat(10) @(negedge clk);
        for(integer b=0;b<8;b=b+1) begin rx=value[b]; repeat(10) @(negedge clk); end
        rx=1; repeat(10) @(negedge clk);
    endtask
    task send_telemetry(input [7:0] flag,input bit corrupt);
        for(integer p=0;p<24;p=p+1) legacy[p]=0;
        legacy[0]=8'h7b; legacy[1]=flag; legacy[3]=100;
        legacy[6]=8'hff; legacy[7]=8'h06;
        legacy[8]=8'h7b; legacy[9]=8'h7d;
        legacy[10]=8'h7c; legacy[11]=8'h7e;
        legacy[20]=8'h5d; legacy[21]=8'hc0; legacy[23]=8'h7d;
        legacy[22]=0;
        for(integer p=0;p<22;p=p+1) legacy[22]=legacy[22]^legacy[p];
        if(corrupt) legacy[22]=legacy[22]^8'h80;
        for(integer p=0;p<24;p=p+1) send_byte(legacy[p]);
        tick(20);
    endtask
    task send_status(input [7:0] seq,input [7:0] action_state,input [7:0] fault,
                     input signed [15:0] progress,input signed [15:0] error);
        status[0]=8'h7c;status[1]=8'ha1;status[2]=seq;status[3]=action_state;
        status[4]=progress[15:8];status[5]=progress[7:0];
        status[6]=error[15:8];status[7]=error[7:0];status[8]=fault;
        status[9]=0;status[10]=8'h7e;
        for(integer p=0;p<9;p=p+1)status[9]=status[9]^status[p];
        for(integer p=0;p<11;p=p+1)send_byte(status[p]);
        tick(20);
    endtask
    task peer(input [7:0] seq,input [7:0] action_state,input [7:0] fault);
        send_telemetry(0,0);
        send_status(seq,action_state,fault,16'sd1234,16'sd7766);
    endtask
    task arm_with_peer(input [7:0] seq);
        peer(seq,3,0);vision("?");press_arm();
        check(armed && state==1,"fresh dual-channel peer and manual ARM resume forward");
    endtask
    task start_left;
        vision("L");vision("L");check(state==1,"two distinct left events cannot request a turn");
        vision("L");check(armed && state==2 && command_vx==0 && command_wz==0,"three votes request angle action with no legacy velocity turn");
        tick(3500);
        check(last_tx_mode==8'h10 && last_tx_a==9000 && last_tx_b==700 && last_tx_c==0,"left action encoded on UART as +9000 cdeg, 700 mrad/s, zero forward");
        active_seq=last_tx_seq;
    endtask
    // This monitor reads only the physical TX pin, not transmitter registers.
    initial begin
        wait(rst_n);
        forever begin
            @(negedge tx);#5000;
            if(tx!==0)$fatal(1,"monitor invalid UART start");
            for(j=0;j<8;j=j+1)begin #10000;monitor_byte[j]=tx;end
            #10000;if(tx!==1)$fatal(1,"monitor invalid UART stop");
            tx_bytes[byte_index]=monitor_byte;
            if(byte_index==10)begin
                if(tx_bytes[0]!==8'h7b || tx_bytes[10]!==8'h7d ||
                    (tx_bytes[1]!==0 && tx_bytes[1]!==8'h10))$fatal(1,"invalid command envelope");
                bcc=0;for(k=0;k<9;k=k+1)bcc=bcc^tx_bytes[k];
                if(bcc!==tx_bytes[9])$fatal(1,"command checksum failed");
                last_tx_mode=tx_bytes[1];last_tx_seq=tx_bytes[2];
                last_tx_a={tx_bytes[3],tx_bytes[4]};last_tx_b={tx_bytes[5],tx_bytes[6]};last_tx_c={tx_bytes[7],tx_bytes[8]};
                if(last_tx_mode==0)begin
                    if(last_tx_seq!=0 || last_tx_b!=0 || last_tx_c!=0)$fatal(1,"legacy command must carry zero reserved, vy and wz");
                    if(last_tx_a==0)zero_frames=zero_frames+1;
                    else if(last_tx_a==100 || last_tx_a==50)forward_frames=forward_frames+1;
                    else $fatal(1,"unexpected legacy speed");
                end else begin
                    if((last_tx_a!=9000 && last_tx_a!=-9000) || last_tx_b!=700 || last_tx_c!=0)$fatal(1,"invalid action parameters");
                    action_frames=action_frames+1;
                end
                frames=frames+1;byte_index=0;
            end else byte_index=byte_index+1;
            #5000;
        end
    end
    initial begin
        tick(5);rst_n=1;src_rst_n=1;tick(2500);
        check(zero_frames>=1 && !armed,"boot sends zero heartbeat");
        send_telemetry(0,1);check(rx_count==0 && !link_ok,"corrupt telemetry cannot open safety interlock");
        send_telemetry(0,0);vision("?");press_arm();
        check(rx_count==1 && !armed && !link_ok,"old 24-byte-only firmware cannot ARM this action protocol");
        send_telemetry(1,0);send_status(42,0,0,0,0);vision("?");press_arm();
        check(link_ok && flag_stop==1 && !armed,"STM32 disabled flag blocks ARM even with action heartbeat");
        arm_with_peer(42);
        check(actual_vx==100 && actual_wz==-250 && battery_mv==24000,"joined telemetry/status stream retains signed legacy feedback and battery");
        tick(3500);check(last_tx_mode==0 && last_tx_a==100,"forward command remains legacy mode zero on wire");
        start_left();left_seq=active_seq;check(left_seq==43,"sequence learns powered peer terminal ID before ARM");
        send_status(left_seq,3,0,9000,0);
        check(armed && state==2,"matching DONE before ACK does not finish maneuver");
        send_status(left_seq+1'b1,2,0,0,9000);send_status(left_seq+1'b1,3,0,9000,0);
        check(armed && state==2,"wrong sequence RUNNING and DONE are ignored");
        peer(left_seq,1,0);peer(left_seq,2,0);
        baseline=action_frames;
        for(integer n=0;n<6;n=n+1)begin tick(6000);peer(left_seq,2,0);end
        check(result_stale && armed && state==2,"sign leaving view does not abort acknowledged maneuver with fresh action heartbeat");
        check(action_frames>baseline+10 && last_tx_seq==left_seq && last_tx_a==9000,"periodic turn keepalives preserve the same ID and parameters");
        vision("L");peer(left_seq,3,0);
        check(armed && state==1 && command_vx==100,"matching ACK then DONE completes angle maneuver");
        tick(3500);check(last_tx_mode==0 && last_tx_a==100,"completed action returns to forward legacy packets");
        vision("L");vision("L");vision("L");tick(3500);
        check(armed && state==1 && last_tx_mode==0,"held recognized sign cannot restart completed action");
        vision("?");vision("?");vision("?");
        vision("R");vision("R");vision("R");tick(3500);right_seq=last_tx_seq;
        check(state==3 && last_tx_mode==8'h10 && last_tx_a==-9000 && right_seq==left_seq+1'b1,"new right sign uses next ID and signed -9000 cdeg");
        peer(right_seq,2,0);
        @(negedge src_clk);src_mode_enable=0;tick(6);
        check(!armed && state==0 && command_vx==0 && command_wz==0,"leaving SIG immediately disarms active action");
        baseline=zero_frames;tick(3500);
        check(zero_frames>baseline && last_tx_mode==0 && last_tx_a==0,"SIG exit sends zero after current atomic packet");
        vision("R");vision("R");vision("R");peer(right_seq,3,0);press_arm();
        check(!armed && state==0,"new recognition and ARM cannot move car outside SIG");
        src_mode_enable=1;tick(20);check(!armed,"SIG reentry never automatically rearms");
        arm_with_peer(right_seq);start_left();peer(active_seq,2,0);
        // Ordinary feedback and valid wrong-ID statuses keep the general link
        // alive, but cannot extend the matching maneuver heartbeat deadline.
        for(integer n=0;n<7;n=n+1)begin tick(2000);peer(active_seq+1'b1,2,0);end
        check(link_ok && !armed && state==6 && command_vx==0,"matching action heartbeat timeout aborts even while both generic channels remain fresh");
        tick(3500);check(last_tx_mode==0 && last_tx_a==0,"heartbeat fault emits urgent zero command");
        arm_with_peer(active_seq);start_left();peer(active_seq,1,0);peer(active_seq,5,3);
        check(!armed && state==6 && command_vx==0,"matching STM32 feedback fault immediately disarms");
        tick(3500);check(last_tx_mode==0 && last_tx_a==0,"STM32 fault is represented by zero wire packets");
        peer(active_seq,3,0);vision("?");tick(500);
        check(!armed,"late DONE after fault cannot automatically resume driving");
        press_arm();check(armed,"fresh peer requires explicit new ARM after fault");
        slow_n=0;tick(4);check(state==5 && command_vx==50,"slow input still uses original forward policy");
        tick(3500);check(last_tx_mode==0 && last_tx_a==50,"slow legacy command verified on wire");
        obstacle_n=0;tick(4);check(!armed && state==4,"obstacle input disarms");
        tick(3500);check(last_tx_mode==0 && last_tx_a==0,"obstacle interlock sends zero");
        obstacle_n=1;slow_n=1;arm_with_peer(active_seq);start_left();peer(active_seq,2,0);
        stop_n=0;tick(4);check(!armed && state==0,"physical STOP aborts active turn");
        tick(3500);check(last_tx_mode==0 && last_tx_a==0,"STOP sends zero after atomic action packet");
        stop_n=1;peer(active_seq,4,0);vision("?");tick(500);
        check(!armed,"STOP release and cancelled status do not automatically rearm");
        check(frames==zero_frames+forward_frames+action_frames && action_frames>30,"all complete UART packets independently accounted for");
        $display("PASS tb_action_control (%0d checks; %0d complete UART packets; %0d action keepalives)",checks,frames,action_frames);$finish;
    end
    initial begin #500000000;$fatal(1,"action control test timeout");end
endmodule
