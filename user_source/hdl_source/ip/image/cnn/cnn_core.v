`timescale 1ns / 1ps
`include "cnn_quant_params.vh"

////////////////////////////////////English///////////////////////////////////////
// Company:         Anlu contest migration
// Engineer:        Codex
//
// Create Date:     2026/09/09 16:00:00
// Design Name:     cnn_core
// Module Name:     cnn_core
// Description:     description/cnn_core_Design.pdf
// Simulations:     testbench/vivado/2021.1/cnn_core
//
// Referrences:     D:/anlu/work/td_opt_20260909
// Dependencies:    cnn_quant_params.vh, cnn_feat_bram.v, cnn_input_bram.v,
//                  cnn_weight_rom.v, cnn_bias_rom.v
//
// Version:         V1.0
// Revision Date:   2026/09/09 16:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/09/09       V1.0        Codex             Optimize MAC and accumulator widths.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        安路赛题迁移工程
// 开发人员:        Codex
//
// 创建日期:        2026年09月09日
// 设计名称:        cnn_core
// 模块名称:        cnn_core
// 模块说明:        Description/cnn_core_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/cnn_core
//
// 参考资料:        D:/anlu/work/td_opt_20260909
// 依赖文件:        cnn_quant_params.vh、cnn_feat_bram.v、cnn_input_bram.v、
//                  cnn_weight_rom.v、cnn_bias_rom.v
//
// 当前版本:        V1.0
// 修订日期:        2026年09月09日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年09月09日   V1.0        Codex             优化MAC和累加器位宽。

module cnn_core (
	input  wire        aclk,
	input  wire        aresetn,
	input  wire        start,
	input  wire        input_frame_ready,
	input  wire        input_bank_select,
	output reg         input_rd_bank,
	output reg  [11:0] input_rd_addr,
	input  wire [7:0]  input_rd_data,
	output reg         busy,
	output reg         done,
	output reg         result_valid,
	output reg  [4:0]  result_class,
	output reg  [7:0]  result_ascii
);

	localparam [2:0] LAYER_CONV1 = 3'd0;
	localparam [2:0] LAYER_CONV2 = 3'd1;
	localparam [2:0] LAYER_CONV3 = 3'd2;

	localparam [5:0]
		ST_IDLE          = 6'd0,
		ST_LOAD_BIAS_REQ = 6'd1,
		ST_LOAD_BIAS     = 6'd2,
		ST_CONV1_INIT    = 6'd3,
		ST_CONV1_REQ     = 6'd4,
		ST_CONV1_WAIT    = 6'd5,
		ST_CONV1_CAPTURE = 6'd6,
		ST_CONV1_PREP    = 6'd7,
		ST_CONV1_MAC     = 6'd8,
		ST_CONV1_FINISH  = 6'd9,
		ST_CONV1_WRITE   = 6'd10,
		ST_CONV_INIT     = 6'd11,
		ST_CONV_REQ      = 6'd12,
		ST_CONV_WAIT     = 6'd13,
		ST_CONV_CAPTURE  = 6'd14,
		ST_CONV_PREP     = 6'd15,
		ST_CONV_MAC      = 6'd16,
		ST_CONV_FINISH   = 6'd17,
		ST_POOL_RMW_WAIT = 6'd18,
		ST_POOL_RMW_CAP  = 6'd19,
		ST_FC1_INIT      = 6'd20,
		ST_FC1_REQ       = 6'd21,
		ST_FC1_WAIT      = 6'd22,
		ST_FC1_CAPTURE   = 6'd23,
		ST_FC1_PREP      = 6'd24,
		ST_FC1_MAC       = 6'd25,
		ST_FC1_FINISH    = 6'd26,
		ST_FC1_WRITE     = 6'd27,
		ST_FC2_INIT      = 6'd28,
		ST_FC2_REQ       = 6'd29,
		ST_FC2_WAIT      = 6'd30,
		ST_FC2_CAPTURE   = 6'd31,
		ST_FC2_PREP      = 6'd32,
		ST_FC2_MAC       = 6'd33,
		ST_FC2_FINISH    = 6'd34,
		ST_CONV1_POOL    = 6'd35,
		ST_CONV_POOL     = 6'd36;

	localparam integer CONV1_W_BASE = 0;
	localparam integer CONV2_W_BASE = 9;
	localparam integer CONV3_W_BASE = 153;
	localparam integer FC1_W_BASE   = 729;
	localparam integer FC2_W_BASE   = 17113;
	localparam integer WEIGHT_DEPTH = 17321;

	localparam integer BIAS_CONV1_BASE = 0;
	localparam integer BIAS_CONV2_BASE = 8;
	localparam integer BIAS_CONV3_BASE = 24;
	localparam integer BIAS_FC1_BASE   = 56;
	localparam integer BIAS_FC2_BASE   = 120;

	// 当前网络的有符号累加范围。扩展层时只调整下面三个位宽参数。
	localparam integer MAC_SUM_WIDTH    = 19;
	localparam integer CONV_ACCUM_WIDTH = 23;
	localparam integer FC_ACCUM_WIDTH   = 26;

	reg [5:0] state;
	reg [2:0] layer_sel;

	// 卷积位置、输出通道和3x3核索引。
	reg [5:0] conv_x;
	reg [5:0] conv_y;
	reg [5:0] out_channel;
	reg [3:0] kernel_index;
	reg       input_group;

	// 八个并行卷积累加器；conv2/conv3使用累加器0。
	reg signed [CONV_ACCUM_WIDTH-1:0] conv_accum [0:7];
	reg [7:0] pool_max;
	reg [7:0] pool_max_lane [0:7];
	reg [7:0]  conv_prev_row  [0:31];
	reg [7:0]  conv1_sample_reg;
	reg [63:0] conv_feature_word_reg;
	reg [63:0] fc_feature_word_reg;
	reg [63:0] conv1_pool_word_reg;
	reg [63:0] conv1_q_word_reg;
	reg [63:0] conv1_prev_word_reg;
	reg [7:0] conv_q_reg;
	reg [7:0] conv_prev_q_reg;
	// 单个八位输入和权重的乘积范围为-32640..32385，十六位有符号数足够。
	// 只在卷积1使用该寄存器，缩短寄存器和布局布线资源。
	reg signed [15:0] mac_product_reg [0:7];
	reg signed [MAC_SUM_WIDTH-1:0] mac_sum_reg;
	reg [1:0]  mac_mode_reg;

	// 卷积池化结果的写回上下文。
	reg [9:0] pool_write_addr;
	reg [2:0] pool_write_lane;
	reg [7:0] pool_write_value;

	// FC索引和累加器。
	reg [6:0]  fc_out_index;
	reg [8:0]  fc_word_index;
	reg signed [FC_ACCUM_WIDTH-1:0] fc_accum;
	reg signed [FC_ACCUM_WIDTH-1:0] fc_bias_reg;
	reg signed [FC_ACCUM_WIDTH-1:0] best_logit;
	reg        best_valid;
	reg [2:0]  fc_write_index;
	reg [63:0] fc1_output_words [0:7];

	// 偏置加载缓存。每层开始时只从偏置ROM读取一次。
	reg [7:0] bias_load_base;
	reg [6:0] bias_load_index;
	reg [6:0] bias_load_limit;
	reg [31:0] bias_values [0:63];
	wire [7:0] bias_rom_addr = bias_load_base + {1'b0, bias_load_index};
	wire [31:0] bias_rom_data;

	// 特征图A/B：每个地址为8个八位特征值。
	reg        feat_a_wr_en;
	reg [9:0]  feat_a_wr_addr;
	reg [63:0] feat_a_wr_data;
	reg [9:0]  feat_a_rd_addr;
	wire [63:0] feat_a_rd_data;
	reg        feat_b_wr_en;
	reg [9:0]  feat_b_wr_addr;
	reg [63:0] feat_b_wr_data;
	reg [9:0]  feat_b_rd_addr;
	wire [63:0] feat_b_rd_data;

	wire [63:0] weight_rom_data;
	reg  [14:0] weight_addr_reg;
	reg  [63:0] weight_data_reg;

	integer i;

	cnn_feat_bram u_cnn_feat_bram_a (
		.clka  (aclk),
		.wea   (feat_a_wr_en),
		.addra (feat_a_wr_addr),
		.dina  (feat_a_wr_data),
		.clkb  (aclk),
		.addrb (feat_a_rd_addr),
		.doutb (feat_a_rd_data)
	);

	cnn_feat_bram #(
		.DEPTH (512)
	) u_cnn_feat_bram_b (
		.clka  (aclk),
		.wea   (feat_b_wr_en),
		.addra (feat_b_wr_addr),
		.dina  (feat_b_wr_data),
		.clkb  (aclk),
		.addrb (feat_b_rd_addr),
		.doutb (feat_b_rd_data)
	);

	cnn_weight_rom #(
		.DEPTH(WEIGHT_DEPTH)
	) u_cnn_weight_rom (
		.clk       (aclk),
		.addr      (weight_addr_reg),
		.dout      (weight_rom_data),
		.bias_addr (bias_rom_addr),
		.bias_read (state == ST_LOAD_BIAS_REQ || state == ST_LOAD_BIAS),
		.bias_dout (bias_rom_data)
	);

	// Function helpers.
	function [7:0] F_lane8;
		input [63:0] I_word;
		input [2:0] I_lane;
		begin
			case (I_lane)
				3'd0: F_lane8 = I_word[7:0];
				3'd1: F_lane8 = I_word[15:8];
				3'd2: F_lane8 = I_word[23:16];
				3'd3: F_lane8 = I_word[31:24];
				3'd4: F_lane8 = I_word[39:32];
				3'd5: F_lane8 = I_word[47:40];
				3'd6: F_lane8 = I_word[55:48];
				default: F_lane8 = I_word[63:56];
			endcase
		end
	endfunction

	function signed [15:0] F_mul_u8_s8;
		input [7:0] I_data;
		input [7:0] I_weight;
		reg signed [8:0] data_s;
		reg signed [7:0] weight_s;
		reg signed [16:0] product_s;
		begin
			data_s = {1'b0, I_data};
			weight_s = I_weight;
			product_s = data_s * weight_s;
			F_mul_u8_s8 = product_s[15:0];
		end
	endfunction

	function [7:0] F_relu_quant;
		input signed [31:0] I_value;
		input [4:0] I_shift;
		reg signed [31:0] shifted_s;
		begin
			shifted_s = I_value >>> I_shift;
			if (shifted_s <= 0)
				F_relu_quant = 8'd0;
			else if (shifted_s > 32'sd127)
				F_relu_quant = 8'd127;
			else
				F_relu_quant = shifted_s[7:0];
		end
	endfunction

	function [63:0] F_replace_lane;
		input [63:0] I_word;
		input [2:0] I_lane;
		input [7:0] I_value;
		reg [63:0] word_r;
		begin
			word_r = I_word;
			case (I_lane)
				3'd0: word_r[7:0]   = I_value;
				3'd1: word_r[15:8]  = I_value;
				3'd2: word_r[23:16] = I_value;
				3'd3: word_r[31:24] = I_value;
				3'd4: word_r[39:32] = I_value;
				3'd5: word_r[47:40] = I_value;
				3'd6: word_r[55:48] = I_value;
				default: word_r[63:56] = I_value;
			endcase
			F_replace_lane = word_r;
		end
	endfunction

	function [1:0] F_kernel_x;
		input [3:0] I_index;
		begin
			case (I_index)
				4'd0, 4'd3, 4'd6: F_kernel_x = 2'd0;
				4'd1, 4'd4, 4'd7: F_kernel_x = 2'd1;
				default: F_kernel_x = 2'd2;
			endcase
		end
	endfunction

	function [1:0] F_kernel_y;
		input [3:0] I_index;
		begin
			case (I_index)
				4'd0, 4'd1, 4'd2: F_kernel_y = 2'd0;
				4'd3, 4'd4, 4'd5: F_kernel_y = 2'd1;
				default: F_kernel_y = 2'd2;
			endcase
		end
	endfunction

	// 64x64输入图按行优先存储，显式扩展地址算术位宽。
	function [11:0] F_input_addr;
		input [5:0] I_y;
		input [5:0] I_x;
		begin
			F_input_addr = {I_y, 6'd0} + {6'd0, I_x};
		end
	endfunction

	// Conv1池化结果：32x32空间位置，每个地址保存8个输出通道。
	function [9:0] F_conv1_pool_addr;
		input [4:0] I_y;
		input [4:0] I_x;
		begin
			F_conv1_pool_addr = {I_y, 5'd0} + {5'd0, I_x};
		end
	endfunction

	// Conv2输入：32x32空间位置，每个地址保存8个输入通道。
	function [9:0] F_conv2_input_addr;
		input [4:0] I_y;
		input [4:0] I_x;
		begin
			F_conv2_input_addr = {I_y, 5'd0} + {5'd0, I_x};
		end
	endfunction

	// Conv3输入：16x16空间位置，每个空间位置分为两个八通道字。
	function [9:0] F_conv3_input_addr;
		input [3:0] I_y;
		input [3:0] I_x;
		input        I_group;
		reg [7:0] spatial_addr;
		begin
			spatial_addr = {I_y, 4'd0} + {4'd0, I_x};
			F_conv3_input_addr = {1'b0, spatial_addr, 1'b0} + I_group;
		end
	endfunction

	// Conv2池化结果：16x16空间位置，每个位置分为两个八通道字。
	function [9:0] F_conv2_pool_addr;
		input [4:0] I_y;
		input [4:0] I_x;
		input [2:0] I_group;
		reg [8:0] spatial_addr;
		begin
			spatial_addr = {I_y, 4'd0} + {4'd0, I_x};
			F_conv2_pool_addr = {spatial_addr, 1'b0} + I_group;
		end
	endfunction

	// Conv3池化结果：8x8空间位置，每个位置分为四个八通道字。
	function [9:0] F_conv3_pool_addr;
		input [3:0] I_y;
		input [3:0] I_x;
		input [2:0] I_group;
		reg [6:0] spatial_addr;
		begin
			spatial_addr = {I_y, 3'd0} + {3'd0, I_x};
			F_conv3_pool_addr = {spatial_addr, 2'b00} + I_group;
		end
	endfunction

	wire signed [7:0] sample_x = $signed({2'b0, conv_x})
								+ $signed({6'b0, F_kernel_x(kernel_index)}) - 8'sd1;
	wire signed [7:0] sample_y = $signed({2'b0, conv_y})
								+ $signed({6'b0, F_kernel_y(kernel_index)}) - 8'sd1;
	wire conv1_sample_in_bounds = (sample_x >= 0) && (sample_y >= 0) &&
								  (sample_x < 64) && (sample_y < 64);
	wire conv_sample_in_bounds = (layer_sel == LAYER_CONV2) ?
								  ((sample_x >= 0) && (sample_y >= 0) &&
								   (sample_x < 32) && (sample_y < 32)) :
								  ((sample_x >= 0) && (sample_y >= 0) &&
								   (sample_x < 16) && (sample_y < 16));
	wire [7:0] conv1_sample = conv1_sample_in_bounds ? input_rd_data : 8'd0;
	wire [63:0] conv_feature_sample = !conv_sample_in_bounds ? 64'd0 :
									   (layer_sel == LAYER_CONV2) ? feat_a_rd_data :
																	   feat_b_rd_data;

	// 八个乘法器由卷积和全连接状态复用，保持每拍八路并行吞吐。
	wire [7:0] mac_data_lane [0:7];
	// 单项乘积范围为 -32640..32385，八项和范围为 -261120..259080。
	// 使用精确的有符号位宽，避免 32 bit 加法树带来的无效进位链。
	wire signed [15:0] mac_product [0:7];
	wire signed [18:0] mac_sum;
	localparam [1:0] MAC_MODE_IDLE  = 2'd0;
	localparam [1:0] MAC_MODE_CONV1 = 2'd1;
	localparam [1:0] MAC_MODE_CONV  = 2'd2;
	localparam [1:0] MAC_MODE_FC    = 2'd3;

	wire mac_mode_conv1 = (mac_mode_reg == MAC_MODE_CONV1);
	wire [63:0] mac_feature_word = (mac_mode_reg == MAC_MODE_CONV) ?
								   conv_feature_word_reg :
								   (mac_mode_reg == MAC_MODE_FC) ?
								   fc_feature_word_reg : 64'd0;

	// PREP和MAC状态只使用已经锁存的输入数据，避免RAM输出和坐标逻辑
	// 穿过乘法器进入同一拍的累加寄存器。数据选择由寄存器保存，
	// 不直接使用FSM状态，减少状态译码对MAC路径的影响。

	assign mac_data_lane[0] = mac_mode_conv1 ? conv1_sample_reg : mac_feature_word[7:0];
	assign mac_data_lane[1] = mac_mode_conv1 ? conv1_sample_reg : mac_feature_word[15:8];
	assign mac_data_lane[2] = mac_mode_conv1 ? conv1_sample_reg : mac_feature_word[23:16];
	assign mac_data_lane[3] = mac_mode_conv1 ? conv1_sample_reg : mac_feature_word[31:24];
	assign mac_data_lane[4] = mac_mode_conv1 ? conv1_sample_reg : mac_feature_word[39:32];
	assign mac_data_lane[5] = mac_mode_conv1 ? conv1_sample_reg : mac_feature_word[47:40];
	assign mac_data_lane[6] = mac_mode_conv1 ? conv1_sample_reg : mac_feature_word[55:48];
	assign mac_data_lane[7] = mac_mode_conv1 ? conv1_sample_reg : mac_feature_word[63:56];

	assign mac_product[0] = F_mul_u8_s8(mac_data_lane[0], F_lane8(weight_data_reg, 3'd0));
	assign mac_product[1] = F_mul_u8_s8(mac_data_lane[1], F_lane8(weight_data_reg, 3'd1));
	assign mac_product[2] = F_mul_u8_s8(mac_data_lane[2], F_lane8(weight_data_reg, 3'd2));
	assign mac_product[3] = F_mul_u8_s8(mac_data_lane[3], F_lane8(weight_data_reg, 3'd3));
	assign mac_product[4] = F_mul_u8_s8(mac_data_lane[4], F_lane8(weight_data_reg, 3'd4));
	assign mac_product[5] = F_mul_u8_s8(mac_data_lane[5], F_lane8(weight_data_reg, 3'd5));
	assign mac_product[6] = F_mul_u8_s8(mac_data_lane[6], F_lane8(weight_data_reg, 3'd6));
	assign mac_product[7] = F_mul_u8_s8(mac_data_lane[7], F_lane8(weight_data_reg, 3'd7));
	wire signed [16:0] mac_sum_01 = {mac_product[0][15], mac_product[0]} +
									 {mac_product[1][15], mac_product[1]};
	wire signed [16:0] mac_sum_23 = {mac_product[2][15], mac_product[2]} +
									 {mac_product[3][15], mac_product[3]};
	wire signed [16:0] mac_sum_45 = {mac_product[4][15], mac_product[4]} +
									 {mac_product[5][15], mac_product[5]};
	wire signed [16:0] mac_sum_67 = {mac_product[6][15], mac_product[6]} +
									 {mac_product[7][15], mac_product[7]};
	wire signed [17:0] mac_sum_03 = {mac_sum_01[16], mac_sum_01} +
									 {mac_sum_23[16], mac_sum_23};
	wire signed [17:0] mac_sum_47 = {mac_sum_45[16], mac_sum_45} +
									 {mac_sum_67[16], mac_sum_67};
	assign mac_sum = {mac_sum_03[17], mac_sum_03} +
					 {mac_sum_47[17], mac_sum_47};

	wire [7:0] conv1_q0 = F_relu_quant(conv_accum[0], `CONV1_SHIFT);
	wire [7:0] conv1_q1 = F_relu_quant(conv_accum[1], `CONV1_SHIFT);
	wire [7:0] conv1_q2 = F_relu_quant(conv_accum[2], `CONV1_SHIFT);
	wire [7:0] conv1_q3 = F_relu_quant(conv_accum[3], `CONV1_SHIFT);
	wire [7:0] conv1_q4 = F_relu_quant(conv_accum[4], `CONV1_SHIFT);
	wire [7:0] conv1_q5 = F_relu_quant(conv_accum[5], `CONV1_SHIFT);
	wire [7:0] conv1_q6 = F_relu_quant(conv_accum[6], `CONV1_SHIFT);
	wire [7:0] conv1_q7 = F_relu_quant(conv_accum[7], `CONV1_SHIFT);

	wire conv_last_pool_point  = (conv_x[0] == 1'b1) && (conv_y[0] == 1'b1);
	wire [63:0] conv1_q_word = {conv1_q7, conv1_q6, conv1_q5, conv1_q4,
								conv1_q3, conv1_q2, conv1_q1, conv1_q0};
	// 量化结果先寄存，下一拍再完成垂直和水平最大值比较。
	// 这样Conv1累加器不再直接驱动池化比较器，缩短关键数据路径。
	wire [7:0] conv1_vertical_pipe_q0 = (conv_y == 0 || conv1_q_word_reg[7:0] > conv1_prev_word_reg[7:0]) ?
										conv1_q_word_reg[7:0] : conv1_prev_word_reg[7:0];
	wire [7:0] conv1_vertical_pipe_q1 = (conv_y == 0 || conv1_q_word_reg[15:8] > conv1_prev_word_reg[15:8]) ?
										conv1_q_word_reg[15:8] : conv1_prev_word_reg[15:8];
	wire [7:0] conv1_vertical_pipe_q2 = (conv_y == 0 || conv1_q_word_reg[23:16] > conv1_prev_word_reg[23:16]) ?
										conv1_q_word_reg[23:16] : conv1_prev_word_reg[23:16];
	wire [7:0] conv1_vertical_pipe_q3 = (conv_y == 0 || conv1_q_word_reg[31:24] > conv1_prev_word_reg[31:24]) ?
										conv1_q_word_reg[31:24] : conv1_prev_word_reg[31:24];
	wire [7:0] conv1_vertical_pipe_q4 = (conv_y == 0 || conv1_q_word_reg[39:32] > conv1_prev_word_reg[39:32]) ?
										conv1_q_word_reg[39:32] : conv1_prev_word_reg[39:32];
	wire [7:0] conv1_vertical_pipe_q5 = (conv_y == 0 || conv1_q_word_reg[47:40] > conv1_prev_word_reg[47:40]) ?
										conv1_q_word_reg[47:40] : conv1_prev_word_reg[47:40];
	wire [7:0] conv1_vertical_pipe_q6 = (conv_y == 0 || conv1_q_word_reg[55:48] > conv1_prev_word_reg[55:48]) ?
										conv1_q_word_reg[55:48] : conv1_prev_word_reg[55:48];
	wire [7:0] conv1_vertical_pipe_q7 = (conv_y == 0 || conv1_q_word_reg[63:56] > conv1_prev_word_reg[63:56]) ?
										conv1_q_word_reg[63:56] : conv1_prev_word_reg[63:56];
	wire [7:0] conv1_pool_pipe_q0 = conv_x[0] ?
									((conv1_vertical_pipe_q0 > pool_max_lane[0]) ? conv1_vertical_pipe_q0 : pool_max_lane[0]) :
									conv1_vertical_pipe_q0;
	wire [7:0] conv1_pool_pipe_q1 = conv_x[0] ?
									((conv1_vertical_pipe_q1 > pool_max_lane[1]) ? conv1_vertical_pipe_q1 : pool_max_lane[1]) :
									conv1_vertical_pipe_q1;
	wire [7:0] conv1_pool_pipe_q2 = conv_x[0] ?
									((conv1_vertical_pipe_q2 > pool_max_lane[2]) ? conv1_vertical_pipe_q2 : pool_max_lane[2]) :
									conv1_vertical_pipe_q2;
	wire [7:0] conv1_pool_pipe_q3 = conv_x[0] ?
									((conv1_vertical_pipe_q3 > pool_max_lane[3]) ? conv1_vertical_pipe_q3 : pool_max_lane[3]) :
									conv1_vertical_pipe_q3;
	wire [7:0] conv1_pool_pipe_q4 = conv_x[0] ?
									((conv1_vertical_pipe_q4 > pool_max_lane[4]) ? conv1_vertical_pipe_q4 : pool_max_lane[4]) :
									conv1_vertical_pipe_q4;
	wire [7:0] conv1_pool_pipe_q5 = conv_x[0] ?
									((conv1_vertical_pipe_q5 > pool_max_lane[5]) ? conv1_vertical_pipe_q5 : pool_max_lane[5]) :
									conv1_vertical_pipe_q5;
	wire [7:0] conv1_pool_pipe_q6 = conv_x[0] ?
									((conv1_vertical_pipe_q6 > pool_max_lane[6]) ? conv1_vertical_pipe_q6 : pool_max_lane[6]) :
									conv1_vertical_pipe_q6;
	wire [7:0] conv1_pool_pipe_q7 = conv_x[0] ?
									((conv1_vertical_pipe_q7 > pool_max_lane[7]) ? conv1_vertical_pipe_q7 : pool_max_lane[7]) :
									conv1_vertical_pipe_q7;
	wire [63:0] conv1_pool_pipe_word = {conv1_pool_pipe_q7, conv1_pool_pipe_q6,
										 conv1_pool_pipe_q5, conv1_pool_pipe_q4,
										 conv1_pool_pipe_q3, conv1_pool_pipe_q2,
										 conv1_pool_pipe_q1, conv1_pool_pipe_q0};

	wire [7:0] conv_q = F_relu_quant(
		conv_accum[0],
		(layer_sel == LAYER_CONV2) ? `CONV2_SHIFT : `CONV3_SHIFT);
	// Conv2/Conv3量化结果先寄存，下一拍再完成垂直和水平最大值比较。
	// 该级切断累加器到池化比较器的直接组合路径。
	wire [7:0] conv_vertical_pipe_q = (conv_y == 0 || conv_q_reg > conv_prev_q_reg) ?
									  conv_q_reg : conv_prev_q_reg;
	wire [7:0] conv_pool_pipe_q = conv_x[0] ?
								   ((conv_vertical_pipe_q > pool_max) ? conv_vertical_pipe_q : pool_max) :
								   conv_vertical_pipe_q;

	// Main sequential process.
	always @(posedge aclk or negedge aresetn) begin
		if (!aresetn) begin
			state            <= ST_IDLE;
			layer_sel        <= LAYER_CONV1;
			conv_x           <= 6'd0;
			conv_y           <= 6'd0;
			out_channel      <= 6'd0;
			kernel_index     <= 4'd0;
			input_group      <= 1'b0;
			input_rd_bank    <= 1'b0;
			input_rd_addr    <= 12'd0;
			busy             <= 1'b0;
			done             <= 1'b0;
			result_valid     <= 1'b0;
			result_class     <= 5'd0;
			result_ascii     <= "A";
			pool_max         <= 8'd0;
			pool_write_addr  <= 10'd0;
			pool_write_lane  <= 3'd0;
			pool_write_value <= 8'd0;
			weight_addr_reg  <= 15'd0;
			weight_data_reg  <= 64'd0;
			conv1_sample_reg <= 8'd0;
			conv_feature_word_reg <= 64'd0;
			fc_feature_word_reg <= 64'd0;
			conv1_pool_word_reg <= 64'd0;
			conv1_q_word_reg <= 64'd0;
			conv1_prev_word_reg <= 64'd0;
			conv_q_reg <= 8'd0;
			conv_prev_q_reg <= 8'd0;
			mac_sum_reg      <= 19'sd0;
			mac_mode_reg     <= MAC_MODE_IDLE;
			for (i = 0; i < 8; i = i + 1)
				mac_product_reg[i] <= 16'sd0;
			fc_out_index     <= 7'd0;
			fc_word_index    <= 9'd0;
			fc_accum         <= 26'sd0;
			fc_bias_reg      <= 26'sd0;
			best_logit       <= 26'sd0;
			best_valid       <= 1'b0;
			fc_write_index   <= 3'd0;
			bias_load_base   <= 8'd0;
			bias_load_index  <= 7'd0;
			bias_load_limit  <= 7'd0;

			feat_a_wr_en     <= 1'b0;
			feat_a_wr_addr   <= 10'd0;
			feat_a_wr_data   <= 64'd0;
			feat_a_rd_addr   <= 10'd0;
			feat_b_wr_en     <= 1'b0;
			feat_b_wr_addr   <= 10'd0;
			feat_b_wr_data   <= 64'd0;
			feat_b_rd_addr   <= 10'd0;

			for (i = 0; i < 8; i = i + 1) begin
				conv_accum[i]       <= 23'sd0;
				pool_max_lane[i]    <= 8'd0;
				fc1_output_words[i] <= 64'd0;
			end
			for (i = 0; i < 32; i = i + 1)
				conv_prev_row[i] <= 8'd0;
			for (i = 0; i < 64; i = i + 1)
				bias_values[i] <= 32'd0;
		end
		else begin
			// 固定速率链路中写使能和done均为单拍脉冲。
			feat_a_wr_en <= 1'b0;
			feat_b_wr_en <= 1'b0;
			done         <= 1'b0;

			// 权重地址在请求状态锁存；等待读数据稳定后再锁存八个权重。
			if ((state == ST_CONV1_CAPTURE) || (state == ST_CONV_CAPTURE) ||
				(state == ST_FC1_CAPTURE) || (state == ST_FC2_CAPTURE))
				weight_data_reg <= weight_rom_data;

			if (state == ST_CONV1_PREP) begin
				for (i = 0; i < 8; i = i + 1)
					mac_product_reg[i] <= mac_product[i][15:0];
			end
			else if ((state == ST_CONV_PREP) || (state == ST_FC1_PREP) ||
					 (state == ST_FC2_PREP)) begin
				mac_sum_reg <= mac_sum;
			end

			case (state)
				ST_IDLE: begin
					busy <= 1'b0;
					if (start && input_frame_ready) begin
						busy           <= 1'b1;
						result_valid   <= 1'b0;
						input_rd_bank  <= input_bank_select;
						bias_load_base <= BIAS_CONV1_BASE;
						bias_load_index <= 7'd0;
						bias_load_limit <= 7'd8;
						state <= ST_LOAD_BIAS_REQ;
					end
				end

				// 偏置RAM先按当前地址完成一次同步读。
				ST_LOAD_BIAS_REQ: begin
					state <= ST_LOAD_BIAS;
				end

				// 每个偏置在读请求后的下一拍被捕获，之后再推进地址。
				ST_LOAD_BIAS: begin
					bias_values[bias_load_index] <= bias_rom_data;
					if (bias_load_index == (bias_load_limit - 1'b1)) begin
						bias_load_index <= 7'd0;
						if (bias_load_base == BIAS_CONV1_BASE) begin
							layer_sel   <= LAYER_CONV1;
							conv_x      <= 6'd0;
							conv_y      <= 6'd0;
							out_channel <= 6'd0;
							state       <= ST_CONV1_INIT;
						end
						else if (bias_load_base == BIAS_CONV2_BASE) begin
							layer_sel   <= LAYER_CONV2;
							conv_x      <= 6'd0;
							conv_y      <= 6'd0;
							out_channel <= 6'd0;
							state       <= ST_CONV_INIT;
						end
						else if (bias_load_base == BIAS_CONV3_BASE) begin
							layer_sel   <= LAYER_CONV3;
							conv_x      <= 6'd0;
							conv_y      <= 6'd0;
							out_channel <= 6'd0;
							state       <= ST_CONV_INIT;
						end
						else if (bias_load_base == BIAS_FC1_BASE) begin
							fc_out_index  <= 7'd0;
							fc_word_index <= 9'd0;
							fc_bias_reg   <= $signed(bias_values[0][25:0]);
							for (i = 0; i < 8; i = i + 1)
								fc1_output_words[i] <= 64'd0;
							state <= ST_FC1_INIT;
						end
						else begin
							fc_out_index  <= 7'd0;
							fc_word_index <= 9'd0;
							fc_bias_reg   <= $signed(bias_values[0][25:0]);
							best_logit     <= 26'sd0;
							best_valid     <= 1'b0;
							state <= ST_FC2_INIT;
						end
					end
					else begin
						bias_load_index <= bias_load_index + 1'b1;
						state <= ST_LOAD_BIAS_REQ;
					end
				end

				// Conv1一次计算8个输出通道，输入为一个8位灰度值。
				ST_CONV1_INIT: begin
					kernel_index <= 4'd0;
					for (i = 0; i < 8; i = i + 1)
						conv_accum[i] <= $signed(bias_values[i][22:0]);
					state <= ST_CONV1_REQ;
				end

				ST_CONV1_REQ: begin
					if (conv1_sample_in_bounds)
						input_rd_addr <= F_input_addr(sample_y[5:0], sample_x[5:0]);
					// Conv1阶段暂时使用特征图B的前64个地址保存上一行结果。
					// 进入Conv2前会覆盖这些地址，因此无需增加额外RAM。
					feat_b_rd_addr <= {4'd0, conv_x};
					weight_addr_reg <= 15'd0 + {11'd0, kernel_index};
					state <= ST_CONV1_WAIT;
				end

				// 输入RAM为同步读，等待请求地址返回数据。
				ST_CONV1_WAIT: begin
					state <= ST_CONV1_CAPTURE;
				end

				ST_CONV1_CAPTURE: begin
					conv1_sample_reg <= conv1_sample;
					conv1_prev_word_reg <= feat_b_rd_data;
					mac_mode_reg <= MAC_MODE_CONV1;
					state <= ST_CONV1_PREP;
				end

				ST_CONV1_PREP: begin
					state <= ST_CONV1_MAC;
				end

				ST_CONV1_MAC: begin
					for (i = 0; i < 8; i = i + 1)
						conv_accum[i] <= conv_accum[i] +
										 $signed({{7{mac_product_reg[i][15]}}, mac_product_reg[i]});
					if (kernel_index == 4'd8)
						state <= ST_CONV1_FINISH;
					else begin
						kernel_index <= kernel_index + 1'b1;
						state <= ST_CONV1_REQ;
					end
				end

				ST_CONV1_FINISH: begin
					conv1_q_word_reg <= conv1_q_word;
					state <= ST_CONV1_POOL;
				end

				// 使用已寄存的量化结果完成2x2池化，并更新上一行缓存。
				ST_CONV1_POOL: begin
					// 写入特征图B的临时区域，减少4096位分布式寄存器。
					feat_b_wr_en   <= 1'b1;
					feat_b_wr_addr <= {4'd0, conv_x};
					feat_b_wr_data <= conv1_q_word_reg;
					pool_max_lane[0] <= conv1_pool_pipe_q0;
					pool_max_lane[1] <= conv1_pool_pipe_q1;
					pool_max_lane[2] <= conv1_pool_pipe_q2;
					pool_max_lane[3] <= conv1_pool_pipe_q3;
					pool_max_lane[4] <= conv1_pool_pipe_q4;
					pool_max_lane[5] <= conv1_pool_pipe_q5;
					pool_max_lane[6] <= conv1_pool_pipe_q6;
					pool_max_lane[7] <= conv1_pool_pipe_q7;

					if (conv_last_pool_point) begin
						conv1_pool_word_reg <= conv1_pool_pipe_word;
						state <= ST_CONV1_WRITE;
					end
					else if ((conv_x == 6'd63) && (conv_y == 6'd63)) begin
						bias_load_base  <= BIAS_CONV2_BASE;
						bias_load_index <= 7'd0;
						bias_load_limit  <= 7'd16;
						state <= ST_LOAD_BIAS_REQ;
					end
					else if (conv_x == 6'd63) begin
						conv_x <= 6'd0;
						conv_y <= conv_y + 1'b1;
						state <= ST_CONV1_INIT;
					end
					else begin
						conv_x <= conv_x + 1'b1;
						state <= ST_CONV1_INIT;
					end
				end

				// 池化字先寄存，再在下一拍写入特征图RAM，隔离量化和比较路径。
				ST_CONV1_WRITE: begin
					feat_a_wr_en   <= 1'b1;
					feat_a_wr_addr <= F_conv1_pool_addr(conv_y[5:1], conv_x[5:1]);
					feat_a_wr_data <= conv1_pool_word_reg;

					if ((conv_x == 6'd63) && (conv_y == 6'd63)) begin
						bias_load_base  <= BIAS_CONV2_BASE;
						bias_load_index <= 7'd0;
						bias_load_limit  <= 7'd16;
						state <= ST_LOAD_BIAS_REQ;
					end
					else if (conv_x == 6'd63) begin
						conv_x <= 6'd0;
						conv_y <= conv_y + 1'b1;
						state <= ST_CONV1_INIT;
					end
					else begin
						conv_x <= conv_x + 1'b1;
						state <= ST_CONV1_INIT;
					end
				end

				// Conv2/Conv3每次处理一个输出通道，MAC每拍处理八个输入通道。
				ST_CONV_INIT: begin
					kernel_index <= 4'd0;
					input_group  <= 1'b0;
					conv_accum[0] <= $signed(bias_values[out_channel][22:0]);
					state <= ST_CONV_REQ;
				end

				ST_CONV_REQ: begin
					if (conv_sample_in_bounds) begin
						if (layer_sel == LAYER_CONV2)
							feat_a_rd_addr <= F_conv2_input_addr(sample_y[4:0], sample_x[4:0]);
						else
							feat_b_rd_addr <= F_conv3_input_addr(sample_y[3:0], sample_x[3:0],
																  input_group);
					end
					if (layer_sel == LAYER_CONV2)
						weight_addr_reg <= 15'd9 + {6'd0, out_channel, 3'b000} +
										   {9'd0, out_channel} +
										   {9'd0, kernel_index};
					else
						weight_addr_reg <= 15'd153 + {5'd0, out_channel, 4'b0000} +
										   {8'd0, out_channel, 1'b0} +
										   {11'd0, input_group, 3'b000} +
										   {14'd0, input_group} +
										   {11'd0, kernel_index};
					state <= ST_CONV_WAIT;
				end

				// 特征图RAM为同步读，等待请求地址返回数据。
				ST_CONV_WAIT: begin
					state <= ST_CONV_CAPTURE;
				end

				ST_CONV_CAPTURE: begin
					conv_feature_word_reg <= conv_feature_sample;
					mac_mode_reg <= MAC_MODE_CONV;
					state <= ST_CONV_PREP;
				end

				ST_CONV_PREP: begin
					state <= ST_CONV_MAC;
				end

				ST_CONV_MAC: begin
					conv_accum[0] <= conv_accum[0] +
									 $signed({{4{mac_sum_reg[18]}}, mac_sum_reg});
					if (layer_sel == LAYER_CONV2) begin
						if (kernel_index == 4'd8)
							state <= ST_CONV_FINISH;
						else begin
							kernel_index <= kernel_index + 1'b1;
							state <= ST_CONV_REQ;
						end
					end
					else if (input_group == 1'b0) begin
						input_group <= 1'b1;
						state <= ST_CONV_REQ;
					end
					else if (kernel_index == 4'd8) begin
						input_group <= 1'b0;
						state <= ST_CONV_FINISH;
					end
					else begin
						input_group <= 1'b0;
						kernel_index <= kernel_index + 1'b1;
						state <= ST_CONV_REQ;
					end
				end

				ST_CONV_FINISH: begin
					conv_q_reg      <= conv_q;
					conv_prev_q_reg <= conv_prev_row[conv_x];
					state <= ST_CONV_POOL;
				end

				// 使用寄存后的量化结果完成Conv2/Conv3的2x2池化。
				ST_CONV_POOL: begin
					conv_prev_row[conv_x] <= conv_q_reg;
					pool_max <= conv_pool_pipe_q;
					if (conv_last_pool_point) begin
						pool_write_value <= conv_pool_pipe_q;
						pool_write_lane  <= out_channel[2:0];
						pool_write_addr  <= (layer_sel == LAYER_CONV2) ?
											F_conv2_pool_addr(conv_y[5:1], conv_x[5:1],
															  out_channel[5:3]) :
											F_conv3_pool_addr(conv_y[5:1], conv_x[5:1],
															  out_channel[5:3]);

						// 第0通道直接写新字，其余通道通过读-改-写补入对应lane。
						if (out_channel == 6'd0) begin
							if (layer_sel == LAYER_CONV2) begin
								feat_b_wr_en   <= 1'b1;
								feat_b_wr_addr <= F_conv2_pool_addr(conv_y[5:1], conv_x[5:1],
																	  out_channel[5:3]);
								feat_b_wr_data <= F_replace_lane(64'd0, 3'd0, conv_pool_pipe_q);
							end
							else begin
								feat_a_wr_en   <= 1'b1;
								feat_a_wr_addr <= F_conv3_pool_addr(conv_y[5:1], conv_x[5:1],
																	  out_channel[5:3]);
								feat_a_wr_data <= F_replace_lane(64'd0, 3'd0, conv_pool_pipe_q);
							end

							// 直接写入后推进下一个卷积点。需要读-改-写的情况在下面处理。
							if ((layer_sel == LAYER_CONV2 && conv_x == 6'd31 && conv_y == 6'd31) ||
								(layer_sel == LAYER_CONV3 && conv_x == 6'd15 && conv_y == 6'd15)) begin
								out_channel <= out_channel + 1'b1;
								conv_x <= 6'd0;
								conv_y <= 6'd0;
								state <= ST_CONV_INIT;
							end
							else if ((layer_sel == LAYER_CONV2 && conv_x == 6'd31) ||
									 (layer_sel == LAYER_CONV3 && conv_x == 6'd15)) begin
								conv_x <= 6'd0;
								conv_y <= conv_y + 1'b1;
								state <= ST_CONV_INIT;
							end
							else begin
								conv_x <= conv_x + 1'b1;
								state <= ST_CONV_INIT;
							end
						end
						else begin
							if (layer_sel == LAYER_CONV2)
								feat_b_rd_addr <= F_conv2_pool_addr(conv_y[5:1], conv_x[5:1],
																	  out_channel[5:3]);
							else
								feat_a_rd_addr <= F_conv3_pool_addr(conv_y[5:1], conv_x[5:1],
																	  out_channel[5:3]);
							// 特征图RAM为同步读，先等待读数据返回，再进入读-改-写。
							state <= ST_POOL_RMW_WAIT;
						end
					end
					else begin
						if ((layer_sel == LAYER_CONV2 && conv_x == 6'd31 && conv_y == 6'd31) ||
							(layer_sel == LAYER_CONV3 && conv_x == 6'd15 && conv_y == 6'd15)) begin
							if (out_channel == ((layer_sel == LAYER_CONV2) ? 6'd15 : 6'd31)) begin
								if (layer_sel == LAYER_CONV2) begin
									bias_load_base  <= BIAS_CONV3_BASE;
									bias_load_limit <= 7'd32;
								end
								else begin
									bias_load_base  <= BIAS_FC1_BASE;
									bias_load_limit <= 7'd64;
								end
								bias_load_index <= 7'd0;
								state <= ST_LOAD_BIAS_REQ;
							end
							else begin
								out_channel <= out_channel + 1'b1;
								conv_x <= 6'd0;
								conv_y <= 6'd0;
								state <= ST_CONV_INIT;
							end
						end
						else if ((layer_sel == LAYER_CONV2 && conv_x == 6'd31) ||
								 (layer_sel == LAYER_CONV3 && conv_x == 6'd15)) begin
							conv_x <= 6'd0;
							conv_y <= conv_y + 1'b1;
							state <= ST_CONV_INIT;
						end
						else begin
							conv_x <= conv_x + 1'b1;
							state <= ST_CONV_INIT;
						end
					end
				end

				// 等待当前池化输出字从同步RAM返回。
				ST_POOL_RMW_WAIT: begin
					state <= ST_POOL_RMW_CAP;
				end

				// 读取当前池化输出字，替换其中一个通道后写回。
				ST_POOL_RMW_CAP: begin
					if (layer_sel == LAYER_CONV2) begin
						feat_b_wr_en   <= 1'b1;
						feat_b_wr_addr <= pool_write_addr;
						feat_b_wr_data <= F_replace_lane(feat_b_rd_data,
														 pool_write_lane,
														 pool_write_value);
					end
					else begin
						feat_a_wr_en   <= 1'b1;
						feat_a_wr_addr <= pool_write_addr;
						feat_a_wr_data <= F_replace_lane(feat_a_rd_data,
														 pool_write_lane,
														 pool_write_value);
					end

					if ((layer_sel == LAYER_CONV2 && conv_x == 6'd31 && conv_y == 6'd31) ||
						(layer_sel == LAYER_CONV3 && conv_x == 6'd15 && conv_y == 6'd15)) begin
						if (out_channel == ((layer_sel == LAYER_CONV2) ? 6'd15 : 6'd31)) begin
							if (layer_sel == LAYER_CONV2) begin
								bias_load_base  <= BIAS_CONV3_BASE;
								bias_load_limit <= 7'd32;
							end
							else begin
								bias_load_base  <= BIAS_FC1_BASE;
								bias_load_limit <= 7'd64;
							end
							bias_load_index <= 7'd0;
							state <= ST_LOAD_BIAS_REQ;
						end
						else begin
							out_channel <= out_channel + 1'b1;
							conv_x <= 6'd0;
							conv_y <= 6'd0;
							state <= ST_CONV_INIT;
						end
					end
					else if ((layer_sel == LAYER_CONV2 && conv_x == 6'd31) ||
							 (layer_sel == LAYER_CONV3 && conv_x == 6'd15)) begin
						conv_x <= 6'd0;
						conv_y <= conv_y + 1'b1;
						state <= ST_CONV_INIT;
					end
					else begin
						conv_x <= conv_x + 1'b1;
						state <= ST_CONV_INIT;
					end
				end

				ST_FC1_INIT: begin
					fc_word_index <= 9'd0;
					fc_accum <= fc_bias_reg;
					state <= ST_FC1_REQ;
				end

				ST_FC1_REQ: begin
					feat_a_rd_addr <= {1'b0, fc_word_index};
					weight_addr_reg <= 15'd729 + {fc_out_index, 8'd0} +
									   {6'd0, fc_word_index};
					state <= ST_FC1_WAIT;
				end

				ST_FC1_WAIT: begin
					state <= ST_FC1_CAPTURE;
				end

				ST_FC1_CAPTURE: begin
					fc_feature_word_reg <= feat_a_rd_data;
					mac_mode_reg <= MAC_MODE_FC;
					state <= ST_FC1_PREP;
				end

				ST_FC1_PREP: begin
					state <= ST_FC1_MAC;
				end

				ST_FC1_MAC: begin
					fc_accum <= fc_accum +
									$signed({{7{mac_sum_reg[18]}}, mac_sum_reg});
					if (fc_word_index == 9'd255)
						state <= ST_FC1_FINISH;
					else begin
						fc_word_index <= fc_word_index + 1'b1;
						state <= ST_FC1_REQ;
					end
				end

				ST_FC1_FINISH: begin
					fc1_output_words[fc_out_index[5:3]] <=
						F_replace_lane(fc1_output_words[fc_out_index[5:3]],
									   fc_out_index[2:0],
									   F_relu_quant(fc_accum, `FC1_SHIFT));
					if (fc_out_index == 7'd63) begin
						fc_write_index <= 3'd0;
						state <= ST_FC1_WRITE;
					end
					else begin
						fc_out_index <= fc_out_index + 1'b1;
						fc_bias_reg  <= $signed(bias_values[fc_out_index + 7'd1][25:0]);
						state <= ST_FC1_INIT;
					end
				end

				ST_FC1_WRITE: begin
					feat_b_wr_en   <= 1'b1;
					feat_b_wr_addr <= fc_write_index;
					feat_b_wr_data <= fc1_output_words[fc_write_index];
					if (fc_write_index == 3'd7) begin
						bias_load_base  <= BIAS_FC2_BASE;
						bias_load_index <= 7'd0;
						bias_load_limit <= 7'd26;
						state <= ST_LOAD_BIAS_REQ;
					end
					else begin
						fc_write_index <= fc_write_index + 1'b1;
					end
				end

				ST_FC2_INIT: begin
					fc_word_index <= 9'd0;
					fc_accum <= fc_bias_reg;
					state <= ST_FC2_REQ;
				end

				ST_FC2_REQ: begin
					feat_b_rd_addr <= {1'b0, fc_word_index};
					weight_addr_reg <= 15'd17113 + {5'd0, fc_out_index, 3'b000} +
									   {6'd0, fc_word_index};
					state <= ST_FC2_WAIT;
				end

				ST_FC2_WAIT: begin
					state <= ST_FC2_CAPTURE;
				end

				ST_FC2_CAPTURE: begin
					fc_feature_word_reg <= feat_b_rd_data;
					mac_mode_reg <= MAC_MODE_FC;
					state <= ST_FC2_PREP;
				end

				ST_FC2_PREP: begin
					state <= ST_FC2_MAC;
				end

				ST_FC2_MAC: begin
					fc_accum <= fc_accum +
									$signed({{7{mac_sum_reg[18]}}, mac_sum_reg});
					if (fc_word_index == 9'd7)
						state <= ST_FC2_FINISH;
					else begin
						fc_word_index <= fc_word_index + 1'b1;
						state <= ST_FC2_REQ;
					end
				end

				ST_FC2_FINISH: begin
					if (!best_valid || (fc_accum > best_logit)) begin
						best_logit   <= fc_accum;
						best_valid   <= 1'b1;
						result_class <= fc_out_index[4:0];
						result_ascii <= 8'd65 + fc_out_index[4:0];
					end

					if (fc_out_index == 7'd25) begin
						busy         <= 1'b0;
						done         <= 1'b1;
						result_valid <= 1'b1;
						if (!best_valid || (fc_accum > best_logit)) begin
							result_class <= fc_out_index[4:0];
							result_ascii <= 8'd65 + fc_out_index[4:0];
						end
						state <= ST_IDLE;
					end
					else begin
						fc_out_index <= fc_out_index + 1'b1;
						fc_bias_reg  <= $signed(bias_values[fc_out_index + 7'd1][25:0]);
						state <= ST_FC2_INIT;
					end
				end

				default: state <= ST_IDLE;
			endcase
		end
	end

endmodule
