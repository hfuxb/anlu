`timescale 1ns / 1ps
// Blue circular signs with white BENT arrows, left/right only.
// 4x4 sampling -> eight bounded blue-run candidates -> 16x16 white
// occupancy -> foreground IoU templates. Previous-frame ROI is measured
// in the current frame. Nearest associated candidate is preferred; confirmed
// L/R is latched until sustained target loss or reset. The pixel path is unchanged.
module traffic_sign_detector_96 #(
 parameter integer IMG_WIDTH=1280, IMG_HEIGHT=720, MIN_SCORE=50, MIN_MARGIN=12,
 parameter integer CONFIRM_FRAMES=3, HOLD_FRAMES=8
)(
 input wire I_clk,I_rst_n,I_tuser,I_tlast,I_tvalid,
 input wire [95:0] I_tdata,
 output reg O_busy,O_done,O_result_valid,
 output reg [4:0] O_result_class,
 output reg [7:0] O_result_ascii,
 output reg O_frame_drop,O_box_valid,
 output reg [10:0] O_x_min,O_x_max,
 output reg [9:0] O_y_min,O_y_max,
 output reg [7:0] O_score
);
 // bit y*16+x; independent left/right templates from the 2026-10-12
 // user reference images, normalized with the same blue/white sampling rules.
 localparam [255:0] LEFT_TEMPLATE=256'h0000000004001c001c001c001c001ce01e700ff80ffc03f800e000c000000000;
 localparam [255:0] RIGHT_TEMPLATE=256'h000000000020003800380038003807380e781ff03ff01fc00700030000000000;
 localparam [255:0] INNER_MASK=256'h0000000007e01ff81ff83ffc3ffc3ffc3ffc3ffc3ffc1ff81ff807e000000000;
 localparam INIT=0,COLLECT=1,DRAIN=2,SCORE_READ=3,SCORE_EVAL=4,
 SELECT=5,DIV_L_START=6,DIV_L=7,DIV_R_START=8,DIV_R=9,PUBLISH=10,SELECT_DONE=11;
 reg [3:0] state;
 reg [8:0] x_group;
 reg [9:0] y_pos;
 reg p_valid,p_user,p_last,p_blue,p_white;
 reg [8:0] p_x;
 reg [9:0] p_y;
 wire [8:0] in_x=I_tuser?9'd0:x_group;
 wire [9:0] in_y=I_tuser?10'd0:y_pos;
 wire sampled=p_valid && p_y[1:0]==2'd1;
 wire [7:0] cy=p_y[9:2];
 wire frame_end=p_valid && p_last && p_y==IMG_HEIGHT-1;
 function is_blue;
 input [23:0] rgb;
 reg [8:0] r,g,b;
 begin
 r={1'b0,rgb[23:16]};g={1'b0,rgb[15:8]};b={1'b0,rgb[7:0]};
 is_blue=b>=40 && b>r+12 && b>g+5 && r*4<=b*3;
 end endfunction
 function is_white;
 input [23:0] rgb;
 reg [7:0] r,g,b,lo,hi;
 begin
 r=rgb[23:16];g=rgb[15:8];b=rgb[7:0];
 lo=r<g?r:g;if(b<lo)lo=b;
 hi=r>g?r:g;if(b>hi)hi=b;
 is_white=hi>=65 && {2'b0,lo}*3>={2'b0,hi}*2;
 end endfunction
 wire [2:0] blue_count={2'b0,is_blue(I_tdata[23:0])}+{2'b0,is_blue(I_tdata[47:24])}+{2'b0,is_blue(I_tdata[71:48])}+{2'b0,is_blue(I_tdata[95:72])};
 wire [2:0] white_count={2'b0,is_white(I_tdata[23:0])}+{2'b0,is_white(I_tdata[47:24])}+{2'b0,is_white(I_tdata[71:48])}+{2'b0,is_white(I_tdata[95:72])};
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
 x_group<=0;y_pos<=0;p_valid<=0;p_user<=0;p_last<=0;p_x<=0;p_y<=0;p_blue<=0;p_white<=0;
 end else begin
 p_valid<=I_tvalid;p_user<=I_tuser;p_last<=I_tlast;
 if(I_tvalid)begin
 p_x<=in_x;p_y<=in_y;p_blue<=blue_count>=2;p_white<=white_count>=2;
 if(I_tlast)begin x_group<=0;y_pos<=in_y+1'b1;end
 else begin x_group<=in_x+1'b1;y_pos<=in_y;end
 end end end

 // Bounded run clustering, not general connected-component labelling.
 reg run_valid;
 reg [8:0] run_start,run_end;
 reg [7:0] c_valid;
 reg [8:0] c_x0[0:7],c_x1[0:7];
 reg [7:0] c_y0[0:7],c_y1[0:7];
 reg [15:0] c_area[0:7];
 wire run_event=sampled && run_valid && (!p_blue || p_last) && state==COLLECT;
 wire [8:0] rx1=p_blue && p_last?p_x:run_end;
 wire [9:0] run_length={1'b0,rx1}-{1'b0,run_start}+1'b1;
 integer slot,free_slot,k;
 reg [7:0] run_matches;
 always @* begin
 slot=-1;free_slot=-1;run_matches=0;
 for(k=0;k<8;k=k+1)begin
 if(!c_valid[k] && free_slot<0)free_slot=k;
 if(c_valid[k] && {1'b0,cy}<={1'b0,c_y1[k]}+9'd2 &&
 {1'b0,run_start}<={1'b0,c_x1[k]}+10'd2 && {1'b0,rx1}+10'd2>={1'b0,c_x0[k]})begin
 run_matches[k]=1;if(slot<0)slot=k;
 end end
 if(slot<0)slot=free_slot;
 end
 // Stage 1 snapshots matching components, Stage 2 balanced-tree reduction.
 // Valid runs have >=2 blue groups: consecutive events are >=3 clocks apart,
 // so the previous update is committed before the next match lookup.
 reg merge_valid;
 reg [2:0] merge_slot;
 reg [7:0] merge_mask;
 reg [9:0] merge_length;
 reg [7:0] merge_y;
 reg [8:0] mx0[0:7],mx1[0:7];
 reg [7:0] my0[0:7];
 reg [15:0] ma[0:7];
 wire [8:0] tree_x0[1:15],tree_x1[1:15];
 wire [7:0] tree_y0[1:15];
 wire [16:0] tree_area[1:15];
 genvar g;
 generate
 for(g=0;g<8;g=g+1)begin:merge_leaves
 assign tree_x0[g+8]=mx0[g];assign tree_x1[g+8]=mx1[g];
 assign tree_y0[g+8]=my0[g];assign tree_area[g+8]={1'b0,ma[g]};
 end
 for(g=1;g<8;g=g+1)begin:merge_tree
 assign tree_x0[g]=tree_x0[g*2]<tree_x0[g*2+1]?tree_x0[g*2]:tree_x0[g*2+1];
 assign tree_x1[g]=tree_x1[g*2]>tree_x1[g*2+1]?tree_x1[g*2]:tree_x1[g*2+1];
 assign tree_y0[g]=tree_y0[g*2]<tree_y0[g*2+1]?tree_y0[g*2]:tree_y0[g*2+1];
 assign tree_area[g]=tree_area[g*2]+tree_area[g*2+1];
 end
 endgenerate
 wire [16:0] merged_area=tree_area[1]+merge_length;
 integer j;
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
 run_valid<=0;run_start<=0;run_end<=0;c_valid<=0;
 merge_valid<=0;merge_slot<=0;merge_mask<=0;merge_length<=0;merge_y<=0;
 for(j=0;j<8;j=j+1)begin
 c_x0[j]<=0;c_x1[j]<=0;c_y0[j]<=0;c_y1[j]<=0;c_area[j]<=0;
 mx0[j]<=0;mx1[j]<=0;my0[j]<=0;ma[j]<=0;
 end
 end else begin
 merge_valid<=run_event && run_length>=2 && slot>=0;
 if(run_event && run_length>=2 && slot>=0)begin
 merge_slot<=slot;merge_mask<=run_matches;merge_length<=run_length;merge_y<=cy;
 for(j=0;j<8;j=j+1)begin
 mx0[j]<=run_matches[j] && c_x0[j]<run_start?c_x0[j]:run_start;
 mx1[j]<=run_matches[j] && c_x1[j]>rx1?c_x1[j]:rx1;
 my0[j]<=run_matches[j] && c_y0[j]<cy?c_y0[j]:cy;
 ma[j]<=run_matches[j]?c_area[j]:16'd0;
 end end
 if(p_valid && p_user)begin run_valid<=0;c_valid<=0;merge_valid<=0;end
 else begin
 if(state==COLLECT && sampled)begin
 if(p_blue && !p_last)begin
 if(!run_valid)run_start<=p_x;
 run_valid<=1;run_end<=p_x;
 end else run_valid<=0;
 end
 if(merge_valid && (state==COLLECT || state==DRAIN))begin
 for(j=0;j<8;j=j+1)if(merge_mask[j])c_valid[j]<=0;
 c_valid[merge_slot]<=1;c_x0[merge_slot]<=tree_x0[1];c_x1[merge_slot]<=tree_x1[1];
 c_y0[merge_slot]<=tree_y0[1];c_y1[merge_slot]<=merge_y;
 c_area[merge_slot]<=merged_area[16]?16'hffff:merged_area[15:0];
 end end end end
 reg track_valid;
 reg [8:0] tx0,tx1,tw;
 reg [7:0] ty0,ty1,th;
 // Compare to multiples of span; no combinational per-pixel divider.
 function [3:0] bin16;
 input [8:0] delta,span;
 integer n;
 reg [12:0] scaled,b1,b2,b4,b8,threshold;
 begin scaled={delta,4'b0};bin16=0;
 for(n=1;n<16;n=n+1)begin
 b1=(n&1)?{4'b0,span}:13'd0;b2=(n&2)?{3'b0,span,1'b0}:13'd0;
 b4=(n&4)?{2'b0,span,2'b0}:13'd0;b8=(n&8)?{1'b0,span,3'b0}:13'd0;
 threshold=(b1+b2)+(b4+b8);
 if(scaled>=threshold)bin16=n;
 end
 end endfunction
 reg sample_valid,sample_white;
 reg [7:0] sample_addr;
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin sample_valid<=0;sample_white<=0;sample_addr<=0;end
 else begin
 sample_valid<=sampled && state==COLLECT && track_valid && p_x>=tx0 && p_x<=tx1 && cy>=ty0 && cy<=ty1;
 sample_white<=p_white;
 sample_addr<={bin16({1'b0,cy}-{1'b0,ty0},{1'b0,th}),bin16(p_x-tx0,tw)};
 end end
 // Synchronous 256x16 RAM: {white samples,total samples}.
 // RMW forwarding for repeated cell addresses on adjacent cycles.
 reg [15:0] cells[0:255];
 reg [15:0] ram_q,last_write_data;
 reg [7:0] rmw_addr,last_write_addr,scan_addr;
 reg rmw_valid,rmw_white,last_write_valid;
 wire [7:0] read_addr=state==SCORE_READ || state==SCORE_EVAL?scan_addr:sample_addr;
 wire [15:0] rmw_base=last_write_valid && last_write_addr==rmw_addr?last_write_data:ram_q;
 wire [7:0] next_total=rmw_base[7:0]==255?8'd255:rmw_base[7:0]+1'b1;
 wire [7:0] next_white=rmw_white && rmw_base[15:8]!=255?rmw_base[15:8]+1'b1:rmw_base[15:8];
 wire clear_cell=state==INIT || state==SCORE_EVAL;
 wire write_cell=clear_cell || (rmw_valid && (state==COLLECT || state==DRAIN));
 wire [7:0] write_addr=clear_cell?scan_addr:rmw_addr;
 wire [15:0] write_data=clear_cell?16'd0:{next_white,next_total};
 always @(posedge I_clk)begin
 ram_q<=cells[read_addr];if(write_cell)cells[write_addr]<=write_data;
 end
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
 rmw_valid<=0;rmw_white<=0;rmw_addr<=0;last_write_valid<=0;last_write_addr<=0;last_write_data<=0;
 end else begin
 rmw_valid<=sample_valid;rmw_white<=sample_white;rmw_addr<=sample_addr;
 last_write_valid<=write_cell;last_write_addr<=write_addr;last_write_data<=write_data;
 end end
 wire cell_white=ram_q[7:0]!=0 && {2'b0,ram_q[15:8]}*4>={2'b0,ram_q[7:0]};
 wire mask_cell=INNER_MASK[scan_addr];
 wire template_l=LEFT_TEMPLATE[scan_addr];
 wire template_r=RIGHT_TEMPLATE[scan_addr];
 reg [8:0] intersection_l,union_l,intersection_r,union_r,white_cells;
 reg [2:0] drain_count,select_index;
 reg best_valid,best_associated;
 reg locked;
 reg [7:0] locked_ascii,vote_ascii,vote_count,missing_count;
 reg assoc_valid;
 reg [10:0] assoc_distance;
 reg [8:0] assoc_x0,assoc_x1;
 reg [7:0] assoc_y0,assoc_y1;
 reg [15:0] best_area;
 reg [8:0] best_x0,best_x1;
 reg [7:0] best_y0,best_y1;
 wire [9:0] cw={1'b0,c_x1[select_index]}-{1'b0,c_x0[select_index]}+1'b1;
 wire [8:0] ch={1'b0,c_y1[select_index]}-{1'b0,c_y0[select_index]}+1'b1;
 wire [18:0] box_area=cw*ch;
 wire candidate_ok=c_valid[select_index] && cw>=16 && ch>=16 && cw<=128 && ch<=128 &&
 cw*3>=ch*2 && cw*2<=ch*3 && c_area[select_index]*4>=box_area && c_area[select_index]<box_area;
 // Target association uses center and span in 4-pixel coordinates.
 // A frame may change size by <=25%; center motion <=1/4 span +16 pixels.
 // No extra DSP multiplier or pixel-stream latency is introduced.
 wire [9:0] cand_center_x={1'b0,c_x0[select_index]}+{1'b0,c_x1[select_index]};
 wire [9:0] prev_center_x={1'b0,tx0}+{1'b0,tx1};
 wire [8:0] cand_center_y={1'b0,c_y0[select_index]}+{1'b0,c_y1[select_index]};
 wire [8:0] prev_center_y={1'b0,ty0}+{1'b0,ty1};
 wire [9:0] center_dx=cand_center_x>=prev_center_x?cand_center_x-prev_center_x:prev_center_x-cand_center_x;
 wire [8:0] center_dy=cand_center_y>=prev_center_y?cand_center_y-prev_center_y:prev_center_y-cand_center_y;
 wire [10:0] distance={1'b0,center_dx}+{2'b0,center_dy};
 wire associated=track_valid && center_dx<=({1'b0,tw}>>1)+10'd8 &&
 center_dy<=({1'b0,th}>>1)+9'd8 &&
 cw>={1'b0,tw}-({1'b0,tw}>>2) && cw<={1'b0,tw}+({1'b0,tw}>>2) &&
 ch>={1'b0,th}-({1'b0,th}>>2) && ch<={1'b0,th}+({1'b0,th}>>2);
 // Serial divider, 15 clocks per direction. Scores are IoU, not probability.
 reg [14:0] dividend,quotient;
 reg [9:0] remainder;
 reg [8:0] divisor;
 reg [3:0] divide_count;
 reg [7:0] score_l,score_r;
 wire [10:0] trial_remainder={remainder,dividend[14]};
 wire subtract_ok=trial_remainder>={2'b0,divisor};
 wire [14:0] next_quotient={quotient[13:0],subtract_ok};
 wire [7:0] best_score=score_l>=score_r?score_l:score_r;
 wire [7:0] score_margin=score_l>=score_r?score_l-score_r:score_r-score_l;
 wire [7:0] frame_ascii=score_l>score_r?"L":"R";
 wire accept_result=track_valid && best_valid && best_associated && best_score>=MIN_SCORE && score_margin>=MIN_MARGIN && white_cells>=10;
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
 state<=INIT;scan_addr<=0;track_valid<=0;tx0<=0;tx1<=0;ty0<=0;ty1<=0;tw<=1;th<=1;
 O_busy<=1;O_done<=0;O_result_valid<=0;O_result_class<=0;O_result_ascii<="?";O_frame_drop<=0;
 O_box_valid<=0;O_x_min<=0;O_x_max<=0;O_y_min<=0;O_y_max<=0;O_score<=0;
 intersection_l<=0;union_l<=0;intersection_r<=0;union_r<=0;white_cells<=0;
 locked<=0;locked_ascii<="?";vote_ascii<="?";vote_count<=0;missing_count<=0;
 assoc_valid<=0;assoc_distance<=11'h7ff;assoc_x0<=0;assoc_x1<=0;assoc_y0<=0;assoc_y1<=0;
 drain_count<=0;select_index<=0;best_valid<=0;best_associated<=0;best_area<=0;best_x0<=0;best_x1<=0;best_y0<=0;best_y1<=0;
 dividend<=0;quotient<=0;remainder<=0;divisor<=1;divide_count<=0;score_l<=0;score_r<=0;
 end else begin
 O_done<=0;O_frame_drop<=0;
 if(p_valid && p_user && state!=COLLECT)O_frame_drop<=1;
 case(state)
 INIT:begin scan_addr<=scan_addr+1'b1;if(scan_addr==255)begin state<=COLLECT;O_busy<=0;end end
 COLLECT:if(frame_end)begin
 state<=DRAIN;drain_count<=0;O_busy<=1;
 intersection_l<=0;union_l<=0;intersection_r<=0;union_r<=0;white_cells<=0;
 end
 DRAIN:begin drain_count<=drain_count+1'b1;if(drain_count==3)begin state<=SCORE_READ;scan_addr<=0;end end
 SCORE_READ:state<=SCORE_EVAL;
 SCORE_EVAL:begin
 if(mask_cell)begin
 if(cell_white)white_cells<=white_cells+1'b1;
 if(cell_white && template_l)intersection_l<=intersection_l+1'b1;
 if(cell_white || template_l)union_l<=union_l+1'b1;
 if(cell_white && template_r)intersection_r<=intersection_r+1'b1;
 if(cell_white || template_r)union_r<=union_r+1'b1;
 end
 scan_addr<=scan_addr+1'b1;
 if(scan_addr==255)begin
 state<=SELECT;select_index<=0;best_valid<=0;best_area<=0;
 best_associated<=0;assoc_valid<=0;assoc_distance<=11'h7ff;
 end
 else state<=SCORE_READ;
 end
 SELECT:begin
 if(candidate_ok && c_area[select_index]>best_area)begin
 best_valid<=1;best_area<=c_area[select_index];best_x0<=c_x0[select_index];best_x1<=c_x1[select_index];
 best_y0<=c_y0[select_index];best_y1<=c_y1[select_index];
 end
 if(candidate_ok && associated && (!assoc_valid || distance<assoc_distance))begin
 assoc_valid<=1;assoc_distance<=distance;assoc_x0<=c_x0[select_index];assoc_x1<=c_x1[select_index];
 assoc_y0<=c_y0[select_index];assoc_y1<=c_y1[select_index];
 end
 select_index<=select_index+1'b1;if(select_index==7)state<=SELECT_DONE;
 end
 SELECT_DONE:begin
 // Prefer the same target even when a larger distant blue object appears.
 // During lock, an unrelated candidate cannot replace the retained target.
 if(assoc_valid)begin
 best_valid<=1;best_associated<=1;
 best_x0<=assoc_x0;best_x1<=assoc_x1;best_y0<=assoc_y0;best_y1<=assoc_y1;
 end else if(locked)best_valid<=0;
 state<=DIV_L_START;
 end
 DIV_L_START:begin
 dividend<=intersection_l*15'd100;divisor<=union_l==0?9'd1:union_l;
 quotient<=0;remainder<=0;divide_count<=0;state<=DIV_L;
 end
 DIV_R_START:begin
 dividend<=intersection_r*15'd100;divisor<=union_r==0?9'd1:union_r;
 quotient<=0;remainder<=0;divide_count<=0;state<=DIV_R;
 end
 DIV_L,DIV_R:begin
 dividend<={dividend[13:0],1'b0};quotient<=next_quotient;
 remainder<=subtract_ok?trial_remainder-divisor:trial_remainder;
 divide_count<=divide_count+1'b1;
 if(divide_count==14)begin
 if(state==DIV_L)begin score_l<=next_quotient[7:0];state<=DIV_R_START;end
 else begin score_r<=next_quotient[7:0];state<=PUBLISH;end
 end end
 PUBLISH:begin
 O_done<=1;O_result_valid<=0;O_result_class<=0;O_result_ascii<="?";
 O_score<=track_valid && best_associated?best_score:8'd0;
 if(locked)begin
   if(best_associated)begin
     // Blue face is still associated: keep the confirmed direction even if
     // arrow score falls to zero, or a single frame suggests the other side.
     missing_count<=0;O_box_valid<=1;O_result_valid<=1;
     O_result_ascii<=locked_ascii;O_result_class<=locked_ascii=="L"?5'd1:5'd2;
     O_x_min<={best_x0,2'b00};O_x_max<={best_x1,2'b11};
     O_y_min<={best_y0,2'b00};O_y_max<={best_y1,2'b11};
     track_valid<=1;tx0<=best_x0;tx1<=best_x1;ty0<=best_y0;ty1<=best_y1;
     tw<=best_x1-best_x0+1'b1;th<=best_y1-best_y0+1'b1;
   end else if(missing_count<HOLD_FRAMES-1)begin
     // Brief occlusion: retain both the last box and L/R, for a bounded time.
     missing_count<=missing_count+1'b1;O_box_valid<=1;O_result_valid<=1;
     O_result_ascii<=locked_ascii;O_result_class<=locked_ascii=="L"?5'd1:5'd2;
     O_x_min<={tx0,2'b00};O_x_max<={tx1,2'b11};
     O_y_min<={ty0,2'b00};O_y_max<={ty1,2'b11};
   end else begin
     // The eighth consecutive missing frame releases the target and direction.
     locked<=0;locked_ascii<="?";missing_count<=0;
     vote_count<=0;vote_ascii<="?";track_valid<=0;O_box_valid<=0;
   end
 end else begin
   missing_count<=0;
   // Acquisition stays '?' until the same associated direction is confirmed.
   O_box_valid<=best_valid;
   O_x_min<={best_x0,2'b00};O_x_max<={best_x1,2'b11};
   O_y_min<={best_y0,2'b00};O_y_max<={best_y1,2'b11};
   track_valid<=best_valid;tx0<=best_x0;tx1<=best_x1;ty0<=best_y0;ty1<=best_y1;
   tw<=best_x1-best_x0+1'b1;th<=best_y1-best_y0+1'b1;
   if(accept_result)begin
     if(CONFIRM_FRAMES<=1 || (vote_ascii==frame_ascii && vote_count>=CONFIRM_FRAMES-1))begin
       locked<=1;locked_ascii<=frame_ascii;vote_count<=0;
       O_result_valid<=1;O_result_ascii<=frame_ascii;
       O_result_class<=frame_ascii=="L"?5'd1:5'd2;
     end else begin
       vote_ascii<=frame_ascii;vote_count<=vote_ascii==frame_ascii?vote_count+1'b1:8'd1;
     end
   end else begin vote_count<=0;vote_ascii<="?";end
 end
 state<=COLLECT;O_busy<=0;
 end
 default:state<=INIT;
 endcase end end
endmodule

