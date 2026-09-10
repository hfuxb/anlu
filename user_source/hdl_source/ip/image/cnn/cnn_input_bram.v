`timescale 1ns / 1ps

// 64x64灰度输入缓存。
// 目标器件使用安路PH1P_LOGIC_ERAM；CNN_SIM使用等价的行为模型。
module cnn_input_bram #(
    parameter INIT_FILE = "NONE"
) (
    input  wire        clka,
    input  wire        wea,
    input  wire [11:0] addra,
    input  wire [7:0]  dina,
    input  wire        clkb,
    input  wire [11:0] addrb,
    output wire [7:0]  doutb
);

`ifdef CNN_SIM
    reg [7:0] mem [0:4095];
    reg [7:0] doutb_reg;
    integer i;

    initial begin
        for (i = 0; i < 4096; i = i + 1)
            mem[i] = 8'd0;
        if (INIT_FILE != "NONE")
            $readmemh(INIT_FILE, mem);
    end

    always @(posedge clka) begin
        if (wea)
            mem[addra] <= dina;
    end

    always @(posedge clkb)
        doutb_reg <= mem[addrb];

    assign doutb = doutb_reg;
`else
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(8),
        .DATA_WIDTH_B(8),
        .ADDR_WIDTH_A(12),
        .ADDR_WIDTH_B(12),
        .DATA_DEPTH_A(4096),
        .DATA_DEPTH_B(4096),
        .MODE("DP"),
        .REGMODE_A("NOREG"),
        .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),
        .WRITEMODE_B("READBEFOREWRITE"),
        .IMPLEMENT("20K(FAST)"),
        .ECC_ENCODE("DISABLE"),
        .ECC_DECODE("DISABLE"),
        .CLKMODE("ASYNC"),
        .SSROVERCE("DISABLE"),
        .OREGSET_A("RESET"),
        .OREGSET_B("RESET"),
        .RESETMODE_A("ASYNC"),
        .RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"),
        .ASYNC_RESET_RELEASE_B("ASYNC"),
        .INIT_FILE(INIT_FILE),
        .FILL_ALL("NONE")
    ) u_cnn_input_bram (
        .dia(dina), .dib(8'd0), .addra(addra), .addrb(addrb),
        .cea(1'b1), .ceb(1'b1), .ocea(1'b0), .oceb(1'b0),
        .clka(clka), .clkb(clkb), .wea(wea), .web(1'b0),
        .bea(1'b0), .beb(1'b0), .rsta(1'b0), .rstb(1'b0),
        .doa(), .ecc_sbiterr(), .ecc_dbiterr(),
        .ecc_sbiterrinj('b0), .ecc_dbiterrinj('b0), .dob(doutb)
    );
`endif

endmodule
