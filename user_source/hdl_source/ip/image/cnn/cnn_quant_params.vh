`ifndef CNN_QUANT_PARAMS_VH
`define CNN_QUANT_PARAMS_VH

// 离线量化得到的右移位数。
// 使用宏而不是文件级localparam，兼容TD对Verilog-2001源文件的解析方式。
`define CONV1_SHIFT 5'd11
`define CONV2_SHIFT 5'd10
`define CONV3_SHIFT 5'd11
`define FC1_SHIFT   5'd13

`endif
