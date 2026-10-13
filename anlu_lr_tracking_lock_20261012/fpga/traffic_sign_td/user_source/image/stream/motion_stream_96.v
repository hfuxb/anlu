`timescale 1ns/1ps
// Frame difference on a 320x180 luma grid for 1280x720 input. A sample is
// the mean of four horizontally adjacent pixels on every fourth row.
// Nearest-neighbor expansion highlights each moving 4x4 region in red.
// A complete prior MOT frame is required; mode entry/partial frames re-prime.
module motion_stream_96 #(
    parameter integer IMG_WIDTH=1280,IMG_HEIGHT=720,
    parameter integer DIFF_THRESHOLD=24
)(
    input wire I_clk,I_rst_n,I_tvalid,I_tuser,I_tlast,I_enable,
    input wire [95:0] I_tdata,
    output reg O_tvalid,O_tuser,O_tlast,
    output reg [95:0] O_tdata
);
    localparam integer GW=IMG_WIDTH/4;
    localparam integer SAMPLE_WORDS=GW*((IMG_HEIGHT+3)/4);
    localparam integer FRAME_GROUPS=GW*IMG_HEIGHT;
    (* ram_style="block" *) reg [7:0] previous_luma[0:SAMPLE_WORDS-1];
    reg motion_line[0:GW-1];
    reg [8:0] x_group;
    reg [9:0] y;
    reg [15:0] sample_addr;
    reg [17:0] frame_groups;
    reg frame_enable,previous_complete,frame_has_previous;
    wire [8:0] active_x=I_tuser?9'd0:x_group;
    wire [9:0] active_y=I_tuser?10'd0:y;
    wire [15:0] active_addr=I_tuser?16'd0:sample_addr;
    wire active_enable=I_tuser?I_enable:frame_enable;
    wire active_previous=I_tuser?previous_complete:frame_has_previous;
    reg [11:0] luma_sum;
    integer p;
    always @*begin
        luma_sum=0;
        for(p=0;p<4;p=p+1)
            luma_sum=luma_sum+{4'd0,I_tdata[p*24+16+:8]}+
                {3'd0,I_tdata[p*24+8+:8],1'b0}+{4'd0,I_tdata[p*24+:8]};
    end
    reg s_valid,s_user,s_last,s_enable,s_previous,s_sample,s_line_motion;
    reg [95:0] s_rgb;
    reg [7:0] s_luma,s_old_luma;
    reg [8:0] s_x;
    reg [15:0] s_addr;
    wire [8:0] difference=s_luma>=s_old_luma?{1'b0,s_luma}-{1'b0,s_old_luma}:
        {1'b0,s_old_luma}-{1'b0,s_luma};
    wire moving=s_enable && s_previous && (s_sample?difference>=DIFF_THRESHOLD:s_line_motion);
    // Read and write are on consecutive pipeline stages, avoiding a same-port
    // read/write collision for normal frames. Never reset either RAM array.
    always @(posedge I_clk)begin
        if(I_tvalid && active_enable && active_y[1:0]==0)s_old_luma<=previous_luma[active_addr];
        if(I_tvalid && active_y[1:0]!=0)s_line_motion<=motion_line[active_x];
        if(s_valid && s_enable && s_sample)begin
            previous_luma[s_addr]<=s_luma;
            motion_line[s_x]<=s_previous && difference>=DIFF_THRESHOLD;
        end
    end
    integer c;
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            x_group<=0;y<=0;sample_addr<=0;frame_groups<=0;
            frame_enable<=0;previous_complete<=0;frame_has_previous<=0;
            s_valid<=0;s_user<=0;s_last<=0;s_enable<=0;s_previous<=0;s_sample<=0;
            s_rgb<=0;s_luma<=0;s_x<=0;s_addr<=0;
            O_tvalid<=0;O_tuser<=0;O_tlast<=0;O_tdata<=0;
        end else begin
            s_valid<=I_tvalid;s_user<=I_tvalid&&I_tuser;s_last<=I_tvalid&&I_tlast;
            s_rgb<=I_tdata;s_luma<=luma_sum[11:4];s_x<=active_x;s_addr<=active_addr;
            s_enable<=active_enable;s_previous<=active_previous;s_sample<=active_y[1:0]==0;
            O_tvalid<=s_valid;O_tuser<=s_user;O_tlast<=s_last;
            for(c=0;c<4;c=c+1)
                O_tdata[c*24+:24]<=moving?{8'hff,1'b0,s_rgb[c*24+9+:7],1'b0,s_rgb[c*24+1+:7]}:s_rgb[c*24+:24];
            if(I_tvalid)begin
                if(I_tuser)begin
                    frame_enable<=I_enable;frame_has_previous<=previous_complete;
                    previous_complete<=0;frame_groups<=1;
                    sample_addr<=I_enable?16'd1:16'd0;
                end else begin
                    frame_groups<=frame_groups+1'b1;
                    if(active_enable && active_y[1:0]==0)sample_addr<=active_addr+1'b1;
                end
                if(I_tlast)begin
                    x_group<=0;y<=active_y==IMG_HEIGHT-1?10'd0:active_y+1'b1;
                    if(active_y==IMG_HEIGHT-1)
                        previous_complete<=active_enable && active_x==GW-1 && frame_groups==FRAME_GROUPS-1;
                end else begin x_group<=active_x+1'b1;y<=active_y;end
            end
        end
    end
endmodule
