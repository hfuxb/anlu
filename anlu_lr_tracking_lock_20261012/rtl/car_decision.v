`timescale 1ns/1ps
// FPGA owns recognition voting and action requests. STM32 owns measured-angle
// turning and wheel PI. Matching acknowledged DONE replaces the old demo timer.
module car_decision #(
    parameter integer CLK_HZ=50000000,
    parameter integer CONFIRM_FRAMES=3,CLEAR_FRAMES=3,
    parameter integer RESULT_TIMEOUT_MS=500,
    parameter integer TURN_TIMEOUT_MS=8000,ACK_TIMEOUT_MS=500,
    parameter integer FORWARD_MM_S=100,SLOW_MM_S=50,
    parameter integer TURN_ANGLE_CDEG=9000,
    parameter integer TURN_MAX_WZ_MRAD=700,
    parameter integer TURN_FORWARD_MM_S=0
)(
    input wire clk,rst_n,arm_pulse,estop,obstacle,slow,
    input wire result_valid,input wire [7:0] result_ascii,
    input wire link_ok,input wire [7:0] flag_stop,
    input wire action_status_valid,input wire [7:0] feedback_action_seq,
    input wire [7:0] feedback_action_state,feedback_action_fault,
    output reg armed,output reg [2:0] state,
    output reg signed [15:0] cmd_vx,cmd_vy,cmd_wz,
    output wire force_zero,result_stale,action_active,
    output reg [7:0] action_seq,
    output wire signed [15:0] action_angle_cdeg,
    output wire [15:0] action_max_wz_mrad,
    output wire signed [15:0] action_forward_mm_s
);
    localparam [2:0] STOP=0,FORWARD=1,LEFT=2,RIGHT=3,OBSTACLE=4,SLOW=5,FAULT=6;
    localparam integer AGE_TICKS=(CLK_HZ/1000)*RESULT_TIMEOUT_MS;
    localparam integer TURN_TICKS=(CLK_HZ/1000)*TURN_TIMEOUT_MS;
    localparam integer ACK_TICKS=(CLK_HZ/1000)*ACK_TIMEOUT_MS;
    reg have_result,ack_seen;
    reg [31:0] result_age,turn_age,matching_age;
    reg [7:0] vote_ascii,next_seq;
    reg [15:0] vote_count,clear_count;
    reg turn_locked;
    wire turning=state==LEFT || state==RIGHT;
    wire matching_status=action_status_valid && feedback_action_seq==action_seq;
    wire terminal_failure=matching_status &&
        (feedback_action_state==8'd4 || feedback_action_state==8'd5 || feedback_action_fault!=0);
    wire turn_failed=turning && (turn_age>=TURN_TICKS ||
        (!ack_seen && turn_age>=ACK_TICKS) ||
        (ack_seen && matching_age>=ACK_TICKS && !matching_status) || terminal_failure);
    assign result_stale=!have_result || result_age>=AGE_TICKS;
    // The sign may leave view during a maneuver. STOP/SIG exit/obstacle and
    // feedback freshness continue to dominate, including while vision is stale.
    wire unsafe=estop || obstacle || !link_ok || flag_stop!=0 ||
        (result_stale && !turning) || turn_failed;
    assign force_zero=!armed || unsafe;
    assign action_active=armed && turning && !unsafe;
    assign action_angle_cdeg=state==LEFT?TURN_ANGLE_CDEG:
        state==RIGHT?-TURN_ANGLE_CDEG:16'sd0;
    assign action_max_wz_mrad=TURN_MAX_WZ_MRAD;
    assign action_forward_mm_s=TURN_FORWARD_MM_S;
    always @*begin
        cmd_vx=0;cmd_vy=0;cmd_wz=0;
        if(!force_zero)begin
            if(state==FORWARD)cmd_vx=FORWARD_MM_S;
            else if(state==SLOW)cmd_vx=SLOW_MM_S;
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin have_result<=0;result_age<=AGE_TICKS;end
        else if(result_valid)begin have_result<=1;result_age<=0;end
        else if(result_age<AGE_TICKS)result_age<=result_age+1'b1;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            armed<=0;state<=STOP;turn_age<=0;matching_age<=0;ack_seen<=0;
            vote_ascii<="?";vote_count<=0;clear_count<=0;turn_locked<=0;
            action_seq<=0;next_seq<=1;
        end else begin
            // Learn the peer's last ID before ARM, avoiding terminal ID reuse
            // when only the FPGA resets and the STM32 remains powered.
            if(action_status_valid && !armed)next_seq<=feedback_action_seq+1'b1;
            if(unsafe)begin
                armed<=0;state<=obstacle?OBSTACLE:estop?STOP:FAULT;
                vote_count<=0;vote_ascii<="?";turn_age<=0;matching_age<=0;ack_seen<=0;
                turn_locked<=0;clear_count<=0;
            end else if(!armed)begin
                vote_count<=0;vote_ascii<="?";turn_age<=0;matching_age<=0;ack_seen<=0;
                turn_locked<=0;clear_count<=0;
                if(arm_pulse)begin armed<=1;state<=slow?SLOW:FORWARD;end
            end else if(turning)begin
                turn_age<=turn_age+1'b1;vote_count<=0;clear_count<=0;
                if(matching_status && (feedback_action_state==8'd1 || feedback_action_state==8'd2 || feedback_action_state==8'd3))matching_age<=0;
                else if(matching_age<ACK_TICKS)matching_age<=matching_age+1'b1;
                if(matching_status)begin
                    if(feedback_action_state==8'd1 || feedback_action_state==8'd2)ack_seen<=1;
                    else if(feedback_action_state==8'd3 && ack_seen)begin
                        state<=slow?SLOW:FORWARD;turn_age<=0;ack_seen<=0;
                    end
                end
            end else begin
                state<=slow?SLOW:FORWARD;
                if(result_valid)begin
                    if(turn_locked)begin
                        vote_count<=0;
                        if(result_ascii=="?")begin
                            if(clear_count>=CLEAR_FRAMES-1)begin turn_locked<=0;clear_count<=0;end
                            else clear_count<=clear_count+1'b1;
                        end else clear_count<=0;
                    end else if(result_ascii=="L" || result_ascii=="R")begin
                        if((vote_ascii==result_ascii && vote_count>=CONFIRM_FRAMES-1) || CONFIRM_FRAMES<=1)begin
                            state<=result_ascii=="L"?LEFT:RIGHT;turn_age<=0;matching_age<=0;ack_seen<=0;
                            action_seq<=next_seq;next_seq<=next_seq+1'b1;
                            turn_locked<=1;vote_count<=0;
                        end else begin
                            vote_ascii<=result_ascii;
                            vote_count<=vote_ascii==result_ascii?vote_count+1'b1:16'd1;
                        end
                    end else begin vote_count<=0;vote_ascii<="?";end
                end
            end
        end
    end
endmodule
