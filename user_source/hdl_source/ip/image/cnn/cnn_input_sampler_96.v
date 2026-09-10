`timescale 1ns / 1ps

//********************************************************************//
//****************** Parameter and Internal Signal *******************//
//********************************************************************//
// 模块说明：
// 1. 接收灰度流中的四个连续像素，每四拍合成为一个CNN横向采样点。
// 2. 逐个摄像头源行累加64个采样点，行边界由固定表决定。
// 3. 两块4Kx8输入RAM交替使用，采样和推理不会访问同一块RAM。
// 4. 视频链路没有反压接口；两块RAM均被占用时置位O_frame_drop并丢弃该帧，
//    不把新旧帧混合写入CNN输入。
//********************************************************************//
module cnn_input_sampler_96 #(
    parameter integer IMG_WIDTH  = 1024,
    parameter integer IMG_HEIGHT = 600,
    parameter integer CNN_SIZE   = 64
) (
    input  wire        I_clk,
    input  wire        I_rst_n,

    input  wire        I_tuser,
    input  wire        I_tlast,
    input  wire        I_tvalid,
    input  wire [31:0] I_gray_data,

    input  wire        I_core_busy,
    input  wire        I_core_done,
    input  wire        I_core_bank,
    output reg         O_core_start,
    output reg         O_core_input_bank,
    output wire        O_core_input_frame_ready,

    input  wire        I_core_rd_bank,
    input  wire [11:0] I_core_rd_addr,
    output wire [7:0]  O_core_rd_data,

    output reg         O_frame_drop,
    output wire        O_capture_active
);

    localparam [1:0] BANK_FREE    = 2'd0;
    localparam [1:0] BANK_CAPTURE = 2'd1;
    localparam [1:0] BANK_READY   = 2'd2;
    localparam [1:0] BANK_RUN     = 2'd3;

    localparam integer GROUP_WIDTH = IMG_WIDTH / 4;

    reg [1:0] bank0_state;
    reg [1:0] bank1_state;
    reg       capture_bank;
    reg       capture_accept;
    reg       capture_active;
    reg       frame_finish_pending;
    reg       frame_finish_bank;

    reg [7:0] src_x_group;
    reg [9:0] src_y;
    reg [5:0] cnn_y;
    reg [18:0] column_sum [0:CNN_SIZE-1];

    reg        input0_we;
    reg        input1_we;
    reg [11:0] input_wr_addr;
    reg [7:0]  input_wr_data;
    reg        write_pending;
    reg        write_bank;
    reg [11:0] write_addr;
    reg [18:0] write_sum;
    reg        write_ten_rows;
    wire [7:0] input0_rd_data;
    wire [7:0] input1_rd_data;

    integer i;

    // 帧首拍优先选择输入RAM 0；RAM 0被占用时选择RAM 1。
    wire start_bank0_free = !capture_active && (bank0_state == BANK_FREE);
    wire start_bank1_free = !capture_active && (bank1_state == BANK_FREE);
    wire start_accept     = start_bank0_free || start_bank1_free;
    wire start_bank       = start_bank0_free ? 1'b0 : 1'b1;
    wire active_bank      = I_tuser ? start_bank : capture_bank;
    wire active_accept    = I_tuser ? start_accept : capture_accept;

    // 当前灰度流拍的源坐标。tuser与第一个有效数据同拍时直接使用零坐标。
    wire [7:0] current_x_group = I_tuser ? 8'd0 : src_x_group;
    wire [9:0] current_y       = I_tuser ? 10'd0 : src_y;
    wire [5:0] current_cnn_y   = I_tuser ? 6'd0 : cnn_y;
    wire [5:0] current_cnn_x   = current_x_group[7:2];
    wire       current_cnn_row_last = current_y == F_cnn_y_end(current_cnn_y);
    wire [9:0] source_gray_sum = {2'd0, I_gray_data[7:0]} + {2'd0, I_gray_data[15:8]}
                                + {2'd0, I_gray_data[23:16]} + {2'd0, I_gray_data[31:24]};
    wire [18:0] source_gray_sum_ext = {9'd0, source_gray_sum};
    wire [18:0] previous_column_sum =
        ((current_y == 10'd0) && (current_x_group[1:0] == 2'd0))
        ? 19'd0 : column_sum[current_cnn_x];
    wire [18:0] column_sum_next = previous_column_sum + source_gray_sum_ext;
    wire        cnn_cell_write = I_tvalid && active_accept &&
                                 (current_x_group[1:0] == 2'd3) &&
                                 current_cnn_row_last;

    assign O_capture_active = capture_active;
    assign O_core_input_frame_ready = (bank0_state == BANK_READY) ||
                                       (bank1_state == BANK_READY);

    // 两块RAM都持续响应CNN读地址，最后一级按bank选择对应数据。
    cnn_input_bram u_cnn_input_bank0 (
        .clka  (I_clk),
        .wea   (input0_we),
        .addra (input_wr_addr),
        .dina  (input_wr_data),
        .clkb  (I_clk),
        .addrb (I_core_rd_addr),
        .doutb (input0_rd_data)
    );

    cnn_input_bram u_cnn_input_bank1 (
        .clka  (I_clk),
        .wea   (input1_we),
        .addra (input_wr_addr),
        .dina  (input_wr_data),
        .clkb  (I_clk),
        .addrb (I_core_rd_addr),
        .doutb (input1_rd_data)
    );

    assign O_core_rd_data = I_core_rd_bank ? input1_rd_data : input0_rd_data;

    // 写回端使用一级流水，把坐标和累加和与平均值计算路径隔开。
    always @(*) begin
        input0_we     = write_pending && (write_bank == 1'b0);
        input1_we     = write_pending && (write_bank == 1'b1);
        input_wr_addr = write_addr;
        input_wr_data = F_cnn_average(write_sum, write_ten_rows);
    end

    // 144和160的倒数用定点乘法实现。下列常量在输入和的有效范围
    // 0..40800内与整数除法逐点相等，避免未流水化的通用除法器。
    function [7:0] F_cnn_average;
        input [18:0] I_sum;
        input        I_ten_rows;
        reg [34:0] product;
        begin
            if (I_ten_rows) begin
                product = {16'd0, I_sum} * 16'd26215;
                F_cnn_average = product >> 22;
            end
            else begin
                product = {16'd0, I_sum} * 16'd58255;
                F_cnn_average = product >> 23;
            end
        end
    endfunction

    // 固定纵向分区的结束源行，避免实时路径使用通用除法。
    function [9:0] F_cnn_y_end;
        input [5:0] I_cnn_y;
        begin
            case (I_cnn_y)
                6'd0:  F_cnn_y_end = 10'd8;
                6'd1:  F_cnn_y_end = 10'd17;
                6'd2:  F_cnn_y_end = 10'd27;
                6'd3:  F_cnn_y_end = 10'd36;
                6'd4:  F_cnn_y_end = 10'd45;
                6'd5:  F_cnn_y_end = 10'd55;
                6'd6:  F_cnn_y_end = 10'd64;
                6'd7:  F_cnn_y_end = 10'd74;
                6'd8:  F_cnn_y_end = 10'd83;
                6'd9:  F_cnn_y_end = 10'd92;
                6'd10: F_cnn_y_end = 10'd102;
                6'd11: F_cnn_y_end = 10'd111;
                6'd12: F_cnn_y_end = 10'd120;
                6'd13: F_cnn_y_end = 10'd130;
                6'd14: F_cnn_y_end = 10'd139;
                6'd15: F_cnn_y_end = 10'd149;
                6'd16: F_cnn_y_end = 10'd158;
                6'd17: F_cnn_y_end = 10'd167;
                6'd18: F_cnn_y_end = 10'd177;
                6'd19: F_cnn_y_end = 10'd186;
                6'd20: F_cnn_y_end = 10'd195;
                6'd21: F_cnn_y_end = 10'd205;
                6'd22: F_cnn_y_end = 10'd214;
                6'd23: F_cnn_y_end = 10'd224;
                6'd24: F_cnn_y_end = 10'd233;
                6'd25: F_cnn_y_end = 10'd242;
                6'd26: F_cnn_y_end = 10'd252;
                6'd27: F_cnn_y_end = 10'd261;
                6'd28: F_cnn_y_end = 10'd270;
                6'd29: F_cnn_y_end = 10'd280;
                6'd30: F_cnn_y_end = 10'd289;
                6'd31: F_cnn_y_end = 10'd299;
                6'd32: F_cnn_y_end = 10'd308;
                6'd33: F_cnn_y_end = 10'd317;
                6'd34: F_cnn_y_end = 10'd327;
                6'd35: F_cnn_y_end = 10'd336;
                6'd36: F_cnn_y_end = 10'd345;
                6'd37: F_cnn_y_end = 10'd355;
                6'd38: F_cnn_y_end = 10'd364;
                6'd39: F_cnn_y_end = 10'd374;
                6'd40: F_cnn_y_end = 10'd383;
                6'd41: F_cnn_y_end = 10'd392;
                6'd42: F_cnn_y_end = 10'd402;
                6'd43: F_cnn_y_end = 10'd411;
                6'd44: F_cnn_y_end = 10'd420;
                6'd45: F_cnn_y_end = 10'd430;
                6'd46: F_cnn_y_end = 10'd439;
                6'd47: F_cnn_y_end = 10'd449;
                6'd48: F_cnn_y_end = 10'd458;
                6'd49: F_cnn_y_end = 10'd467;
                6'd50: F_cnn_y_end = 10'd477;
                6'd51: F_cnn_y_end = 10'd486;
                6'd52: F_cnn_y_end = 10'd495;
                6'd53: F_cnn_y_end = 10'd505;
                6'd54: F_cnn_y_end = 10'd514;
                6'd55: F_cnn_y_end = 10'd524;
                6'd56: F_cnn_y_end = 10'd533;
                6'd57: F_cnn_y_end = 10'd542;
                6'd58: F_cnn_y_end = 10'd552;
                6'd59: F_cnn_y_end = 10'd561;
                6'd60: F_cnn_y_end = 10'd570;
                6'd61: F_cnn_y_end = 10'd580;
                6'd62: F_cnn_y_end = 10'd589;
                default: F_cnn_y_end = 10'd599;
            endcase
        end
    endfunction

    function [3:0] F_cnn_y_height;
        input [5:0] I_cnn_y;
        begin
            case (I_cnn_y)
                // floor((j + 1) * 600 / 64) - floor(j * 600 / 64)
                6'd2, 6'd5, 6'd7, 6'd10, 6'd13, 6'd15, 6'd18, 6'd21,
                6'd23, 6'd26, 6'd29, 6'd31, 6'd34, 6'd37, 6'd39, 6'd42,
                6'd45, 6'd47, 6'd50, 6'd53, 6'd55, 6'd58, 6'd61, 6'd63:
                    F_cnn_y_height = 4'd10;
                default:
                    F_cnn_y_height = 4'd9;
            endcase
        end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            bank0_state          <= BANK_FREE;
            bank1_state          <= BANK_FREE;
            capture_bank         <= 1'b0;
            capture_accept       <= 1'b0;
            capture_active       <= 1'b0;
            frame_finish_pending <= 1'b0;
            frame_finish_bank    <= 1'b0;
            src_x_group          <= 8'd0;
            src_y                <= 10'd0;
            cnn_y                <= 6'd0;
            O_core_start         <= 1'b0;
            O_core_input_bank    <= 1'b0;
            O_frame_drop         <= 1'b0;
            write_pending        <= 1'b0;
            write_bank           <= 1'b0;
            write_addr           <= 12'd0;
            write_sum            <= 19'd0;
            write_ten_rows       <= 1'b0;
            for (i = 0; i < CNN_SIZE; i = i + 1)
                column_sum[i] <= 19'd0;
        end
        else begin
            O_core_start <= 1'b0;

            // 每个CNN单元完成后进入写回流水；RAM在下一拍写入平均值。
            write_pending <= cnn_cell_write;
            if (cnn_cell_write) begin
                write_bank     <= active_bank;
                write_addr     <= {current_cnn_y, current_cnn_x};
                write_sum      <= column_sum_next;
                write_ten_rows <= (F_cnn_y_height(current_cnn_y) == 4'd10);
            end

            // 推理完成后释放其输入RAM，供后续帧重新使用。
            if (I_core_done) begin
                if (I_core_bank == 1'b0)
                    bank0_state <= BANK_FREE;
                else
                    bank1_state <= BANK_FREE;
            end

            // 最后一行的最后一个CNN单元写入后的下一个时钟沿标记为READY。
            if (frame_finish_pending) begin
                if (frame_finish_bank == 1'b0)
                    bank0_state <= BANK_READY;
                else
                    bank1_state <= BANK_READY;
                frame_finish_pending <= 1'b0;
            end

            // 启动脉冲先保持一个完整周期，下一拍由核心和采样器同时确认。
            // 这样核心看到的start、ready和bank选择来自同一拍，避免丢失脉冲。
            if (O_core_start) begin
                if (O_core_input_bank == 1'b0)
                    bank0_state <= BANK_RUN;
                else
                    bank1_state <= BANK_RUN;
            end
            else if (!I_core_busy && (bank0_state == BANK_READY)) begin
                O_core_start      <= 1'b1;
                O_core_input_bank <= 1'b0;
            end
            else if (!I_core_busy && (bank1_state == BANK_READY)) begin
                O_core_start      <= 1'b1;
                O_core_input_bank <= 1'b1;
            end

            if (I_tvalid) begin
                // 帧首拍选择可用RAM；无可用RAM时整帧标记为丢弃。
                if (I_tuser) begin
                    capture_bank   <= start_bank;
                    capture_accept <= start_accept;
                    capture_active <= 1'b1;
                    src_x_group    <= 8'd0;
                    src_y          <= 10'd0;
                    cnn_y          <= 6'd0;
                    if (start_accept) begin
                        if (start_bank == 1'b0)
                            bank0_state <= BANK_CAPTURE;
                        else
                            bank1_state <= BANK_CAPTURE;
                    end
                    else begin
                        O_frame_drop <= 1'b1;
                    end
                end

                // 每个摄像头源行结束时更新纵向分区计数。
                if (I_tlast) begin
                    src_x_group <= 8'd0;
                    if (current_y == IMG_HEIGHT - 1) begin
                        src_y <= 10'd0;
                        cnn_y <= 6'd0;
                        capture_active <= 1'b0;
                        if (active_accept) begin
                            frame_finish_pending <= 1'b1;
                            frame_finish_bank    <= active_bank;
                        end
                    end
                    else begin
                        src_y <= current_y + 10'd1;
                        if (current_cnn_row_last)
                            cnn_y <= current_cnn_y + 6'd1;
                        capture_active <= 1'b1;
                    end
                end
                else begin
                    src_x_group <= current_x_group + 8'd1;
                    src_y       <= current_y;
                end

                if (cnn_cell_write)
                    column_sum[current_cnn_x] <= 19'd0;
                else
                    column_sum[current_cnn_x] <= column_sum_next;
            end

            // 推理启动脉冲需覆盖到核心下一次采样的时钟沿。
            // O_core_start在本always中只保持一个时钟周期。
        end
    end

endmodule
