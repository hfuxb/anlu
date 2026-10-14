`timescale 1ns/1ps
module tb_override;
reg clk=0,rst=0,button=1;always #5 clk=~clk;wire lock_normal;
recognition_override_button #(.DEBOUNCE_CYCLES(5)) dut(.I_clk(clk),.I_rst_n(rst),.I_button_n(button),.O_force_normal(lock_normal));
initial begin
 repeat(4)@(negedge clk);rst=1;
 button=0;repeat(2)@(negedge clk);button=1;repeat(12)@(negedge clk);
 if(lock_normal)$fatal(1,"bounce toggled");
 button=0;repeat(20)@(negedge clk);if(!lock_normal)$fatal(1,"press failed");
 repeat(50)@(negedge clk);if(!lock_normal)$fatal(1,"hold retoggled");
 button=1;repeat(20)@(negedge clk);if(!lock_normal)$fatal(1,"release toggled");
 button=0;repeat(20)@(negedge clk);if(lock_normal)$fatal(1,"second press failed");
 $display("PASS KEY3 override debounce, one toggle per press, long-hold persistence, AUTO return");$finish;
end
endmodule
