`timescale 1ns/1ps
// Statistics ALWAYS observe pre-dehaze AWB RGB, never enhanced or held MATCH.
// Complete frames only. 16-bin luma percentiles reject small bright lamps.
// Time hysteresis uses the measured SOF interval at the 60 MHz CSI byte clock.
module recognition_environment_96 #(
 parameter integer IMG_WIDTH=1280,IMG_HEIGHT=720,CLK_HZ=60000000,
 parameter integer SAMPLE_X_STEP=16,SAMPLE_Y_STEP=8,
 parameter integer ENTER_MS=500,EXIT_MS=1000,HOLD_MS=2000,
 parameter integer ENTER_FRAMES=8,EXIT_FRAMES=16
)(input wire I_clk,I_rst_n,I_tvalid,I_tuser,I_tlast,
 input wire [95:0] I_tdata,input wire [2:0] I_mode,
 input wire I_recognition_request,I_force_normal,
 output wire O_enable_dehaze,output reg O_dehaze_active,O_force_active,
 output reg O_stats_valid,O_fog_candidate,output reg [7:0] O_contrast);
 localparam integer GW=IMG_WIDTH/4,FG=GW*IMG_HEIGHT;
 localparam integer ENTER_TICKS=(CLK_HZ/1000)*ENTER_MS;
 localparam integer EXIT_TICKS=(CLK_HZ/1000)*EXIT_MS;
 localparam integer HOLD_TICKS=(CLK_HZ/1000)*HOLD_MS;
 reg auto_next,frame_sig;
 assign O_enable_dehaze=I_tvalid&&I_tuser ?
  (I_mode==5 || (I_mode==0&&I_recognition_request&&!I_force_normal&&auto_next)):
  O_dehaze_active;
 reg [8:0] x;reg [9:0] y;
 wire [8:0] ax=I_tuser?9'd0:x;
 wire [9:0] ay=I_tuser?10'd0:y;
 wire [7:0] r=I_tdata[23:16],g=I_tdata[15:8],b=I_tdata[7:0];
 wire [9:0] luma_sum={2'b0,r}+{1'b0,g,1'b0}+{2'b0,b};
 wire [7:0] rgb_min=(r<g?(r<b?r:b):(g<b?g:b));
 wire [7:0] rgb_max=(r>g?(r>b?r:b):(g>b?g:b));
 reg sv,su,sl,ssig,sforce;reg [8:0] sx;reg [9:0] sy;
 reg [7:0] sy8,sdark,ssat;
 reg [31:0] clock_count,last_sof,period,speriod;
 reg seen_sof;
 reg [15:0] hist[0:15];
 reg [15:0] samples;reg [23:0] dark_sum,sat_sum;
 reg [18:0] groups;
 reg scan_busy;reg [3:0] scan_index,low_bin;
 reg low_found;reg [16:0] cumulative;
 wire [16:0] next_cdf=cumulative+{1'b0,hist[scan_index]};
 wire [15:0] trim=samples>>5;
 wire [3:0] effective_low=low_found?low_bin:scan_index;
 reg [3:0] high_bin;
 reg high_found;
 wire [3:0] effective_high=high_found?high_bin:scan_index;
 wire [4:0] bin_span={1'b0,effective_high}-{1'b0,effective_low};
 wire dark_enter=dark_sum>=(({8'd0,samples}<<5)+({8'd0,samples}<<4));
 wire sat_enter=sat_sum<=(({8'd0,samples}<<5)+({8'd0,samples}<<3));
 wire dark_exit=dark_sum<({8'd0,samples}<<5);
 wire sat_exit=sat_sum>(({8'd0,samples}<<5)+({8'd0,samples}<<4)+({8'd0,samples}<<3));
 wire fog=bin_span<=5 && dark_enter && sat_enter;
 wire clear_scene=bin_span>=8 || dark_exit || sat_exit;
 reg [31:0] enter_ticks,exit_ticks,hold_ticks;
 reg [7:0] enter_count,exit_count;
 wire [32:0] enter_total={1'b0,enter_ticks}+{1'b0,speriod};
 wire [32:0] exit_total={1'b0,exit_ticks}+{1'b0,speriod};
 integer i;
 always @(posedge I_clk or negedge I_rst_n)begin
  if(!I_rst_n)begin
   auto_next<=0;frame_sig<=0;O_dehaze_active<=0;O_force_active<=0;
   O_stats_valid<=0;O_fog_candidate<=0;O_contrast<=0;
   x<=0;y<=0;sv<=0;su<=0;sl<=0;ssig<=0;sforce<=0;sx<=0;sy<=0;sy8<=0;sdark<=0;ssat<=0;
   clock_count<=0;last_sof<=0;period<=0;speriod<=0;seen_sof<=0;
   samples<=0;groups<=0;dark_sum<=0;sat_sum<=0;
   scan_busy<=0;scan_index<=0;low_bin<=0;high_bin<=0;
   low_found<=0;high_found<=0;cumulative<=0;
   enter_ticks<=0;exit_ticks<=0;hold_ticks<=0;enter_count<=0;exit_count<=0;
   for(i=0;i<16;i=i+1)hist[i]<=0;
  end else begin
   clock_count<=clock_count+1'b1;O_stats_valid<=0;
   if(hold_ticks!=0)hold_ticks<=hold_ticks-1'b1;
   sv<=I_tvalid;su<=I_tvalid&&I_tuser;sl<=I_tvalid&&I_tlast;
   sx<=ax;sy<=ay;sy8<=luma_sum[9:2];sdark<=rgb_min;ssat<=rgb_max-rgb_min;
   ssig<=I_mode==0&&I_recognition_request;sforce<=I_force_normal;
   if(I_tvalid)begin
    if(I_tuser)begin
     O_dehaze_active<=O_enable_dehaze;O_force_active<=I_force_normal;
     frame_sig<=I_mode==0&&I_recognition_request;
     period<=seen_sof?clock_count-last_sof:0;
     speriod<=seen_sof?clock_count-last_sof:0;
     if(seen_sof && clock_count-last_sof>CLK_HZ/4)begin
      speriod<=0;enter_ticks<=0;exit_ticks<=0;enter_count<=0;exit_count<=0;
     end
     last_sof<=clock_count;seen_sof<=1;
    end
    if(I_tlast)begin x<=0;y<=ay==IMG_HEIGHT-1?10'd0:ay+1'b1;end
    else begin x<=ax+1'b1;y<=ay;end
   end
   // A manual lock has priority and restarts automatic evidence on release.
   if(I_force_normal)begin auto_next<=0;enter_ticks<=0;exit_ticks<=0;enter_count<=0;exit_count<=0;end
   if(sv)begin
    if(su)begin
     if(groups!=0 && groups!=FG)begin enter_ticks<=0;exit_ticks<=0;enter_count<=0;exit_count<=0;end
     scan_busy<=0;groups<=1;samples<=1;dark_sum<={16'd0,sdark};sat_sum<={16'd0,ssat};
     for(i=0;i<16;i=i+1)hist[i]<=sy8[7:4]==i?16'd1:16'd0;
    end else begin
     groups<=groups+1'b1;
     if(sx%SAMPLE_X_STEP==0 && sy%SAMPLE_Y_STEP==0)begin
      hist[sy8[7:4]]<=hist[sy8[7:4]]+1'b1;samples<=samples+1'b1;
      dark_sum<=dark_sum+sdark;sat_sum<=sat_sum+ssat;
     end
    end
    if(sl && sy==IMG_HEIGHT-1)begin
     if(sx==GW-1 && groups==FG-1 && samples!=0)begin
      scan_busy<=1;scan_index<=0;cumulative<=0;low_found<=0;high_found<=0;
     end else begin enter_ticks<=0;exit_ticks<=0;enter_count<=0;exit_count<=0;end
    end
   end
   // A new SOF cancels unfinished statistics; never classify partial frames.
   if(scan_busy && !(sv&&su))begin
    cumulative<=next_cdf;
    if(!low_found && next_cdf>trim)begin low_bin<=scan_index;low_found<=1;end
    if(!high_found && next_cdf>=samples-trim)begin high_bin<=scan_index;high_found<=1;end
    if(scan_index==15)begin
     scan_busy<=0;O_stats_valid<=1;O_fog_candidate<=fog;
     O_contrast<=bin_span>=16?8'hff:{bin_span[3:0],4'd0};
     if(!I_force_normal && frame_sig)begin
      if(!auto_next)begin
       exit_ticks<=0;exit_count<=0;
       if(fog)begin
        enter_ticks<=enter_total>=ENTER_TICKS?ENTER_TICKS:enter_total[31:0];
        if(enter_count<255)enter_count<=enter_count+1'b1;
        if(enter_total>=ENTER_TICKS && enter_count>=ENTER_FRAMES-1 && hold_ticks==0)begin
         auto_next<=1;hold_ticks<=HOLD_TICKS;enter_ticks<=0;enter_count<=0;
        end
       end else begin enter_ticks<=0;enter_count<=0;end
      end else begin
       enter_ticks<=0;enter_count<=0;
       if(clear_scene)begin
        exit_ticks<=exit_total>=EXIT_TICKS?EXIT_TICKS:exit_total[31:0];
        if(exit_count<255)exit_count<=exit_count+1'b1;
        if(exit_total>=EXIT_TICKS && exit_count>=EXIT_FRAMES-1 && hold_ticks==0)begin
         auto_next<=0;hold_ticks<=HOLD_TICKS;exit_ticks<=0;exit_count<=0;
        end
       end else begin exit_ticks<=0;exit_count<=0;end
      end
     end else begin enter_ticks<=0;exit_ticks<=0;enter_count<=0;exit_count<=0;end
    end else scan_index<=scan_index+1'b1;
   end
  end
 end
endmodule
