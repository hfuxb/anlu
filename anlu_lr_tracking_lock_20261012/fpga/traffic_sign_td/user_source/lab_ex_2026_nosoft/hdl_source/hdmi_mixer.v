module hdmi_mixer #(
    parameter H_OFFSET = 128,
    parameter V_OFFSET = 60,
    parameter IMG_WIDTH = 1280,
    parameter IMG_HEIGHT = 720,
    parameter integer DEBUG_MODE = 0,
    parameter integer ENABLE_LATENCY = 0,
    parameter integer HDMI_CLK_HZ = 75000000,
    parameter integer LATENCY_REFRESH_MS = 1000,
    parameter integer LATENCY_STALE_MS = 1500
)(
    input wire        I_clk,
    input wire        I_rst_n,

    input wire        I_video_vsync,
    input wire        I_video_hsync,
    input wire        I_video_de,
    input wire        I_video_user,
    input wire        I_video_last,

    input wire[3:0]   I_debug_status,
    input wire [2:0]  I_image_mode,

// 路牌识别状态来自摄像头时钟域，结果toggle和ASCII由顶层CDC模块提供。
// OSD只显示单字符：L、R或?；接口名保留 traffic_sign_* 以兼容成员3的顶层连接。
    input wire        I_traffic_sign_mode,
    input wire        I_traffic_sign_busy,
    input wire        I_traffic_sign_result_toggle,
    input wire [7:0]  I_traffic_sign_result_ascii,
    input wire [50:0] I_traffic_sign_metadata,
    input wire [19:0] I_latency_bcd,
    input wire I_latency_valid,I_latency_overflow,I_latency_update,

    output wire       O_video_rd_en,
    input wire[23:0]  I_video_rd_data,

    output reg        O_hdmi_vsync,
    output reg        O_hdmi_hsync,
    output reg        O_hdmi_de,
    output reg[23:0]  O_hdmi_data
);

    reg        S_video_vsync_1d;
    reg        S_video_vsync_2d;
    reg        S_video_hsync_1d;
    reg        S_video_hsync_2d;
    reg        S_video_de_1d;
    reg        S_video_de_2d;
    reg [23:0] S_video_data_1d;
    reg [23:0] S_video_data_2d;
    reg [11:0] S_x;
    reg [11:0] S_y;
    reg [11:0] S_x_1d;
    reg [11:0] S_x_2d;
    reg [11:0] S_y_1d;
    reg [11:0] S_y_2d;

    localparam integer LATENCY_X=IMG_WIDTH-208;
    wire [19:0] S_latency_bcd;
    wire S_latency_valid,S_latency_overflow;
    reg [7:0] S_latency_char;
    wire [11:0] S_latency_x=S_x_2d-LATENCY_X;
    wire [3:0] S_latency_cell=S_latency_x[7:4];
    wire [3:0] S_latency_row=S_y_2d-12'd16;
    wire [15:0] S_latency_row_bits;
    // Measurement stays per frame. Only the readable OSD value is throttled.
    generate if(ENABLE_LATENCY != 0)begin: g_latency_display
        video_latency_display #(.CLK_HZ(HDMI_CLK_HZ),
            .REFRESH_MS(LATENCY_REFRESH_MS),.STALE_MS(LATENCY_STALE_MS)) u_display(
            .I_clk(I_clk),.I_rst_n(I_rst_n),.I_frame_start(I_video_user),
            .I_bcd20(I_latency_bcd),.I_valid(I_latency_valid),
            .I_overflow(I_latency_overflow),.I_update(I_latency_update),
            .O_bcd20(S_latency_bcd),.O_valid(S_latency_valid),.O_overflow(S_latency_overflow));
    end else begin: g_no_latency_display
        assign S_latency_bcd=20'd0;
        assign S_latency_valid=1'b0;
        assign S_latency_overflow=1'b0;
    end endgenerate
    always @* begin
        S_latency_char=8'h20;
        case(S_latency_cell)
            0:S_latency_char="L";
            1:S_latency_char="A";
            2:S_latency_char="T";
            3:S_latency_char=8'h3a;
            4:S_latency_char=!S_latency_valid?8'h2d:S_latency_overflow?"O":8'h30+S_latency_bcd[19:16];
            5:S_latency_char=!S_latency_valid?8'h2d:S_latency_overflow?"V":8'h30+S_latency_bcd[15:12];
            6:S_latency_char=!S_latency_valid?8'h2d:S_latency_overflow?"F":8'h30+S_latency_bcd[11:8];
            7:S_latency_char=!S_latency_valid?8'h2d:S_latency_overflow?"L":8'h30+S_latency_bcd[7:4];
            8:S_latency_char=S_latency_valid&&S_latency_overflow?8'h20:8'h2e;
            9:S_latency_char=!S_latency_valid?8'h2d:S_latency_overflow?8'h20:8'h30+S_latency_bcd[3:0];
            10:S_latency_char="M";
            11:S_latency_char="S";
        endcase
    end
    osd_char_lib u_latency_font(.I_char(S_latency_char),.I_row(S_latency_row),.O_row_bits(S_latency_row_bits));

    // One coherent frame-latched metadata packet: box, match score, direction.
    reg [50:0] S_sign_meta_frame;
    reg [7:0] S_sign_ascii_frame;
    wire S_sign_box = S_sign_meta_frame[50];
    wire [10:0] S_sign_x0 = S_sign_meta_frame[49:39];
    wire [10:0] S_sign_x1 = S_sign_meta_frame[38:28];
    wire [9:0] S_sign_y0 = S_sign_meta_frame[27:18];
    wire [9:0] S_sign_y1 = S_sign_meta_frame[17:8];
    wire [7:0] S_sign_score = S_sign_meta_frame[7:0];
    wire S_sign_accepted = S_sign_ascii_frame=="L" || S_sign_ascii_frame=="R";
    reg        S_traffic_sign_mode_sync1;
    reg        S_traffic_sign_mode_sync2;
    reg        S_traffic_sign_mode_frame;
    reg [2:0]  S_image_mode_sync1;
    reg [2:0]  S_image_mode_sync2;
    reg [2:0]  S_image_mode_frame;
    reg        S_traffic_sign_toggle_sync1;
    reg        S_traffic_sign_toggle_sync2;
    reg        S_traffic_sign_toggle_seen;
    reg        S_traffic_sign_result_ready;
    reg        S_sign_ready_frame;
    wire       S_sign_mode_sync = S_traffic_sign_mode_sync2 && S_image_mode_sync2==3'd0;
    wire       S_sign_overlay_enable = S_traffic_sign_mode_frame && S_image_mode_frame==3'd0;

    // Center-coordinate label belongs to the exact same HDMI-frame packet as
    // the box/direction. Decimal conversion runs for 12 clocks at frame start;
    // it never adds a divider or a wide multiplier to the pixel-to-RGB path.
    localparam integer COORD_LABEL_W = 208; // "L (0640,0360)": 13 x 16 pixels
    localparam integer COORD_LABEL_H = 20;
    reg [11:0] S_coord_bin_x,S_coord_bin_y;
    reg [15:0] S_coord_work_x,S_coord_work_y;
    reg [15:0] S_coord_bcd_x,S_coord_bcd_y;
    reg [3:0] S_coord_step;
    reg S_coord_busy,S_coord_ready;
    reg [11:0] S_coord_label_x,S_coord_label_y;
    reg [7:0] S_coord_char;
    wire [11:0] S_coord_local_x=S_x_2d-S_coord_label_x;
    wire [11:0] S_coord_local_y=S_y_2d-S_coord_label_y;
    wire [3:0] S_coord_cell=S_coord_local_x[7:4];
    wire [3:0] S_coord_font_row=S_coord_local_y-12'd2;
    wire [15:0] S_coord_row_bits;
    wire [11:0] S_incoming_center_sum_x={1'b0,I_traffic_sign_metadata[49:39]}+
                                            {1'b0,I_traffic_sign_metadata[38:28]};
    wire [10:0] S_incoming_center_sum_y={1'b0,I_traffic_sign_metadata[27:18]}+
                                            {1'b0,I_traffic_sign_metadata[17:8]};
    function [15:0] F_coord_bcd_shift;
        input [15:0] digits;
        input next_bit;
        reg [15:0] adjusted;
        integer digit;
        begin
            adjusted=digits;
            for(digit=0;digit<4;digit=digit+1)
                if(digits[digit*4+:4]>=5)
                    adjusted[digit*4+:4]=digits[digit*4+:4]+4'd3;
            F_coord_bcd_shift={adjusted[14:0],next_bit};
        end
    endfunction
    wire [15:0] S_coord_next_x=F_coord_bcd_shift(S_coord_work_x,S_coord_bin_x[11]);
    wire [15:0] S_coord_next_y=F_coord_bcd_shift(S_coord_work_y,S_coord_bin_y[11]);
    function [11:0] F_coord_label_y;
        input [9:0] box_y0;
        reg [11:0] position;
        begin
            if(box_y0>=22)position={2'b0,box_y0}-12'd22;
            else position={2'b0,box_y0}+12'd2;
            if(position>IMG_HEIGHT-COORD_LABEL_H)position=IMG_HEIGHT-COORD_LABEL_H;
            F_coord_label_y=position;
        end
    endfunction
    function [11:0] F_coord_label_x;
        input [10:0] box_x0;
        input [11:0] label_y;
        reg [11:0] position;
        begin
            position={1'b0,box_x0};
            if(position>IMG_WIDTH-COORD_LABEL_W)position=IMG_WIDTH-COORD_LABEL_W;
            // Keep the existing logo, count/mode/status and LAT fields readable.
            // These adjustments affect label position only, never the box or its
            // reported coordinates, and all positions are registered per frame.
            if(label_y<160 && position<160 && IMG_WIDTH>=368)position=160;
            if(label_y<240 && label_y+COORD_LABEL_H>120 &&
               position<591 && position+COORD_LABEL_W>375 && IMG_WIDTH>=799)
                position=591;
            if(ENABLE_LATENCY && label_y<40 && label_y+COORD_LABEL_H>8 &&
               position+COORD_LABEL_W>LATENCY_X-8 && IMG_WIDTH>=424)
                position=LATENCY_X-8-COORD_LABEL_W;
            F_coord_label_x=position;
        end
    endfunction
    wire [11:0] S_incoming_label_y=F_coord_label_y(I_traffic_sign_metadata[27:18]);
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)begin
            S_coord_bin_x<=0;S_coord_bin_y<=0;
            S_coord_work_x<=0;S_coord_work_y<=0;
            S_coord_bcd_x<=0;S_coord_bcd_y<=0;
            S_coord_step<=0;S_coord_busy<=0;S_coord_ready<=0;
            S_coord_label_x<=0;S_coord_label_y<=0;
        end else if(I_video_user)begin
            S_coord_ready<=0;S_coord_step<=0;
            S_coord_work_x<=0;S_coord_work_y<=0;
            if(S_sign_mode_sync && S_traffic_sign_mode_frame && S_traffic_sign_result_ready &&
               I_traffic_sign_metadata[50] &&
               (I_traffic_sign_result_ascii=="L" || I_traffic_sign_result_ascii=="R"))begin
                S_coord_bin_x<={1'b0,S_incoming_center_sum_x[11:1]};
                S_coord_bin_y<={2'b0,S_incoming_center_sum_y[10:1]};
                S_coord_label_x<=F_coord_label_x(I_traffic_sign_metadata[49:39],S_incoming_label_y);
                S_coord_label_y<=S_incoming_label_y;
                S_coord_busy<=1;
            end else begin
                S_coord_busy<=0;S_coord_bcd_x<=0;S_coord_bcd_y<=0;
            end
        end else if(S_coord_busy)begin
            S_coord_bin_x<={S_coord_bin_x[10:0],1'b0};
            S_coord_bin_y<={S_coord_bin_y[10:0],1'b0};
            S_coord_work_x<=S_coord_next_x;S_coord_work_y<=S_coord_next_y;
            if(S_coord_step==11)begin
                S_coord_bcd_x<=S_coord_next_x;S_coord_bcd_y<=S_coord_next_y;
                S_coord_busy<=0;S_coord_ready<=1;
            end else S_coord_step<=S_coord_step+1'b1;
        end
    end
    always @* begin
        S_coord_char=8'h20;
        case(S_coord_cell)
            0:S_coord_char=S_sign_ascii_frame;
            2:S_coord_char=8'h28;
            3:S_coord_char=8'h30+S_coord_bcd_x[15:12];
            4:S_coord_char=8'h30+S_coord_bcd_x[11:8];
            5:S_coord_char=8'h30+S_coord_bcd_x[7:4];
            6:S_coord_char=8'h30+S_coord_bcd_x[3:0];
            7:S_coord_char=8'h2c;
            8:S_coord_char=8'h30+S_coord_bcd_y[15:12];
            9:S_coord_char=8'h30+S_coord_bcd_y[11:8];
            10:S_coord_char=8'h30+S_coord_bcd_y[7:4];
            11:S_coord_char=8'h30+S_coord_bcd_y[3:0];
            12:S_coord_char=8'h29;
        endcase
    end
    osd_char_lib u_coordinate_font(.I_char(S_coord_char),.I_row(S_coord_font_row),.O_row_bits(S_coord_row_bits));
    reg [3:0] S_score_digit,S_score_tens_frame,S_score_ones_frame;
    reg S_score_hundred_frame;
    function [3:0] score_tens;
        input [7:0] value;
        begin
            if(value>=100)score_tens=0;
            else if(value>=90)score_tens=9;
            else if(value>=80)score_tens=8;
            else if(value>=70)score_tens=7;
            else if(value>=60)score_tens=6;
            else if(value>=50)score_tens=5;
            else if(value>=40)score_tens=4;
            else if(value>=30)score_tens=3;
            else if(value>=20)score_tens=2;
            else if(value>=10)score_tens=1;
            else score_tens=0;
        end
    endfunction
    wire [3:0] S_incoming_tens=score_tens(I_traffic_sign_metadata[7:0]);
    wire [7:0] S_incoming_ten_value=({4'd0,S_incoming_tens}<<3)+({4'd0,S_incoming_tens}<<1);
    reg        S_osd_hit;
    reg [23:0] S_osd_color;
    reg [11:0] S_logo_x;
    reg [11:0] S_logo_y;
    reg [3:0]  S_char_idx;
    reg [2:0]  S_char_row;
    reg [2:0]  S_char_col;
    reg [4:0]  S_char_bits;
    reg        S_char_on;
    reg        S_logo_blue_on;
    reg        S_logo_red_on;
    reg [11:0] S_logo_tmp_y;
    reg [3:0]  S_logo_red_band;
    reg [11:0] S_logo_red_x_start;
    reg [11:0] S_logo_red_x_end;
    reg [14:0] S_logo_addr;
    wire[24:0] S_logo_pixel;
    reg [31:0] S_frame_cnt;
    reg [11:0] S_dyn_x;
    reg [11:0] S_dyn_y;
    reg [3:0]  S_dyn_char;
    reg [2:0]  S_dyn_col;
    reg [2:0]  S_dyn_row;
    reg [4:0]  S_dyn_bits;
    reg [3:0]  S_dyn_digit_idx;
    reg [11:0] S_dyn_digit_x;
    reg [6:0]  S_dyn_seg;
    reg [3:0]  S_cnt_d0;
    reg [3:0]  S_cnt_d1;
    reg [3:0]  S_cnt_d2;
    reg [3:0]  S_cnt_d3;
    reg [3:0]  S_cnt_d4;
    reg [3:0]  S_cnt_d5;
    reg [2:0]  S_lbl_row;
    reg [2:0]  S_lbl_col;
    reg [1:0]  S_lbl_idx;
    reg [4:0]  S_lbl_bits;
    reg [6:0]  S_lbl_local_x;
    reg [3:0]  S_dyn_dec_digit;
    reg [4:0]  S_cn_local_x;
    reg [4:0]  S_cn_local_y;
    reg [3:0]  S_cn_col;
    reg [3:0]  S_cn_row;
    reg [15:0] S_cn_row_bits;
    reg        S_cn_on;
    reg [9:0]  S_cn_scale_x;
    reg [9:0]  S_cn_scale_y;
    reg [7:0]  S_pf_char;
    reg [4:0]  S_pf_local_x;
    reg [4:0]  S_pf_local_y;
    reg [3:0]  S_pf_col;
    reg [3:0]  S_pf_row;
    wire [15:0] S_pf_row_bits;
    reg        S_pf_on;
    reg [9:0]  S_pf_scale_x;
    reg [9:0]  S_pf_scale_y;
    localparam LOGO_X = 12'd0;
    localparam LOGO_Y = 12'd0;
    localparam LOGO_W = 12'd160;
    localparam LOGO_H = 12'd160;

    // Compute the address from the first delayed coordinates. This register
    // aligns with S_x_2d/S_y_2d and removes multiplication from the ROM-to-RGB path.
    wire [7:0] S_logo_x_early=S_x_1d-LOGO_X;
    wire [7:0] S_logo_y_early=S_y_1d-LOGO_Y;
    wire [14:0] S_logo_addr_early=({7'd0,S_logo_y_early}<<7)+
                                  ({7'd0,S_logo_y_early}<<5)+{7'd0,S_logo_x_early};

    localparam COLOR_LOGO_BLUE   = 24'h1f315c;
    localparam COLOR_LOGO_RED    = 24'hec1c2d;
    localparam COLOR_TEXT        = 24'h00e6ff;
    localparam DYN_OSD_X         = 12'd375;
    localparam DYN_OSD_Y         = 12'd120;
    localparam DYN_OSD_W         = 12'd216;
    localparam DYN_OSD_H         = 12'd24;
    localparam CN_Y_OFFSET       = 12'd2;
    localparam COLOR_DYN_TEXT    = 24'hfff200;
    localparam CHAR_AN           = 8'h80;
    localparam CHAR_LU           = 8'h81;
    localparam CHAR_C            = 8'h43;
    localparam CHAR_N            = 8'h4e;
    localparam CHAR_T            = 8'h54;
    localparam CHAR_0            = 8'h30;
    localparam CHAR_COLON        = 8'h3a;

    // Exact floor(16*p/24), p=0..23. Avoid a DSP/divider in pixel OSD.
    function [3:0] F_font24;
        input [4:0] p;
        begin
            case(p)
                5'd0: F_font24=4'd0;
                5'd1: F_font24=4'd0;
                5'd2: F_font24=4'd1;
                5'd3: F_font24=4'd2;
                5'd4: F_font24=4'd2;
                5'd5: F_font24=4'd3;
                5'd6: F_font24=4'd4;
                5'd7: F_font24=4'd4;
                5'd8: F_font24=4'd5;
                5'd9: F_font24=4'd6;
                5'd10: F_font24=4'd6;
                5'd11: F_font24=4'd7;
                5'd12: F_font24=4'd8;
                5'd13: F_font24=4'd8;
                5'd14: F_font24=4'd9;
                5'd15: F_font24=4'd10;
                5'd16: F_font24=4'd10;
                5'd17: F_font24=4'd11;
                5'd18: F_font24=4'd12;
                5'd19: F_font24=4'd12;
                5'd20: F_font24=4'd13;
                5'd21: F_font24=4'd14;
                5'd22: F_font24=4'd14;
                5'd23: F_font24=4'd15;
                default:F_font24=0;
            endcase
        end
    endfunction

    function [4:0] F_logo_text_bits;
        input [3:0] I_char;
        input [2:0] I_row;
        begin
            case(I_char)
                4'd0: begin
                    case(I_row) // A
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10001;
                        3'd3: F_logo_text_bits = 5'b11111;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b10001;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd1: begin
                    case(I_row) // N
                        3'd0: F_logo_text_bits = 5'b10001;
                        3'd1: F_logo_text_bits = 5'b11001;
                        3'd2: F_logo_text_bits = 5'b10101;
                        3'd3: F_logo_text_bits = 5'b10011;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b10001;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd2: begin
                    case(I_row) // L
                        3'd0: F_logo_text_bits = 5'b10000;
                        3'd1: F_logo_text_bits = 5'b10000;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10000;
                        3'd4: F_logo_text_bits = 5'b10000;
                        3'd5: F_logo_text_bits = 5'b10000;
                        3'd6: F_logo_text_bits = 5'b11111;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd3: begin
                    case(I_row) // O
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10001;
                        3'd3: F_logo_text_bits = 5'b10001;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd4: begin
                    case(I_row) // G
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10111;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd5: begin
                    case(I_row) // I
                        3'd0: F_logo_text_bits = 5'b11111;
                        3'd1: F_logo_text_bits = 5'b00100;
                        3'd2: F_logo_text_bits = 5'b00100;
                        3'd3: F_logo_text_bits = 5'b00100;
                        3'd4: F_logo_text_bits = 5'b00100;
                        3'd5: F_logo_text_bits = 5'b00100;
                        3'd6: F_logo_text_bits = 5'b11111;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd6: begin
                    case(I_row) // C
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10000;
                        3'd4: F_logo_text_bits = 5'b10000;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                default: F_logo_text_bits = 5'b00000;
            endcase
        end
    endfunction

    // 7-seg bit mapping: {a,b,c,d,e,f,g}
    function [6:0] F_hex7seg;
        input [3:0] I_hex;
        begin
            case(I_hex)
                4'h0: F_hex7seg = 7'b1111110;
                4'h1: F_hex7seg = 7'b0110000;
                4'h2: F_hex7seg = 7'b1101101;
                4'h3: F_hex7seg = 7'b1111001;
                4'h4: F_hex7seg = 7'b0110011;
                4'h5: F_hex7seg = 7'b1011011;
                4'h6: F_hex7seg = 7'b1011111;
                4'h7: F_hex7seg = 7'b1110000;
                4'h8: F_hex7seg = 7'b1111111;
                4'h9: F_hex7seg = 7'b1111011;
                4'ha: F_hex7seg = 7'b1110111;
                4'hb: F_hex7seg = 7'b0011111;
                4'hc: F_hex7seg = 7'b1001110;
                4'hd: F_hex7seg = 7'b0111101;
                4'he: F_hex7seg = 7'b1001111;
                4'hf: F_hex7seg = 7'b1000111;
                default: F_hex7seg = 7'b0000000;
            endcase
        end
    endfunction

    function [4:0] F_cnt_label_bits;
        input [1:0] I_idx;
        input [2:0] I_row;
        begin
            case(I_idx)
                2'd0: begin // C
                    case(I_row)
                        3'd0: F_cnt_label_bits = 5'b01110;
                        3'd1: F_cnt_label_bits = 5'b10001;
                        3'd2: F_cnt_label_bits = 5'b10000;
                        3'd3: F_cnt_label_bits = 5'b10000;
                        3'd4: F_cnt_label_bits = 5'b10000;
                        3'd5: F_cnt_label_bits = 5'b10001;
                        3'd6: F_cnt_label_bits = 5'b01110;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                2'd1: begin // N
                    case(I_row)
                        3'd0: F_cnt_label_bits = 5'b10001;
                        3'd1: F_cnt_label_bits = 5'b11001;
                        3'd2: F_cnt_label_bits = 5'b10101;
                        3'd3: F_cnt_label_bits = 5'b10011;
                        3'd4: F_cnt_label_bits = 5'b10001;
                        3'd5: F_cnt_label_bits = 5'b10001;
                        3'd6: F_cnt_label_bits = 5'b10001;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                2'd2: begin // T
                    case(I_row)
                        3'd0: F_cnt_label_bits = 5'b11111;
                        3'd1: F_cnt_label_bits = 5'b00100;
                        3'd2: F_cnt_label_bits = 5'b00100;
                        3'd3: F_cnt_label_bits = 5'b00100;
                        3'd4: F_cnt_label_bits = 5'b00100;
                        3'd5: F_cnt_label_bits = 5'b00100;
                        3'd6: F_cnt_label_bits = 5'b00100;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                default: begin // ':'
                    case(I_row)
                        3'd2: F_cnt_label_bits = 5'b00100;
                        3'd5: F_cnt_label_bits = 5'b00100;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
            endcase
        end
    endfunction

    // Minimal 16x16 Chinese bitmap rows for "an" and "lu".
    function [15:0] F_cn16_row;
        input I_char; // 0: an, 1: lu
        input [3:0] I_row;
        begin
            if(!I_char) begin
                case(I_row)
                    4'd0:  F_cn16_row = 16'h0200;
                    4'd1:  F_cn16_row = 16'h7ff0;
                    4'd2:  F_cn16_row = 16'h4410;
                    4'd3:  F_cn16_row = 16'h0400;
                    4'd4:  F_cn16_row = 16'h7ff0;
                    4'd5:  F_cn16_row = 16'h0840;
                    4'd6:  F_cn16_row = 16'h1040;
                    4'd7:  F_cn16_row = 16'h1c80;
                    4'd8:  F_cn16_row = 16'h0300;
                    4'd9:  F_cn16_row = 16'h0cc0;
                    4'd10: F_cn16_row = 16'h7020;
                    4'd11: F_cn16_row = 16'h0000;
                    4'd12: F_cn16_row = 16'h0000;
                    4'd13: F_cn16_row = 16'h0000;
                    4'd14: F_cn16_row = 16'h0000;
                    4'd15: F_cn16_row = 16'h0000;
                    default: F_cn16_row = 16'h0000;
                endcase
            end
            else begin
                case(I_row)
                    4'd0:  F_cn16_row = 16'h79e0;
                    4'd1:  F_cn16_row = 16'h4a20;
                    4'd2:  F_cn16_row = 16'h4d40;
                    4'd3:  F_cn16_row = 16'h7880;
                    4'd4:  F_cn16_row = 16'h1140;
                    4'd5:  F_cn16_row = 16'h1630;
                    4'd6:  F_cn16_row = 16'h5be0;
                    4'd7:  F_cn16_row = 16'h5220;
                    4'd8:  F_cn16_row = 16'h5220;
                    4'd9:  F_cn16_row = 16'h5be0;
                    4'd10: F_cn16_row = 16'h6220;
                    4'd11: F_cn16_row = 16'h0000;
                    4'd12: F_cn16_row = 16'h0000;
                    4'd13: F_cn16_row = 16'h0000;
                    4'd14: F_cn16_row = 16'h0000;
                    4'd15: F_cn16_row = 16'h0000;
                    default: F_cn16_row = 16'h0000;
                endcase
            end
        end
    endfunction

    function [4:0] F_dyn_char_bits;
        input [3:0] I_char;
        input [2:0] I_row;
        begin
            case(I_char)
                4'h0: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10011; 3'd3:F_dyn_char_bits=5'b10101; 3'd4:F_dyn_char_bits=5'b11001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h1: begin case(I_row) 3'd0:F_dyn_char_bits=5'b00100; 3'd1:F_dyn_char_bits=5'b01100; 3'd2:F_dyn_char_bits=5'b00100; 3'd3:F_dyn_char_bits=5'b00100; 3'd4:F_dyn_char_bits=5'b00100; 3'd5:F_dyn_char_bits=5'b00100; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h2: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b00001; 3'd3:F_dyn_char_bits=5'b00110; 3'd4:F_dyn_char_bits=5'b01000; 3'd5:F_dyn_char_bits=5'b10000; 3'd6:F_dyn_char_bits=5'b11111; default:F_dyn_char_bits=5'b00000; endcase end
                4'h3: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11110; 3'd1:F_dyn_char_bits=5'b00001; 3'd2:F_dyn_char_bits=5'b00001; 3'd3:F_dyn_char_bits=5'b01110; 3'd4:F_dyn_char_bits=5'b00001; 3'd5:F_dyn_char_bits=5'b00001; 3'd6:F_dyn_char_bits=5'b11110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h4: begin case(I_row) 3'd0:F_dyn_char_bits=5'b00010; 3'd1:F_dyn_char_bits=5'b00110; 3'd2:F_dyn_char_bits=5'b01010; 3'd3:F_dyn_char_bits=5'b10010; 3'd4:F_dyn_char_bits=5'b11111; 3'd5:F_dyn_char_bits=5'b00010; 3'd6:F_dyn_char_bits=5'b00010; default:F_dyn_char_bits=5'b00000; endcase end
                4'h5: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b10000; 3'd2:F_dyn_char_bits=5'b11110; 3'd3:F_dyn_char_bits=5'b00001; 3'd4:F_dyn_char_bits=5'b00001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h6: begin case(I_row) 3'd0:F_dyn_char_bits=5'b00110; 3'd1:F_dyn_char_bits=5'b01000; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h7: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b00001; 3'd2:F_dyn_char_bits=5'b00010; 3'd3:F_dyn_char_bits=5'b00100; 3'd4:F_dyn_char_bits=5'b01000; 3'd5:F_dyn_char_bits=5'b01000; 3'd6:F_dyn_char_bits=5'b01000; default:F_dyn_char_bits=5'b00000; endcase end
                4'h8: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b01110; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h9: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b01111; 3'd4:F_dyn_char_bits=5'b00001; 3'd5:F_dyn_char_bits=5'b00010; 3'd6:F_dyn_char_bits=5'b11100; default:F_dyn_char_bits=5'b00000; endcase end
                4'ha: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b11111; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b10001; default:F_dyn_char_bits=5'b00000; endcase end
                4'hb: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b11110; default:F_dyn_char_bits=5'b00000; endcase end
                4'hc: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b10000; 3'd4:F_dyn_char_bits=5'b10000; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'hd: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b10001; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b11110; default:F_dyn_char_bits=5'b00000; endcase end
                4'he: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b10000; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10000; 3'd5:F_dyn_char_bits=5'b10000; 3'd6:F_dyn_char_bits=5'b11111; default:F_dyn_char_bits=5'b00000; endcase end
                4'hf: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b10000; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10000; 3'd5:F_dyn_char_bits=5'b10000; 3'd6:F_dyn_char_bits=5'b10000; default:F_dyn_char_bits=5'b00000; endcase end
                default: F_dyn_char_bits = 5'b00000;
            endcase
        end
    endfunction

    // Unified prefix character library (16x16 rows): an/lu/C/N/T/:
    function [15:0] F_osd_char16_row;
        input [7:0] I_char;
        input [3:0] I_row;
        begin
            case(I_char)
                CHAR_AN: begin
                    case(I_row)
                        4'd0:  F_osd_char16_row = 16'h0200;
                        4'd1:  F_osd_char16_row = 16'h7ff0;
                        4'd2:  F_osd_char16_row = 16'h4410;
                        4'd3:  F_osd_char16_row = 16'h0400;
                        4'd4:  F_osd_char16_row = 16'h7ff0;
                        4'd5:  F_osd_char16_row = 16'h0840;
                        4'd6:  F_osd_char16_row = 16'h1040;
                        4'd7:  F_osd_char16_row = 16'h1c80;
                        4'd8:  F_osd_char16_row = 16'h0300;
                        4'd9:  F_osd_char16_row = 16'h0cc0;
                        4'd10: F_osd_char16_row = 16'h7020;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_LU: begin
                    case(I_row)
                        4'd0:  F_osd_char16_row = 16'h79e0;
                        4'd1:  F_osd_char16_row = 16'h4a20;
                        4'd2:  F_osd_char16_row = 16'h4d40;
                        4'd3:  F_osd_char16_row = 16'h7880;
                        4'd4:  F_osd_char16_row = 16'h1140;
                        4'd5:  F_osd_char16_row = 16'h1630;
                        4'd6:  F_osd_char16_row = 16'h5be0;
                        4'd7:  F_osd_char16_row = 16'h5220;
                        4'd8:  F_osd_char16_row = 16'h5220;
                        4'd9:  F_osd_char16_row = 16'h5be0;
                        4'd10: F_osd_char16_row = 16'h6220;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_C: begin
                    case(I_row)
                        4'd2:  F_osd_char16_row = 16'h03f0;
                        4'd3:  F_osd_char16_row = 16'h0c0c;
                        4'd4:  F_osd_char16_row = 16'h1800;
                        4'd5:  F_osd_char16_row = 16'h3000;
                        4'd6:  F_osd_char16_row = 16'h3000;
                        4'd7:  F_osd_char16_row = 16'h3000;
                        4'd8:  F_osd_char16_row = 16'h3000;
                        4'd9:  F_osd_char16_row = 16'h3000;
                        4'd10: F_osd_char16_row = 16'h1800;
                        4'd11: F_osd_char16_row = 16'h0c0c;
                        4'd12: F_osd_char16_row = 16'h03f0;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_N: begin
                    case(I_row)
                        4'd2:  F_osd_char16_row = 16'h300c;
                        4'd3:  F_osd_char16_row = 16'h380c;
                        4'd4:  F_osd_char16_row = 16'h3c0c;
                        4'd5:  F_osd_char16_row = 16'h360c;
                        4'd6:  F_osd_char16_row = 16'h330c;
                        4'd7:  F_osd_char16_row = 16'h318c;
                        4'd8:  F_osd_char16_row = 16'h30cc;
                        4'd9:  F_osd_char16_row = 16'h306c;
                        4'd10: F_osd_char16_row = 16'h303c;
                        4'd11: F_osd_char16_row = 16'h301c;
                        4'd12: F_osd_char16_row = 16'h300c;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_T: begin
                    case(I_row)
                        4'd2:  F_osd_char16_row = 16'h3ffc;
                        4'd3:  F_osd_char16_row = 16'h03c0;
                        4'd4:  F_osd_char16_row = 16'h03c0;
                        4'd5:  F_osd_char16_row = 16'h03c0;
                        4'd6:  F_osd_char16_row = 16'h03c0;
                        4'd7:  F_osd_char16_row = 16'h03c0;
                        4'd8:  F_osd_char16_row = 16'h03c0;
                        4'd9:  F_osd_char16_row = 16'h03c0;
                        4'd10: F_osd_char16_row = 16'h03c0;
                        4'd11: F_osd_char16_row = 16'h03c0;
                        4'd12: F_osd_char16_row = 16'h03c0;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_COLON: begin
                    case(I_row)
                        4'd6:  F_osd_char16_row = 16'h0180;
                        4'd7:  F_osd_char16_row = 16'h0180;
                        4'd10: F_osd_char16_row = 16'h0180;
                        4'd11: F_osd_char16_row = 16'h0180;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                default: F_osd_char16_row = 16'h0000;
            endcase
        end
    endfunction

    assign O_video_rd_en = I_video_de;

    anlogic_logo_rom u_anlogic_logo_rom(
        .I_addr  ( S_logo_addr  ),
        .O_pixel ( S_logo_pixel )
    );

    osd_char_lib u_osd_char_lib(
        .I_char     ( S_pf_char     ),
        .I_row      ( S_pf_row      ),
        .O_row_bits ( S_pf_row_bits )
    );

    // Synchronize mode controls and commit OSD changes only at HDMI frame start.
    // Entering SIG starts a new result epoch: old CDC metadata cannot reappear
    // until a fresh detector notification has arrived during this SIG session.
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_traffic_sign_mode_sync1 <= 1'b0;
            S_traffic_sign_mode_sync2 <= 1'b0;
            S_traffic_sign_mode_frame <= 1'b0;
            S_image_mode_sync1 <= 3'd3;
            S_image_mode_sync2 <= 3'd3;
            S_image_mode_frame <= 3'd3;
            S_traffic_sign_toggle_sync1 <= 1'b0;
            S_traffic_sign_toggle_sync2 <= 1'b0;
            S_traffic_sign_toggle_seen <= 1'b0;
            S_traffic_sign_result_ready <= 1'b0;
            S_sign_ready_frame <= 1'b0;
            S_sign_meta_frame <= 0; S_sign_ascii_frame <= "?";
            S_score_hundred_frame<=0;S_score_tens_frame<=0;S_score_ones_frame<=0;
        end else begin
            S_traffic_sign_mode_sync1 <= I_traffic_sign_mode;
            S_traffic_sign_mode_sync2 <= S_traffic_sign_mode_sync1;
            S_image_mode_sync1 <= I_image_mode;
            S_image_mode_sync2 <= S_image_mode_sync1;
            S_traffic_sign_toggle_sync1 <= I_traffic_sign_result_toggle;
            S_traffic_sign_toggle_sync2 <= S_traffic_sign_toggle_sync1;
            S_traffic_sign_toggle_seen <= S_traffic_sign_toggle_sync2;
            if(!S_sign_mode_sync || !S_traffic_sign_mode_frame)
                S_traffic_sign_result_ready <= 1'b0;
            else if(S_traffic_sign_toggle_sync2 != S_traffic_sign_toggle_seen)
                S_traffic_sign_result_ready <= 1'b1;
            if(I_video_user) begin
                S_image_mode_frame <= S_image_mode_sync2;
                S_traffic_sign_mode_frame <= S_sign_mode_sync;
                if(S_sign_mode_sync && S_traffic_sign_mode_frame && S_traffic_sign_result_ready) begin
                    S_sign_ready_frame <= 1'b1;
                    S_sign_meta_frame <= I_traffic_sign_metadata;
                    S_sign_ascii_frame <= I_traffic_sign_result_ascii;
                    S_score_hundred_frame <= I_traffic_sign_metadata[7:0]>=100;
                    S_score_tens_frame <= S_incoming_tens;
                    S_score_ones_frame <= I_traffic_sign_metadata[7:0]>=100?0:I_traffic_sign_metadata[7:0]-S_incoming_ten_value;
                end else begin
                    S_sign_ready_frame <= 1'b0;
                    S_sign_meta_frame <= 0; S_sign_ascii_frame <= "?";
                    S_score_hundred_frame<=0;S_score_tens_frame<=0;S_score_ones_frame<=0;
                end
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if(I_video_user) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if(I_video_de) begin
            if(I_video_last) begin
                S_x <= 12'd0;
                S_y <= S_y + 12'd1;
            end
            else begin
                S_x <= S_x + 12'd1;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_frame_cnt <= 32'd0;
            S_cnt_d0 <= 4'd0;
            S_cnt_d1 <= 4'd0;
            S_cnt_d2 <= 4'd0;
            S_cnt_d3 <= 4'd0;
            S_cnt_d4 <= 4'd0;
            S_cnt_d5 <= 4'd0;
        end
        else if(I_video_user) begin
            S_frame_cnt <= S_frame_cnt + 32'd1;
            if(S_cnt_d0 == 4'd9) begin
                S_cnt_d0 <= 4'd0;
                if(S_cnt_d1 == 4'd9) begin
                    S_cnt_d1 <= 4'd0;
                    if(S_cnt_d2 == 4'd9) begin
                        S_cnt_d2 <= 4'd0;
                        if(S_cnt_d3 == 4'd9) begin
                            S_cnt_d3 <= 4'd0;
                            if(S_cnt_d4 == 4'd9) begin
                                S_cnt_d4 <= 4'd0;
                                if(S_cnt_d5 == 4'd9)
                                    S_cnt_d5 <= 4'd0;
                                else
                                    S_cnt_d5 <= S_cnt_d5 + 4'd1;
                            end
                            else
                                S_cnt_d4 <= S_cnt_d4 + 4'd1;
                        end
                        else
                            S_cnt_d3 <= S_cnt_d3 + 4'd1;
                    end
                    else
                        S_cnt_d2 <= S_cnt_d2 + 4'd1;
                end
                else
                    S_cnt_d1 <= S_cnt_d1 + 4'd1;
            end
            else
                S_cnt_d0 <= S_cnt_d0 + 4'd1;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_x_1d <= 12'd0;
            S_x_2d <= 12'd0;
            S_y_1d <= 12'd0;
            S_y_2d <= 12'd0;
            S_logo_addr <= 15'd0;
        end
        else begin
            S_x_1d <= S_x;
            S_x_2d <= S_x_1d;
            S_y_1d <= S_y;
            S_y_2d <= S_y_1d;
            if(S_x_1d>=LOGO_X && S_x_1d<LOGO_X+LOGO_W &&
               S_y_1d>=LOGO_Y && S_y_1d<LOGO_Y+LOGO_H)
                S_logo_addr <= S_logo_addr_early;
            else S_logo_addr <= 15'd0;
        end
    end

    always @(*) begin
        S_score_digit = 0;
        S_osd_hit   = 1'b0;
        S_osd_color = 24'd0;

        S_logo_x = 12'd0;
        S_logo_y = 12'd0;
        S_char_idx = 4'd0;
        S_char_row = 3'd0;
        S_char_col = 3'd0;
        S_char_bits = 5'd0;
        S_char_on = 1'b0;
        S_logo_blue_on = 1'b0;
        S_logo_red_on = 1'b0;
        S_logo_tmp_y = 12'd0;
        S_logo_red_band = 4'd0;
        S_logo_red_x_start = 12'd0;
        S_logo_red_x_end = 12'd0;
        S_dyn_x = 12'd0;
        S_dyn_y = 12'd0;
        S_dyn_char = 4'd0;
        S_dyn_col = 3'd0;
        S_dyn_row = 3'd0;
        S_dyn_bits = 5'd0;
        S_dyn_digit_idx = 4'd0;
        S_dyn_digit_x = 12'd0;
        S_dyn_seg = 7'd0;
        S_lbl_row = 3'd0;
        S_lbl_col = 3'd0;
        S_lbl_idx = 2'd0;
        S_lbl_bits = 5'd0;
        S_lbl_local_x = 7'd0;
        S_dyn_dec_digit = 4'd0;
        S_cn_local_x = 5'd0;
        S_cn_local_y = 5'd0;
        S_cn_col = 4'd0;
        S_cn_row = 4'd0;
        S_cn_row_bits = 16'd0;
        S_cn_on = 1'b0;
        S_cn_scale_x = 10'd0;
        S_cn_scale_y = 10'd0;
        S_pf_char = 8'd0;
        S_pf_local_x = 5'd0;
        S_pf_local_y = 5'd0;
        S_pf_col = 4'd0;
        S_pf_row = 4'd0;
        S_pf_on = 1'b0;
        S_pf_scale_x = 10'd0;
        S_pf_scale_y = 10'd0;

        if(S_video_de_2d) begin
            if((S_x_2d >= LOGO_X) && (S_x_2d < (LOGO_X + LOGO_W)) &&
               (S_y_2d >= LOGO_Y) && (S_y_2d < (LOGO_Y + LOGO_H))) begin
                S_logo_x = S_x_2d - LOGO_X;
                S_logo_y = S_y_2d - LOGO_Y;
                if(S_logo_pixel[24]) begin
                    S_osd_hit   = 1'b1;
                    S_osd_color = S_logo_pixel[23:0];
                end
            end

            if((S_x_2d >= DYN_OSD_X) && (S_x_2d < (DYN_OSD_X + DYN_OSD_W)) &&
               (S_y_2d >= DYN_OSD_Y) && (S_y_2d < (DYN_OSD_Y + DYN_OSD_H))) begin
                S_dyn_x = S_x_2d - DYN_OSD_X;
                S_dyn_y = S_y_2d - DYN_OSD_Y;

                // Keep the original two Chinese 24x24 cells, then use ONE
                // 16x16 size for CNT:, all six count digits and all status rows.
                if(S_dyn_x<12'd48) begin
                    if(S_dyn_x<12'd24) begin
                        S_pf_char=CHAR_AN; S_pf_local_x=S_dyn_x;
                    end else begin
                        S_pf_char=CHAR_LU; S_pf_local_x=S_dyn_x-12'd24;
                    end
                    if(S_dyn_y>=CN_Y_OFFSET)begin
                        S_pf_local_y=S_dyn_y-CN_Y_OFFSET;
                        S_pf_col=F_font24(S_pf_local_x);
                        S_pf_row=F_font24(S_pf_local_y);
                        S_pf_on=S_pf_row_bits[15-S_pf_col];
                    end
                end else if(S_dyn_x>=12'd52 && S_dyn_x<12'd212 &&
                            S_dyn_y>=12'd4 && S_dyn_y<12'd20)begin
                    S_pf_local_x=S_dyn_x-12'd52;
                    S_pf_col=S_pf_local_x[3:0];
                    S_pf_row=S_dyn_y-12'd4;
                    if(S_dyn_x<12'd68) S_pf_char=CHAR_C;
                    else if(S_dyn_x<12'd84) S_pf_char=CHAR_N;
                    else if(S_dyn_x<12'd100) S_pf_char=CHAR_T;
                    else if(S_dyn_x<12'd116) S_pf_char=CHAR_COLON;
                    else if(S_dyn_x<12'd132) S_pf_char=CHAR_0+S_cnt_d5;
                    else if(S_dyn_x<12'd148) S_pf_char=CHAR_0+S_cnt_d4;
                    else if(S_dyn_x<12'd164) S_pf_char=CHAR_0+S_cnt_d3;
                    else if(S_dyn_x<12'd180) S_pf_char=CHAR_0+S_cnt_d2;
                    else if(S_dyn_x<12'd196) S_pf_char=CHAR_0+S_cnt_d1;
                    else S_pf_char=CHAR_0+S_cnt_d0;
                    S_pf_on=S_pf_row_bits[15-S_pf_col];
                end

                // 动态OSD只使用当前字符像素作为命中条件，避免在同一组合块内
                // 读回自赋值的中间信号，防止综合器推断组合反馈环。
                if(S_pf_on) begin
                    S_osd_hit = 1'b1;
                    S_osd_color = COLOR_DYN_TEXT;
                end
            end

            // SIG alone shows DIR; RAW/ERO/DIL keep only mode/count/logo OSD.
            if(S_sign_overlay_enable && (S_x_2d >= 12'd375) && (S_x_2d < 12'd503) &&
               (S_y_2d >= 12'd150) && (S_y_2d < 12'd174)) begin
                S_dyn_x = S_x_2d - 12'd375;
                S_dyn_y = S_y_2d - 12'd150;
                if((S_dyn_y >= 12'd4) && (S_dyn_y < 12'd20)) begin
                    S_pf_local_y = S_dyn_y - 12'd4;
                    S_pf_row = S_pf_local_y[3:0];
                    S_pf_local_x = S_dyn_x[4:0];
                    if(S_dyn_x < 12'd16)
                        S_pf_char = 8'h44; // D
                    else if(S_dyn_x < 12'd32)
                        S_pf_char = 8'h49; // I
                    else if(S_dyn_x < 12'd48)
                        S_pf_char = 8'h52; // R
                    else if(S_dyn_x < 12'd64)
                        S_pf_char = CHAR_COLON;
                    // ASCII已由前级CDC模块稳定保持，HDMI域同步toggle后直接读取。
                    else if(S_sign_ready_frame && (S_dyn_x < 12'd80))
                        S_pf_char = S_sign_ascii_frame;
                    else if(!S_sign_ready_frame && (S_dyn_x < 12'd80))
                        S_pf_char = 8'h57;
                    else if(!S_sign_ready_frame && (S_dyn_x < 12'd96))
                        S_pf_char = 8'h41;
                    else if(!S_sign_ready_frame && (S_dyn_x < 12'd112))
                        S_pf_char = 8'h49;
                    else if(!S_sign_ready_frame && (S_dyn_x < 12'd128))
                        S_pf_char = 8'h54;
                    else
                        S_pf_char = 8'd0;

                    if(S_dyn_x < 12'd128) begin
                        S_pf_col = S_dyn_x[3:0];
                        S_pf_on = S_pf_row_bits[15 - S_pf_col];
                        if(S_pf_on) begin
                            S_osd_hit = 1'b1;
                            S_osd_color = COLOR_DYN_TEXT;
                        end
                    end
                end
            end
            // 每种画面都显示当前模式；在帧首锁存，避免一帧中途更换文字。
            if((S_x_2d >= 12'd375) && (S_x_2d < 12'd503) &&
               (S_y_2d >= 12'd180) && (S_y_2d < 12'd204)) begin
                S_dyn_x = S_x_2d - 12'd375;
                S_dyn_y = S_y_2d - 12'd180;
                if((S_dyn_y >= 12'd4) && (S_dyn_y < 12'd20)) begin
                    S_pf_local_y = S_dyn_y - 12'd4;
                    S_pf_row = S_pf_local_y[3:0];
                    if(S_dyn_x < 12'd16) S_pf_char = 8'h4d; // M
                    else if(S_dyn_x < 12'd32) S_pf_char = 8'h4f; // O
                    else if(S_dyn_x < 12'd48) S_pf_char = 8'h44; // D
                    else if(S_dyn_x < 12'd64) S_pf_char = 8'h45; // E
                    else if(S_dyn_x < 12'd80) S_pf_char = CHAR_COLON;
                    else begin
                        case(S_image_mode_frame)
                            3'd3: begin // RAW
                                if(S_dyn_x < 12'd96) S_pf_char = 8'h52;
                                else if(S_dyn_x < 12'd112) S_pf_char = 8'h41;
                                else S_pf_char = 8'h57;
                            end
                            3'd2: begin // ERO
                                if(S_dyn_x < 12'd96) S_pf_char = 8'h45;
                                else if(S_dyn_x < 12'd112) S_pf_char = 8'h52;
                                else S_pf_char = 8'h4f;
                            end
                            3'd1: begin // DIL
                                if(S_dyn_x < 12'd96) S_pf_char = 8'h44;
                                else if(S_dyn_x < 12'd112) S_pf_char = 8'h49;
                                else S_pf_char = 8'h4c;
                            end
                            3'd4: begin // MOT
                                if(S_dyn_x < 12'd96) S_pf_char = "M";
                                else if(S_dyn_x < 12'd112) S_pf_char = "O";
                                else S_pf_char = "T";
                            end
                            3'd5: begin // DEH
                                if(S_dyn_x < 12'd96) S_pf_char = "D";
                                else if(S_dyn_x < 12'd112) S_pf_char = "E";
                                else S_pf_char = "H";
                            end
                            default: begin // SIG
                                if(S_dyn_x < 12'd96) S_pf_char = 8'h53;
                                else if(S_dyn_x < 12'd112) S_pf_char = 8'h49;
                                else S_pf_char = 8'h47;
                            end
                        endcase
                    end
                    S_pf_col = S_dyn_x[3:0];
                    S_pf_on = S_pf_row_bits[15 - S_pf_col];
                    if(S_pf_on) begin
                        S_osd_hit = 1'b1;
                        S_osd_color = COLOR_DYN_TEXT;
                    end
                end
            end

            // Two-pixel ROI border; uses the SAME delayed coordinate as RGB.
            if(S_sign_overlay_enable && S_sign_box && S_x_2d>=S_sign_x0 && S_x_2d<=S_sign_x1 &&
               S_y_2d>=S_sign_y0 && S_y_2d<=S_sign_y1 &&
               (S_x_2d<S_sign_x0+2 || S_x_2d+2>S_sign_x1 ||
                S_y_2d<S_sign_y0+2 || S_y_2d+2>S_sign_y1)) begin
                S_osd_hit=1; S_osd_color=S_sign_accepted?24'h20ff40:24'hfff200;
            end
            // Recognized L/R only: a fixed-size label follows the tracked box.
            // Candidate '?' boxes remain visible without showing coordinates.
            // When placed inside a top-edge box, text also takes priority over
            // its border so the digits cannot be cut by a vertical green line.
            if(S_sign_overlay_enable && S_sign_box && S_sign_accepted && S_coord_ready &&
               S_x_2d>=S_coord_label_x && S_x_2d<S_coord_label_x+COORD_LABEL_W &&
               S_y_2d>=S_coord_label_y && S_y_2d<S_coord_label_y+COORD_LABEL_H)begin
                S_osd_hit=1;S_osd_color=24'h20ff40;
                if(S_coord_local_y>=2 && S_coord_local_y<18 &&
                   S_coord_row_bits[15-S_coord_local_x[3:0]])S_osd_color=24'h101820;
            end
            // MATCH:000..100 = foreground IoU score, not a probability.
            if(S_sign_overlay_enable && S_x_2d>=375 && S_x_2d<519 && S_y_2d>=214 && S_y_2d<230) begin
                S_dyn_x=S_x_2d-375; S_pf_row=S_y_2d-214;
                if(S_dyn_x<16) S_pf_char="M";
                else if(S_dyn_x<32) S_pf_char="A";
                else if(S_dyn_x<48) S_pf_char="T";
                else if(S_dyn_x<64) S_pf_char="C";
                else if(S_dyn_x<80) S_pf_char="H";
                else if(S_dyn_x<96) S_pf_char=CHAR_COLON;
                else begin
                    if(S_dyn_x<112) S_score_digit={3'd0,S_score_hundred_frame};
                    else if(S_dyn_x<128) S_score_digit=S_score_tens_frame;
                    else S_score_digit=S_score_ones_frame;
                    S_pf_char=CHAR_0+S_score_digit;
                end
                S_pf_col=S_dyn_x[3:0];
                S_pf_on=S_pf_row_bits[15-S_pf_col];
                if(S_pf_on)begin S_osd_hit=1;S_osd_color=COLOR_DYN_TEXT;end
            end
            if(S_sign_overlay_enable && S_x_2d>=375 && S_x_2d<575 && S_y_2d>=234 && S_y_2d<240)begin
                S_osd_hit=1;
                S_osd_color=S_x_2d-375<({4'b0,S_sign_score}<<1)?24'h20ff40:24'h303030;
            end
            // All modes show frame-matched latency in a small top-right field.
            if(ENABLE_LATENCY && S_x_2d>=LATENCY_X-8 && S_x_2d<LATENCY_X+200 &&
               S_y_2d>=8 && S_y_2d<40)begin
                S_osd_hit=1;S_osd_color=24'h101820;
                if(S_x_2d>=LATENCY_X && S_x_2d<LATENCY_X+192 &&
                   S_y_2d>=16 && S_y_2d<32 && S_latency_row_bits[15-S_latency_x[3:0]])
                    S_osd_color=S_latency_valid&&!S_latency_overflow?24'h40ffff:24'hc0c0c0;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_video_vsync_1d <= 1'b0;
            S_video_vsync_2d <= 1'b0;
            S_video_hsync_1d <= 1'b0;
            S_video_hsync_2d <= 1'b0;
            S_video_de_1d    <= 1'b0;
            S_video_de_2d    <= 1'b0;
            O_hdmi_vsync     <= 1'b0;
            O_hdmi_hsync     <= 1'b0;
            O_hdmi_de        <= 1'b0;
            O_hdmi_data      <= 24'd0;
        end
        else begin
            S_video_vsync_1d <= I_video_vsync;
            S_video_vsync_2d <= S_video_vsync_1d;
            O_hdmi_vsync     <= S_video_vsync_2d;

            S_video_hsync_1d <= I_video_hsync;
            S_video_hsync_2d <= S_video_hsync_1d;
            O_hdmi_hsync     <= S_video_hsync_2d;

            S_video_de_1d    <= I_video_de;
            S_video_de_2d    <= S_video_de_1d;
            O_hdmi_de        <= S_video_de_2d;
            S_video_data_1d  <= I_video_rd_data;
            S_video_data_2d  <= S_video_data_1d;

            if(DEBUG_MODE == 1) begin
                if(S_video_de_2d) begin
                    if(S_x < 12'd128)
                        O_hdmi_data <= 24'hff0000;
                    else if(S_x < 12'd256)
                        O_hdmi_data <= 24'h00ff00;
                    else if(S_x < 12'd384)
                        O_hdmi_data <= 24'h0000ff;
                    else if(S_x < 12'd512)
                        O_hdmi_data <= 24'hffff00;
                    else if(S_x < 12'd640)
                        O_hdmi_data <= 24'h00ffff;
                    else if(S_x < 12'd768)
                        O_hdmi_data <= 24'hff00ff;
                    else if(S_x < 12'd896)
                        O_hdmi_data <= 24'hffffff;
                    else
                        O_hdmi_data <= 24'h202020;
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 2) begin
                if(S_video_de_2d) begin
                    case (I_debug_status)
                        4'b0000: O_hdmi_data <= 24'h000000;
                        4'b0001: O_hdmi_data <= 24'hff0000;
                        4'b0011: O_hdmi_data <= 24'hffff00;
                        4'b0111: O_hdmi_data <= 24'h00ff00;
                        4'b1111: O_hdmi_data <= I_video_rd_data;
                        default: O_hdmi_data <= 24'h0000ff;
                    endcase
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 3) begin
                if(S_video_de_2d) begin
                    if(S_x < 12'd256)
                        O_hdmi_data <= I_debug_status[0] ? 24'hff8000 : 24'h201000;
                    else if(S_x < 12'd512)
                        O_hdmi_data <= I_debug_status[1] ? 24'hffff00 : 24'h202000;
                    else if(S_x < 12'd768)
                        O_hdmi_data <= I_debug_status[2] ? 24'hff0000 : 24'h200000;
                    else
                        O_hdmi_data <= I_debug_status[3] ? 24'h00ffff : 24'h002020;
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else begin
                if(S_osd_hit)
                    O_hdmi_data <= S_osd_color;
                else
                    O_hdmi_data <= S_video_data_2d;
            end
        end
    end

endmodule
