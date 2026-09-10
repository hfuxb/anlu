`timescale 1ns / 1ps

// 权重按64位逻辑字分成17个物理RAM bank。
// 每个逻辑字保存八个有符号八位权重，lane0位于最低有效字节。
// 最后一个bank的未使用空间同时保存146个32位偏置值。
`ifdef CNN_SIM
`define CNN_WEIGHT_BANK0_INIT  "../user_source/ip_source/cnn/cnn_weight_bank0.bin"
`define CNN_WEIGHT_BANK1_INIT  "../user_source/ip_source/cnn/cnn_weight_bank1.bin"
`define CNN_WEIGHT_BANK2_INIT  "../user_source/ip_source/cnn/cnn_weight_bank2.bin"
`define CNN_WEIGHT_BANK3_INIT  "../user_source/ip_source/cnn/cnn_weight_bank3.bin"
`define CNN_WEIGHT_BANK4_INIT  "../user_source/ip_source/cnn/cnn_weight_bank4.bin"
`define CNN_WEIGHT_BANK5_INIT  "../user_source/ip_source/cnn/cnn_weight_bank5.bin"
`define CNN_WEIGHT_BANK6_INIT  "../user_source/ip_source/cnn/cnn_weight_bank6.bin"
`define CNN_WEIGHT_BANK7_INIT  "../user_source/ip_source/cnn/cnn_weight_bank7.bin"
`define CNN_WEIGHT_BANK8_INIT  "../user_source/ip_source/cnn/cnn_weight_bank8.bin"
`define CNN_WEIGHT_BANK9_INIT  "../user_source/ip_source/cnn/cnn_weight_bank9.bin"
`define CNN_WEIGHT_BANK10_INIT "../user_source/ip_source/cnn/cnn_weight_bank10.bin"
`define CNN_WEIGHT_BANK11_INIT "../user_source/ip_source/cnn/cnn_weight_bank11.bin"
`define CNN_WEIGHT_BANK12_INIT "../user_source/ip_source/cnn/cnn_weight_bank12.bin"
`define CNN_WEIGHT_BANK13_INIT "../user_source/ip_source/cnn/cnn_weight_bank13.bin"
`define CNN_WEIGHT_BANK14_INIT "../user_source/ip_source/cnn/cnn_weight_bank14.bin"
`define CNN_WEIGHT_BANK15_INIT "../user_source/ip_source/cnn/cnn_weight_bank15.bin"
`define CNN_WEIGHT_BANK16_INIT "../user_source/ip_source/cnn/cnn_weight_bank16.bin"
`else
`define CNN_WEIGHT_BANK0_INIT  "../../../../ip_source/cnn/cnn_weight_bank0.bin"
`define CNN_WEIGHT_BANK1_INIT  "../../../../ip_source/cnn/cnn_weight_bank1.bin"
`define CNN_WEIGHT_BANK2_INIT  "../../../../ip_source/cnn/cnn_weight_bank2.bin"
`define CNN_WEIGHT_BANK3_INIT  "../../../../ip_source/cnn/cnn_weight_bank3.bin"
`define CNN_WEIGHT_BANK4_INIT  "../../../../ip_source/cnn/cnn_weight_bank4.bin"
`define CNN_WEIGHT_BANK5_INIT  "../../../../ip_source/cnn/cnn_weight_bank5.bin"
`define CNN_WEIGHT_BANK6_INIT  "../../../../ip_source/cnn/cnn_weight_bank6.bin"
`define CNN_WEIGHT_BANK7_INIT  "../../../../ip_source/cnn/cnn_weight_bank7.bin"
`define CNN_WEIGHT_BANK8_INIT  "../../../../ip_source/cnn/cnn_weight_bank8.bin"
`define CNN_WEIGHT_BANK9_INIT  "../../../../ip_source/cnn/cnn_weight_bank9.bin"
`define CNN_WEIGHT_BANK10_INIT "../../../../ip_source/cnn/cnn_weight_bank10.bin"
`define CNN_WEIGHT_BANK11_INIT "../../../../ip_source/cnn/cnn_weight_bank11.bin"
`define CNN_WEIGHT_BANK12_INIT "../../../../ip_source/cnn/cnn_weight_bank12.bin"
`define CNN_WEIGHT_BANK13_INIT "../../../../ip_source/cnn/cnn_weight_bank13.bin"
`define CNN_WEIGHT_BANK14_INIT "../../../../ip_source/cnn/cnn_weight_bank14.bin"
`define CNN_WEIGHT_BANK15_INIT "../../../../ip_source/cnn/cnn_weight_bank15.bin"
`define CNN_WEIGHT_BANK16_INIT "../../../../ip_source/cnn/cnn_weight_bank16.bin"
`endif

localparam integer CNN_WEIGHT_WORDS = 17321;
localparam integer CNN_WEIGHT_BANK_DEPTH = 1024;
localparam integer CNN_BIAS_PAIR_BASE = 937;

// 一个64位单口RAM bank。仿真模型使用组合读，和当前安路RAM配置的
// NOREG输出行为一致；综合时直接例化安路逻辑RAM原语。
module cnn_weight_bank #(
    parameter INIT_FILE = "NONE",
    parameter integer DEPTH = CNN_WEIGHT_BANK_DEPTH
) (
    input  wire        clka,
    input  wire        ena,
    input  wire [9:0]  addra,
    output wire [63:0] doa
);

`ifdef CNN_SIM
    reg [63:0] mem [0:DEPTH-1];
    reg [63:0] doa_reg;
    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 64'd0;
        $readmemb(INIT_FILE, mem);
    end

    always @(*) begin
        doa_reg = ena && (addra < DEPTH) ? mem[addra] : 64'd0;
    end

    assign doa = doa_reg;
`else
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(64), .DATA_WIDTH_B(64),
        .ADDR_WIDTH_A(10), .ADDR_WIDTH_B(10),
        .DATA_DEPTH_A(DEPTH), .DATA_DEPTH_B(DEPTH),
        .MODE("SP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .IMPLEMENT("20K(FAST)"), .ECC_ENCODE("DISABLE"),
        .ECC_DECODE("DISABLE"), .CLKMODE("ASYNC"),
        .SSROVERCE("DISABLE"), .OREGSET_A("RESET"), .OREGSET_B("RESET"),
        .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
        .INIT_FILE(INIT_FILE), .FILL_ALL("NONE")
    ) u_cnn_weight_bank (
        .dia(64'd0), .dib(64'd0),
        .addra(addra), .addrb(10'd0),
        .cea(ena), .ceb(1'b0), .ocea(1'b0), .oceb(1'b0),
        .clka(clka), .clkb(1'b0), .wea(1'b0), .web(1'b0),
        .bea(1'b0), .beb(1'b0), .rsta(1'b0), .rstb(1'b0),
        .doa(doa), .dob(), .ecc_sbiterr(), .ecc_dbiterr(),
        .ecc_sbiterrinj('b0), .ecc_dbiterrinj('b0)
    );
`endif

endmodule

// 17321个八位权重的八路并行存储接口。
// addr[14:10]选择bank，addr[9:0]选择bank内的64位逻辑字。
module cnn_weight_rom #(
    parameter DEPTH = CNN_WEIGHT_WORDS
) (
    input  wire        clk,
    input  wire [14:0] addr,
    output wire [63:0] dout,
    input  wire [7:0]  bias_addr,
    input  wire        bias_read,
    output wire [31:0] bias_dout
);

    wire [4:0]  bank_select = addr[14:10];
    wire [9:0]  bank_addr = addr[9:0];
    wire [9:0]  bias_bank_addr = CNN_BIAS_PAIR_BASE + {3'd0, bias_addr[7:1]};
    wire        bank_enable0 = !bias_read && (bank_select == 5'd0);
    wire        bank_enable1 = !bias_read && (bank_select == 5'd1);
    wire        bank_enable2 = !bias_read && (bank_select == 5'd2);
    wire        bank_enable3 = !bias_read && (bank_select == 5'd3);
    wire        bank_enable4 = !bias_read && (bank_select == 5'd4);
    wire        bank_enable5 = !bias_read && (bank_select == 5'd5);
    wire        bank_enable6 = !bias_read && (bank_select == 5'd6);
    wire        bank_enable7 = !bias_read && (bank_select == 5'd7);
    wire        bank_enable8 = !bias_read && (bank_select == 5'd8);
    wire        bank_enable9 = !bias_read && (bank_select == 5'd9);
    wire        bank_enable10 = !bias_read && (bank_select == 5'd10);
    wire        bank_enable11 = !bias_read && (bank_select == 5'd11);
    wire        bank_enable12 = !bias_read && (bank_select == 5'd12);
    wire        bank_enable13 = !bias_read && (bank_select == 5'd13);
    wire        bank_enable14 = !bias_read && (bank_select == 5'd14);
    wire        bank_enable15 = !bias_read && (bank_select == 5'd15);
    wire        bank_enable16 = bias_read || (bank_select == 5'd16);
    wire [63:0] bank_data0;
    wire [63:0] bank_data1;
    wire [63:0] bank_data2;
    wire [63:0] bank_data3;
    wire [63:0] bank_data4;
    wire [63:0] bank_data5;
    wire [63:0] bank_data6;
    wire [63:0] bank_data7;
    wire [63:0] bank_data8;
    wire [63:0] bank_data9;
    wire [63:0] bank_data10;
    wire [63:0] bank_data11;
    wire [63:0] bank_data12;
    wire [63:0] bank_data13;
    wire [63:0] bank_data14;
    wire [63:0] bank_data15;
    wire [63:0] bank_data16;

    cnn_weight_bank #(.INIT_FILE(`CNN_WEIGHT_BANK0_INIT)) u_bank0 (
        .clka(clk), .ena(bank_enable0), .addra(bank_addr), .doa(bank_data0));
    cnn_weight_bank #(.INIT_FILE(`CNN_WEIGHT_BANK1_INIT)) u_bank1 (
        .clka(clk), .ena(bank_enable1), .addra(bank_addr), .doa(bank_data1));
    cnn_weight_bank #(.INIT_FILE(`CNN_WEIGHT_BANK2_INIT)) u_bank2 (
        .clka(clk), .ena(bank_enable2), .addra(bank_addr), .doa(bank_data2));
    cnn_weight_bank #(.INIT_FILE(`CNN_WEIGHT_BANK3_INIT)) u_bank3 (
        .clka(clk), .ena(bank_enable3), .addra(bank_addr), .doa(bank_data3));
    cnn_weight_bank #(.INIT_FILE(`CNN_WEIGHT_BANK4_INIT)) u_bank4 (
        .clka(clk), .ena(bank_enable4), .addra(bank_addr), .doa(bank_data4));
    cnn_weight_bank #(.INIT_FILE(`CNN_WEIGHT_BANK5_INIT)) u_bank5 (
        .clka(clk), .ena(bank_enable5), .addra(bank_addr), .doa(bank_data5));
    cnn_weight_bank #(.INIT_FILE(`CNN_WEIGHT_BANK6_INIT)) u_bank6 (
        .clka(clk), .ena(bank_enable6), .addra(bank_addr), .doa(bank_data6));
    cnn_weight_bank #(.INIT_FILE(`CNN_WEIGHT_BANK7_INIT)) u_bank7 (
        .clka(clk), .ena(bank_enable7), .addra(bank_addr), .doa(bank_data7));
    cnn_weight_bank #(.INIT_FILE(`CNN_WEIGHT_BANK8_INIT)) u_bank8 (
        .clka(clk), .ena(bank_enable8), .addra(bank_addr), .doa(bank_data8));
    cnn_weight_bank #(.INIT_FILE(`CNN_WEIGHT_BANK9_INIT)) u_bank9 (
        .clka(clk), .ena(bank_enable9), .addra(bank_addr), .doa(bank_data9));
    cnn_weight_bank #(.INIT_FILE(`CNN_WEIGHT_BANK10_INIT)) u_bank10 (
        .clka(clk), .ena(bank_enable10), .addra(bank_addr), .doa(bank_data10));
    cnn_weight_bank #(.INIT_FILE(`CNN_WEIGHT_BANK11_INIT)) u_bank11 (
        .clka(clk), .ena(bank_enable11), .addra(bank_addr), .doa(bank_data11));
    cnn_weight_bank #(.INIT_FILE(`CNN_WEIGHT_BANK12_INIT)) u_bank12 (
        .clka(clk), .ena(bank_enable12), .addra(bank_addr), .doa(bank_data12));
    cnn_weight_bank #(.INIT_FILE(`CNN_WEIGHT_BANK13_INIT)) u_bank13 (
        .clka(clk), .ena(bank_enable13), .addra(bank_addr), .doa(bank_data13));
    cnn_weight_bank #(.INIT_FILE(`CNN_WEIGHT_BANK14_INIT)) u_bank14 (
        .clka(clk), .ena(bank_enable14), .addra(bank_addr), .doa(bank_data14));
    cnn_weight_bank #(.INIT_FILE(`CNN_WEIGHT_BANK15_INIT)) u_bank15 (
        .clka(clk), .ena(bank_enable15), .addra(bank_addr), .doa(bank_data15));
    cnn_weight_bank #(.INIT_FILE(`CNN_WEIGHT_BANK16_INIT)) u_bank16 (
        .clka(clk), .ena(bank_enable16), .addra(bias_read ? bias_bank_addr : bank_addr),
        .doa(bank_data16));

    assign dout = (bank_select == 5'd0)  ? bank_data0  :
                  (bank_select == 5'd1)  ? bank_data1  :
                  (bank_select == 5'd2)  ? bank_data2  :
                  (bank_select == 5'd3)  ? bank_data3  :
                  (bank_select == 5'd4)  ? bank_data4  :
                  (bank_select == 5'd5)  ? bank_data5  :
                  (bank_select == 5'd6)  ? bank_data6  :
                  (bank_select == 5'd7)  ? bank_data7  :
                  (bank_select == 5'd8)  ? bank_data8  :
                  (bank_select == 5'd9)  ? bank_data9  :
                  (bank_select == 5'd10) ? bank_data10 :
                  (bank_select == 5'd11) ? bank_data11 :
                  (bank_select == 5'd12) ? bank_data12 :
                  (bank_select == 5'd13) ? bank_data13 :
                  (bank_select == 5'd14) ? bank_data14 :
                  (bank_select == 5'd15) ? bank_data15 :
                  bank_data16;

    assign bias_dout = bias_addr[0] ? bank_data16[63:32] : bank_data16[31:0];

endmodule

`undef CNN_WEIGHT_BANK0_INIT
`undef CNN_WEIGHT_BANK1_INIT
`undef CNN_WEIGHT_BANK2_INIT
`undef CNN_WEIGHT_BANK3_INIT
`undef CNN_WEIGHT_BANK4_INIT
`undef CNN_WEIGHT_BANK5_INIT
`undef CNN_WEIGHT_BANK6_INIT
`undef CNN_WEIGHT_BANK7_INIT
`undef CNN_WEIGHT_BANK8_INIT
`undef CNN_WEIGHT_BANK9_INIT
`undef CNN_WEIGHT_BANK10_INIT
`undef CNN_WEIGHT_BANK11_INIT
`undef CNN_WEIGHT_BANK12_INIT
`undef CNN_WEIGHT_BANK13_INIT
`undef CNN_WEIGHT_BANK14_INIT
`undef CNN_WEIGHT_BANK15_INIT
`undef CNN_WEIGHT_BANK16_INIT
