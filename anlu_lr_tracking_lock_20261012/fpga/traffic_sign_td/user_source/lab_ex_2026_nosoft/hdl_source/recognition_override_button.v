`timescale 1ns/1ps
// KEY3: debounced press toggles persistent FORCE NORMAL / AUTO.
module recognition_override_button #(parameter integer DEBOUNCE_CYCLES=480000)(
 input wire I_clk,I_rst_n,I_button_n,output reg O_force_normal);
 localparam integer CW=DEBOUNCE_CYCLES<=1?1:$clog2(DEBOUNCE_CYCLES);
 (* ASYNC_REG="TRUE" *) reg sync1,sync2;
 reg stable;reg [CW-1:0] count;
 always @(posedge I_clk or negedge I_rst_n)begin
  if(!I_rst_n)begin sync1<=1;sync2<=1;stable<=1;count<=0;O_force_normal<=0;end
  else begin
   sync1<=I_button_n;sync2<=sync1;
   if(sync2==stable)count<=0;
   else if(count==DEBOUNCE_CYCLES-1)begin
    stable<=sync2;count<=0;
    if(!sync2)O_force_normal<=!O_force_normal;
   end else count<=count+1'b1;
  end
 end
endmodule
