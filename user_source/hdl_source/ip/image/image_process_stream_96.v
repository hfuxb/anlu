`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Anlu contest migration
// Engineer:        Codex
//
// Create Date:     2026/09/01 22:00:00
// Design Name:     image_process_stream_96
// Module Name:     image_process_stream_96
// Description:     Four-pixel RGB888 streaming grayscale, Sobel and morphology.
// Simulations:     sim/tb_image_process_stream_96.sv (Icarus PASS)
//
// Referrences:     PH1P35_image_processing_migration_report.pdf and reviewed algorithm contract.
// Dependencies:    None
//
// Version:         V1.1
// Revision Date:   2026/09/02 14:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/09/01       V1.0        Codex             Create streaming image process.
// 2026/09/02       V1.1        Codex             Add arithmetic and morphology pipeline stages.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        安路赛题迁移工程
// 开发人员:        Codex
//
// 创建日期:        2026年09月01日
// 设计名称:        image_process_stream_96
// 模块名称:        image_process_stream_96
// 模块说明:        96位四像素流灰度、Sobel、腐蚀和膨胀处理。
// 仿真工程:        sim/tb_image_process_stream_96.sv（Icarus 已通过）
// 参考资料:        PH1P35_image_processing_migration_report.pdf及已复核的算法约定。
// 依赖文件:        无
//
// 当前版本:        V1.1
// 修订日期:        2026年09月02日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年09月01日   V1.0        Codex             创建四像素流处理模块。
// 2026年09月02日   V1.1        Codex             增加算术和形态学流水级，降低MIPI字节时钟关键路径。

module image_process_stream_96 #(
	parameter integer IMG_WIDTH  = 1024, // 图像宽度，单位为像素，必须是4的整数倍。
	parameter integer IMG_HEIGHT = 600   // 图像高度，单位为像素。
) (
	// 全局时钟与复位
	input  wire        I_clk,
	input  wire        I_rst_n,

	// 输入四像素视频流
	input  wire        I_tuser,
	input  wire        I_tlast,
	input  wire        I_tvalid,
	input  wire [95:0] I_tdata,

	// 帧级算法配置
	input  wire [1:0]  I_algo_mode,
	input  wire [10:0] I_edge_threshold,

	// 输出四像素视频流
	output reg         O_tuser,
	output reg         O_tlast,
	output reg         O_tvalid,
	output reg  [95:0] O_tdata
);

	// 每个输入拍包含4个像素，因此横向处理坐标按4像素折算。
	localparam integer GROUP_WIDTH = IMG_WIDTH / 4;

	// 算法选择编码：00为原图，01为Sobel，10为腐蚀，11为膨胀。
	localparam [1:0] MODE_RAW      = 2'b00;
	localparam [1:0] MODE_SOBEL    = 2'b01;
	localparam [1:0] MODE_EROSION  = 2'b10;
	localparam [1:0] MODE_DILATION = 2'b11;

	//********************************************************************//
	//****************** Parameter and Internal Signal *******************//
	//********************************************************************//
	// 两行灰度缓存：line_a为上一行，line_b为上上行。
	reg [7:0] gray_line_a [0:GROUP_WIDTH-1];
	reg [7:0] gray_line_b [0:GROUP_WIDTH-1];
	// 两行Sobel二值缓存，供当前行的3x3形态学窗口使用。
	reg       bin_line_a  [0:GROUP_WIDTH-1];
	reg       bin_line_b  [0:GROUP_WIDTH-1];

	// 灰度窗口的横向延迟：_2为左侧，_1为中间。
	reg [7:0] gray_top_delay_2;
	reg [7:0] gray_top_delay_1;
	reg [7:0] gray_mid_delay_2;
	reg [7:0] gray_mid_delay_1;
	reg [7:0] gray_cur_delay_2;
	reg [7:0] gray_cur_delay_1;

	// 二值窗口的横向延迟：_2为左侧，_1为中间。
	reg       bin_top_delay_2;
	reg       bin_top_delay_1;
	reg       bin_mid_delay_2;
	reg       bin_mid_delay_1;
	reg       bin_cur_delay_2;
	reg       bin_cur_delay_1;

	// 当前输入拍的处理组坐标。
	reg [7:0] x_group;
	reg [9:0] y_pos;
	// 帧开始时锁存的算法模式和Sobel阈值。
	reg [1:0]  frame_mode;
	reg [10:0] frame_threshold;

	// I_tuser所在拍使用输入配置，其余拍使用已经锁存的帧配置。
	wire [7:0] active_x;
	wire [9:0] active_y;
	wire [1:0] active_mode;
	wire [10:0] active_threshold;

	assign active_x         = I_tuser ? 8'd0 : x_group;
	assign active_y         = I_tuser ? 10'd0 : y_pos;
	assign active_mode      = I_tuser ? I_algo_mode : frame_mode;
	assign active_threshold = I_tuser ? I_edge_threshold : frame_threshold;

	//********************************************************************//
	//*************************** Pipeline Stage 0 **********************//
	//********************************************************************//
	// 第一流水级只完成RGB加权乘法，并锁存输入控制信息。
	reg        stage0_valid;
	reg        stage0_user;
	reg        stage0_last;
	reg [95:0] stage0_raw_data;
	reg [7:0]  stage0_x;
	reg [9:0]  stage0_y;
	reg [1:0]  stage0_mode;
	reg [10:0] stage0_threshold;
	reg [15:0] stage0_gray_r_0;
	reg [15:0] stage0_gray_g_0;
	reg [15:0] stage0_gray_b_0;
	reg [15:0] stage0_gray_r_1;
	reg [15:0] stage0_gray_g_1;
	reg [15:0] stage0_gray_b_1;
	reg [15:0] stage0_gray_r_2;
	reg [15:0] stage0_gray_g_2;
	reg [15:0] stage0_gray_b_2;
	reg [15:0] stage0_gray_r_3;
	reg [15:0] stage0_gray_g_3;
	reg [15:0] stage0_gray_b_3;

	// 灰度公式为gray=(77*R+150*G+29*B)>>8。
	// 每个乘法的输入显式扩展到16位，避免表达式宽度导致乘积截断。
	wire [15:0] input_gray_r_0;
	wire [15:0] input_gray_g_0;
	wire [15:0] input_gray_b_0;
	wire [15:0] input_gray_r_1;
	wire [15:0] input_gray_g_1;
	wire [15:0] input_gray_b_1;
	wire [15:0] input_gray_r_2;
	wire [15:0] input_gray_g_2;
	wire [15:0] input_gray_b_2;
	wire [15:0] input_gray_r_3;
	wire [15:0] input_gray_g_3;
	wire [15:0] input_gray_b_3;

	assign input_gray_r_0 = ({8'd0, I_tdata[23:16]} * 16'd77);
	assign input_gray_g_0 = ({8'd0, I_tdata[15:8]}  * 16'd150);
	assign input_gray_b_0 = ({8'd0, I_tdata[7:0]}   * 16'd29);
	assign input_gray_r_1 = ({8'd0, I_tdata[47:40]} * 16'd77);
	assign input_gray_g_1 = ({8'd0, I_tdata[39:32]} * 16'd150);
	assign input_gray_b_1 = ({8'd0, I_tdata[31:24]} * 16'd29);
	assign input_gray_r_2 = ({8'd0, I_tdata[71:64]} * 16'd77);
	assign input_gray_g_2 = ({8'd0, I_tdata[63:56]} * 16'd150);
	assign input_gray_b_2 = ({8'd0, I_tdata[55:48]} * 16'd29);
	assign input_gray_r_3 = ({8'd0, I_tdata[95:88]} * 16'd77);
	assign input_gray_g_3 = ({8'd0, I_tdata[87:80]} * 16'd150);
	assign input_gray_b_3 = ({8'd0, I_tdata[79:72]} * 16'd29);

	//********************************************************************//
	//*************************** Pipeline Stage 1 **********************//
	//********************************************************************//
	// 第二流水级完成三个乘积的加法，并输出四个像素的灰度值。
	reg        stage1_valid;
	reg        stage1_user;
	reg        stage1_last;
	reg [95:0] stage1_raw_data;
	reg [7:0]  stage1_x;
	reg [9:0]  stage1_y;
	reg [1:0]  stage1_mode;
	reg [10:0] stage1_threshold;
	reg [7:0]  stage1_gray_0;
	reg [7:0]  stage1_gray_1;
	reg [7:0]  stage1_gray_2;
	reg [7:0]  stage1_gray_3;

	wire [15:0] stage0_gray_sum_0;
	wire [15:0] stage0_gray_sum_1;
	wire [15:0] stage0_gray_sum_2;
	wire [15:0] stage0_gray_sum_3;

	assign stage0_gray_sum_0 = stage0_gray_r_0 + stage0_gray_g_0 + stage0_gray_b_0;
	assign stage0_gray_sum_1 = stage0_gray_r_1 + stage0_gray_g_1 + stage0_gray_b_1;
	assign stage0_gray_sum_2 = stage0_gray_r_2 + stage0_gray_g_2 + stage0_gray_b_2;
	assign stage0_gray_sum_3 = stage0_gray_r_3 + stage0_gray_g_3 + stage0_gray_b_3;

	//********************************************************************//
	//*************************** Pipeline Stage 2 **********************//
	//********************************************************************//
	// 第三流水级计算组平均灰度，同时读取和更新两行灰度缓存。
	reg        stage2_valid;
	reg        stage2_user;
	reg        stage2_last;
	reg [95:0] stage2_raw_data;
	reg [7:0]  stage2_x;
	reg [9:0]  stage2_y;
	reg [1:0]  stage2_mode;
	reg [10:0] stage2_threshold;
	reg [7:0]  stage2_gray_top_2;
	reg [7:0]  stage2_gray_top_1;
	reg [7:0]  stage2_gray_top_current;
	reg [7:0]  stage2_gray_mid_2;
	reg [7:0]  stage2_gray_mid_1;
	reg [7:0]  stage2_gray_mid_current;
	reg [7:0]  stage2_gray_cur_2;
	reg [7:0]  stage2_gray_cur_1;
	reg [7:0]  stage2_gray_cur_current;

	wire [9:0] stage1_gray_group_sum;
	wire [7:0] stage1_gray_group;
	wire [7:0] stage1_gray_top_current;
	wire [7:0] stage1_gray_mid_current;

	assign stage1_gray_group_sum = {2'b0, stage1_gray_0}
								 + {2'b0, stage1_gray_1}
								 + {2'b0, stage1_gray_2}
								 + {2'b0, stage1_gray_3};
	assign stage1_gray_group = stage1_gray_group_sum[9:2];
	assign stage1_gray_top_current = gray_line_b[stage1_x];
	assign stage1_gray_mid_current = gray_line_a[stage1_x];

	//********************************************************************//
	//*************************** Pipeline Stage 3 **********************//
	//********************************************************************//
	// 第四流水级完成Sobel和二值缓存更新，避免Sobel算术链直接连接输出寄存器。
	reg        stage3_valid;
	reg        stage3_user;
	reg        stage3_last;
	reg [95:0] stage3_raw_data;
	reg [7:0]  stage3_x;
	reg [9:0]  stage3_y;
	reg [1:0]  stage3_mode;
	reg        stage3_sobel_bit;
	reg        stage3_bin_top_2;
	reg        stage3_bin_top_1;
	reg        stage3_bin_top_current;
	reg        stage3_bin_mid_2;
	reg        stage3_bin_mid_1;
	reg        stage3_bin_mid_current;
	reg        stage3_bin_cur_2;
	reg        stage3_bin_cur_1;
	reg        stage3_bin_cur_current;

	// 当前列对应的上两行Sobel二值数据。
	wire stage2_bin_top_current_bit;
	wire stage2_bin_mid_current_bit;

	assign stage2_bin_top_current_bit = bin_line_b[stage2_x];
	assign stage2_bin_mid_current_bit = bin_line_a[stage2_x];

	// 3x3窗口右下角为当前处理组，横向数据来自stage2寄存器。
	wire signed [12:0] stage2_sobel_gx;
	wire signed [12:0] stage2_sobel_gy;
	wire [12:0] stage2_sobel_abs_gx;
	wire [12:0] stage2_sobel_abs_gy;
	wire [12:0] stage2_sobel_magnitude;
	wire stage2_sobel_window_bit;
	wire stage2_sobel_bit;

	assign stage2_sobel_gx =
			$signed({5'b0, stage2_gray_top_current})
		+ ($signed({5'b0, stage2_gray_mid_current}) <<< 1)
		+ $signed({5'b0, stage2_gray_cur_current})
		- $signed({5'b0, stage2_gray_top_2})
		- ($signed({5'b0, stage2_gray_mid_2}) <<< 1)
		- $signed({5'b0, stage2_gray_cur_2});
	assign stage2_sobel_gy =
			$signed({5'b0, stage2_gray_cur_2})
		+ ($signed({5'b0, stage2_gray_cur_1}) <<< 1)
		+ $signed({5'b0, stage2_gray_cur_current})
		- $signed({5'b0, stage2_gray_top_2})
		- ($signed({5'b0, stage2_gray_top_1}) <<< 1)
		- $signed({5'b0, stage2_gray_top_current});
	assign stage2_sobel_abs_gx = stage2_sobel_gx[12]
							? (~stage2_sobel_gx + 13'd1) : stage2_sobel_gx;
	assign stage2_sobel_abs_gy = stage2_sobel_gy[12]
							? (~stage2_sobel_gy + 13'd1) : stage2_sobel_gy;
	assign stage2_sobel_magnitude = stage2_sobel_abs_gx + stage2_sobel_abs_gy;
	assign stage2_sobel_window_bit = stage2_sobel_magnitude > {2'b0, stage2_threshold};

	// 前两列和前两行没有完整3x3窗口，统一输出黑色边界。
	assign stage2_sobel_bit = ((stage2_x < 8'd2) || (stage2_y < 10'd2))
							? 1'b0 : stage2_sobel_window_bit;

	//********************************************************************//
	//*************************** Output Calculate ***********************//
	//********************************************************************//
	// 输出级只执行形态学窗口和模式选择，输出延迟为输入后的4个时钟周期。
	wire [8:0] stage3_morphology_taps;
	wire stage3_morphology_valid;
	wire stage3_erosion_bit;
	wire stage3_dilation_bit;
	wire [23:0] stage3_sobel_pixel;
	wire [23:0] stage3_erosion_pixel;
	wire [23:0] stage3_dilation_pixel;
	wire [95:0] stage3_sobel_word;
	wire [95:0] stage3_erosion_word;
	wire [95:0] stage3_dilation_word;

	assign stage3_morphology_taps = {
		stage3_bin_top_2,
		stage3_bin_top_1,
		stage3_bin_top_current,
		stage3_bin_mid_2,
		stage3_bin_mid_1,
		stage3_bin_mid_current,
		stage3_bin_cur_2,
		stage3_bin_cur_1,
		stage3_bin_cur_current
	};
	assign stage3_morphology_valid = (stage3_x >= 8'd2) && (stage3_y >= 10'd2);
	assign stage3_erosion_bit = stage3_morphology_valid ? (&stage3_morphology_taps) : 1'b0;
	assign stage3_dilation_bit = stage3_morphology_valid ? (|stage3_morphology_taps) : 1'b0;

	// 二值结果转换为RGB白色或黑色，并复制到四个输出像素。
	assign stage3_sobel_pixel   = stage3_sobel_bit   ? 24'hffffff : 24'h000000;
	assign stage3_erosion_pixel = stage3_erosion_bit ? 24'hffffff : 24'h000000;
	assign stage3_dilation_pixel = stage3_dilation_bit ? 24'hffffff : 24'h000000;
	assign stage3_sobel_word = {
		stage3_sobel_pixel, stage3_sobel_pixel, stage3_sobel_pixel, stage3_sobel_pixel
	};
	assign stage3_erosion_word = {
		stage3_erosion_pixel, stage3_erosion_pixel, stage3_erosion_pixel, stage3_erosion_pixel
	};
	assign stage3_dilation_word = {
		stage3_dilation_pixel, stage3_dilation_pixel, stage3_dilation_pixel, stage3_dilation_pixel
	};

	//********************************************************************//
	//***************************** Main Code ****************************//
	//********************************************************************//
	// 固定速率视频流：输入有效时产生一个延迟4拍的对应输出，不使用反压。
	always @(posedge I_clk or negedge I_rst_n) begin
		if (!I_rst_n) begin
			// 复位坐标、帧配置、窗口延迟和输出标志。
			x_group          <= 8'd0;
			y_pos            <= 10'd0;
			frame_mode       <= MODE_RAW;
			frame_threshold  <= 11'd24;

			gray_top_delay_2 <= 8'd0;
			gray_top_delay_1 <= 8'd0;
			gray_mid_delay_2 <= 8'd0;
			gray_mid_delay_1 <= 8'd0;
			gray_cur_delay_2 <= 8'd0;
			gray_cur_delay_1 <= 8'd0;
			bin_top_delay_2  <= 1'b0;
			bin_top_delay_1  <= 1'b0;
			bin_mid_delay_2  <= 1'b0;
			bin_mid_delay_1  <= 1'b0;
			bin_cur_delay_2  <= 1'b0;
			bin_cur_delay_1  <= 1'b0;

			stage0_valid     <= 1'b0;
			stage0_user      <= 1'b0;
			stage0_last      <= 1'b0;
			stage0_raw_data  <= 96'd0;
			stage0_x         <= 8'd0;
			stage0_y         <= 10'd0;
			stage0_mode      <= MODE_RAW;
			stage0_threshold  <= 11'd24;
			stage0_gray_r_0  <= 16'd0;
			stage0_gray_g_0  <= 16'd0;
			stage0_gray_b_0  <= 16'd0;
			stage0_gray_r_1  <= 16'd0;
			stage0_gray_g_1  <= 16'd0;
			stage0_gray_b_1  <= 16'd0;
			stage0_gray_r_2  <= 16'd0;
			stage0_gray_g_2  <= 16'd0;
			stage0_gray_b_2  <= 16'd0;
			stage0_gray_r_3  <= 16'd0;
			stage0_gray_g_3  <= 16'd0;
			stage0_gray_b_3  <= 16'd0;

			stage1_valid     <= 1'b0;
			stage1_user      <= 1'b0;
			stage1_last      <= 1'b0;
			stage1_raw_data  <= 96'd0;
			stage1_x         <= 8'd0;
			stage1_y         <= 10'd0;
			stage1_mode      <= MODE_RAW;
			stage1_threshold <= 11'd24;
			stage1_gray_0    <= 8'd0;
			stage1_gray_1    <= 8'd0;
			stage1_gray_2    <= 8'd0;
			stage1_gray_3    <= 8'd0;

			stage2_valid            <= 1'b0;
			stage2_user             <= 1'b0;
			stage2_last             <= 1'b0;
			stage2_raw_data         <= 96'd0;
			stage2_x                <= 8'd0;
			stage2_y                <= 10'd0;
			stage2_mode             <= MODE_RAW;
			stage2_threshold        <= 11'd24;
			stage2_gray_top_2       <= 8'd0;
			stage2_gray_top_1       <= 8'd0;
			stage2_gray_top_current <= 8'd0;
			stage2_gray_mid_2       <= 8'd0;
			stage2_gray_mid_1       <= 8'd0;
			stage2_gray_mid_current <= 8'd0;
			stage2_gray_cur_2       <= 8'd0;
			stage2_gray_cur_1       <= 8'd0;
			stage2_gray_cur_current <= 8'd0;

			stage3_valid             <= 1'b0;
			stage3_user              <= 1'b0;
			stage3_last              <= 1'b0;
			stage3_raw_data          <= 96'd0;
			stage3_x                 <= 8'd0;
			stage3_y                 <= 10'd0;
			stage3_mode              <= MODE_RAW;
			stage3_sobel_bit         <= 1'b0;
			stage3_bin_top_2         <= 1'b0;
			stage3_bin_top_1         <= 1'b0;
			stage3_bin_top_current   <= 1'b0;
			stage3_bin_mid_2         <= 1'b0;
			stage3_bin_mid_1         <= 1'b0;
			stage3_bin_mid_current   <= 1'b0;
			stage3_bin_cur_2         <= 1'b0;
			stage3_bin_cur_1         <= 1'b0;
			stage3_bin_cur_current   <= 1'b0;

			O_tuser                  <= 1'b0;
			O_tlast                  <= 1'b0;
			O_tvalid                 <= 1'b0;
			O_tdata                  <= 96'd0;
		end
		else begin
			// 输出级：模式、数据和标志均来自同一个stage3处理组。
			O_tuser  <= 1'b0;
			O_tlast  <= 1'b0;
			O_tvalid <= stage3_valid;
			O_tdata  <= 96'd0;
			if (stage3_valid) begin
				O_tuser <= stage3_user;
				O_tlast <= stage3_last;
				case (stage3_mode)
					MODE_SOBEL:    O_tdata <= stage3_sobel_word;
					MODE_EROSION:  O_tdata <= stage3_erosion_word;
					MODE_DILATION: O_tdata <= stage3_dilation_word;
					default:       O_tdata <= stage3_raw_data;
				endcase
			end

			// Stage3：完成Sobel，并把当前Sobel结果写入二值行缓存。
			stage3_valid <= stage2_valid;
			stage3_user  <= stage2_user;
			stage3_last  <= stage2_last;
			if (stage2_valid) begin
				stage3_raw_data        <= stage2_raw_data;
				stage3_x               <= stage2_x;
				stage3_y               <= stage2_y;
				stage3_mode            <= stage2_mode;
				stage3_sobel_bit       <= stage2_sobel_bit;
				stage3_bin_top_2       <= bin_top_delay_2;
				stage3_bin_top_1       <= bin_top_delay_1;
				stage3_bin_top_current <= stage2_bin_top_current_bit;
				stage3_bin_mid_2       <= bin_mid_delay_2;
				stage3_bin_mid_1       <= bin_mid_delay_1;
				stage3_bin_mid_current <= stage2_bin_mid_current_bit;
				stage3_bin_cur_2       <= bin_cur_delay_2;
				stage3_bin_cur_1       <= bin_cur_delay_1;
				stage3_bin_cur_current <= stage2_sobel_bit;

				if (stage2_y == 10'd0) begin
					bin_line_a[stage2_x] <= stage2_sobel_bit;
				end
				else begin
					bin_line_b[stage2_x] <= bin_line_a[stage2_x];
					bin_line_a[stage2_x] <= stage2_sobel_bit;
				end

				if (stage2_last) begin
					bin_top_delay_2 <= 1'b0;
					bin_top_delay_1 <= 1'b0;
					bin_mid_delay_2 <= 1'b0;
					bin_mid_delay_1 <= 1'b0;
					bin_cur_delay_2 <= 1'b0;
					bin_cur_delay_1 <= 1'b0;
				end
				else begin
					bin_top_delay_2 <= bin_top_delay_1;
					bin_top_delay_1 <= stage2_bin_top_current_bit;
					bin_mid_delay_2 <= bin_mid_delay_1;
					bin_mid_delay_1 <= stage2_bin_mid_current_bit;
					bin_cur_delay_2 <= bin_cur_delay_1;
					bin_cur_delay_1 <= stage2_sobel_bit;
				end
			end

			// Stage2：生成3x3灰度窗口，并推进灰度行缓存。
			stage2_valid <= stage1_valid;
			stage2_user  <= stage1_user;
			stage2_last  <= stage1_last;
			if (stage1_valid) begin
				stage2_raw_data         <= stage1_raw_data;
				stage2_x                <= stage1_x;
				stage2_y                <= stage1_y;
				stage2_mode             <= stage1_mode;
				stage2_threshold        <= stage1_threshold;
				stage2_gray_top_2       <= gray_top_delay_2;
				stage2_gray_top_1       <= gray_top_delay_1;
				stage2_gray_top_current <= gray_line_b[stage1_x];
				stage2_gray_mid_2       <= gray_mid_delay_2;
				stage2_gray_mid_1       <= gray_mid_delay_1;
				stage2_gray_mid_current <= gray_line_a[stage1_x];
				stage2_gray_cur_2       <= gray_cur_delay_2;
				stage2_gray_cur_1       <= gray_cur_delay_1;
				stage2_gray_cur_current <= stage1_gray_group;

				if (stage1_y == 10'd0) begin
					gray_line_a[stage1_x] <= stage1_gray_group;
				end
				else begin
					gray_line_b[stage1_x] <= gray_line_a[stage1_x];
					gray_line_a[stage1_x] <= stage1_gray_group;
				end

				if (stage1_last) begin
					gray_top_delay_2 <= 8'd0;
					gray_top_delay_1 <= 8'd0;
					gray_mid_delay_2 <= 8'd0;
					gray_mid_delay_1 <= 8'd0;
					gray_cur_delay_2 <= 8'd0;
					gray_cur_delay_1 <= 8'd0;
				end
				else begin
					gray_top_delay_2 <= gray_top_delay_1;
					gray_top_delay_1 <= gray_line_b[stage1_x];
					gray_mid_delay_2 <= gray_mid_delay_1;
					gray_mid_delay_1 <= gray_line_a[stage1_x];
					gray_cur_delay_2 <= gray_cur_delay_1;
					gray_cur_delay_1 <= stage1_gray_group;
				end
			end

			// Stage1：锁存四个像素的灰度结果和控制信息。
			stage1_valid <= stage0_valid;
			stage1_user  <= stage0_user;
			stage1_last  <= stage0_last;
			if (stage0_valid) begin
				stage1_raw_data  <= stage0_raw_data;
				stage1_x         <= stage0_x;
				stage1_y         <= stage0_y;
				stage1_mode      <= stage0_mode;
				stage1_threshold <= stage0_threshold;
				stage1_gray_0   <= stage0_gray_sum_0[15:8];
				stage1_gray_1   <= stage0_gray_sum_1[15:8];
				stage1_gray_2   <= stage0_gray_sum_2[15:8];
				stage1_gray_3   <= stage0_gray_sum_3[15:8];
			end

			// Stage0：输入有效时锁存乘积、坐标、标志和帧级配置。
			stage0_valid <= I_tvalid;
			stage0_user  <= I_tvalid && I_tuser;
			stage0_last  <= I_tvalid && I_tlast;
			if (I_tvalid) begin
				stage0_raw_data <= I_tdata;
				stage0_x        <= active_x;
				stage0_y        <= active_y;
				stage0_mode     <= active_mode;
				stage0_threshold <= active_threshold;
				stage0_gray_r_0 <= input_gray_r_0;
				stage0_gray_g_0 <= input_gray_g_0;
				stage0_gray_b_0 <= input_gray_b_0;
				stage0_gray_r_1 <= input_gray_r_1;
				stage0_gray_g_1 <= input_gray_g_1;
				stage0_gray_b_1 <= input_gray_b_1;
				stage0_gray_r_2 <= input_gray_r_2;
				stage0_gray_g_2 <= input_gray_g_2;
				stage0_gray_b_2 <= input_gray_b_2;
				stage0_gray_r_3 <= input_gray_r_3;
				stage0_gray_g_3 <= input_gray_g_3;
				stage0_gray_b_3 <= input_gray_b_3;

				if (I_tuser) begin
					frame_mode      <= I_algo_mode;
					frame_threshold <= I_edge_threshold;
				end

				// 输入行结束后更新下一行坐标。
				if (I_tlast) begin
					x_group <= 8'd0;
					if (active_y == IMG_HEIGHT - 1)
						y_pos <= 10'd0;
					else
						y_pos <= active_y + 10'd1;
				end
				else begin
					x_group <= active_x + 8'd1;
					y_pos   <= active_y;
				end
			end
		end
	end

endmodule
