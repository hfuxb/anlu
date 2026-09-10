`timescale 1ns / 1ps

// 64位特征图缓存。
// 一个地址保存同一空间位置的八个通道，便于八路MAC并行读取。
module cnn_feat_bram #(
    parameter INIT_FILE = "NONE",
    parameter integer DEPTH = 1024
) (
    input  wire        clka,
    input  wire        wea,
    input  wire [9:0]  addra,
    input  wire [63:0] dina,
    input  wire        clkb,
    input  wire [9:0]  addrb,
    output wire [63:0] doutb
);

    localparam integer ADDR_WIDTH = (DEPTH <= 512) ? 9 : 10;

`ifdef CNN_SIM
    reg [63:0] mem [0:DEPTH-1];
    reg [63:0] doutb_reg;
    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 64'd0;
        if (INIT_FILE != "NONE")
            $readmemh(INIT_FILE, mem);
    end

    always @(posedge clka) begin
        if (wea)
            mem[addra] <= dina;
    end

    always @(posedge clkb)
        doutb_reg <= mem[addrb[ADDR_WIDTH-1:0]];

    assign doutb = doutb_reg;
`else
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(64), .DATA_WIDTH_B(64),
        .ADDR_WIDTH_A(ADDR_WIDTH), .ADDR_WIDTH_B(ADDR_WIDTH),
        .DATA_DEPTH_A(DEPTH), .DATA_DEPTH_B(DEPTH),
        .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("READBEFOREWRITE"),
        .IMPLEMENT("20K(FAST)"), .ECC_ENCODE("DISABLE"),
        .ECC_DECODE("DISABLE"), .CLKMODE("ASYNC"),
        .SSROVERCE("DISABLE"), .OREGSET_A("RESET"), .OREGSET_B("RESET"),
        .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
        .INIT_FILE(INIT_FILE), .FILL_ALL("NONE")
    ) u_cnn_feat_bram (
        .dia(dina), .dib(64'd0),
        .addra(addra[ADDR_WIDTH-1:0]), .addrb(addrb[ADDR_WIDTH-1:0]),
        .cea(1'b1), .ceb(1'b1), .ocea(1'b0), .oceb(1'b0),
        .clka(clka), .clkb(clkb), .wea(wea), .web(1'b0),
        .bea(1'b0), .beb(1'b0), .rsta(1'b0), .rstb(1'b0),
        .doa(), .ecc_sbiterr(), .ecc_dbiterr(),
        .ecc_sbiterrinj('b0), .ecc_dbiterrinj('b0), .dob(doutb)
    );
`endif

endmodule
