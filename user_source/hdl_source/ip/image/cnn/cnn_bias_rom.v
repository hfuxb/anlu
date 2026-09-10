`timescale 1ns / 1ps

// 网络偏置ROM，共146个有符号32位字。
module cnn_bias_rom #(
`ifdef CNN_SIM
    parameter INIT_FILE = "../user_source/ip_source/cnn/cnn_bias.mem",
`else
    parameter INIT_FILE = "../../../../ip_source/cnn/cnn_bias.bin",
`endif
    parameter DEPTH = 146
) (
    input  wire        clk,
    input  wire [7:0] addr,
    output wire [31:0] dout
);

`ifdef CNN_SIM
    reg [31:0] mem [0:DEPTH-1];
    reg [31:0] dout_reg;
    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'd0;
        $readmemh(INIT_FILE, mem);
    end

    always @(*) begin
        if (addr < DEPTH)
            dout_reg = mem[addr];
        else
            dout_reg = 32'd0;
    end

    assign dout = dout_reg;
`else
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(32), .DATA_WIDTH_B(32),
        .ADDR_WIDTH_A(8), .ADDR_WIDTH_B(8),
        .DATA_DEPTH_A(DEPTH), .DATA_DEPTH_B(DEPTH),
        .MODE("SP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .IMPLEMENT("20K(FAST)"), .ECC_ENCODE("DISABLE"),
        .ECC_DECODE("DISABLE"), .CLKMODE("ASYNC"),
        .SSROVERCE("DISABLE"), .OREGSET_A("RESET"), .OREGSET_B("RESET"),
        .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
        .INIT_FILE(INIT_FILE), .FILL_ALL("NONE")
    ) u_cnn_bias_rom (
        .dia(32'd0), .dib(32'd0), .addra(addr), .addrb(8'd0),
        .cea(1'b1), .ceb(1'b0), .ocea(1'b0), .oceb(1'b0),
        .clka(clk), .clkb(1'b0), .wea(1'b0), .web(1'b0),
        .bea(1'b0), .beb(1'b0), .rsta(1'b0), .rstb(1'b0),
        .doa(dout), .ecc_sbiterr(), .ecc_dbiterr(),
        .ecc_sbiterrinj('b0), .ecc_dbiterrinj('b0), .dob()
    );
`endif

endmodule
