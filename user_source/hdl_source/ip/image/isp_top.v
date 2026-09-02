module isp_top #(
    parameter [10:0] EDGE_THRESHOLD = 11'd24 // Sobel边缘阈值，帧内保持不变。
) (
    // 全局时钟与复位
    input 			axi4s_video_aclk,
    input 			I_rst_n			,

    // 输入RAW视频流
    input 			I_tlast			,
    input 			I_tuser			,
    input [39:0] 	I_tdata			,
    input 			I_tvalid		,
    input [9:0] 	I_tdest			,

    // 图像处理配置和输出握手
    input [1:0]  	I_algo_mode		,
    input 			O_tready		,

    // 输出RGB视频流
    output [127:0] 	O_tdata			,
    output 			O_tlast			,
    output 			O_tuser			,
    output 			O_tvalid		,
    output 			I_tready
);
 
//********************************************************************//
//****************** Parameter and Internal Signal *******************//
//********************************************************************//
// demosaic输出的128位四像素流及其握手信号。
wire         m_aixs_tvalid;  //synthesis keep 
  wire [127:0] m_aixs_tdata;  //synthesis keep 
  wire         m_aixs_tuser;  //synthesis keep 
  wire         m_aixs_tlast;  //synthesis keep 
  wire         m_aixs_tready;  //synthesis keep 
  
  // 128位输入流拆成96位四个RGB888像素。
  wire [ 95:0] m_aixs_tdata_96;  //synthesis keep 


  // AWB输出流。
  wire         awb_O_tlast;  //synthesis keep 
  wire         awb_O_tuser;  //synthesis keep 
  wire [ 95:0] awb_O_tdata;  //synthesis keep 
  wire         awb_O_tvalid;  //synthesis keep 
  wire         awb_O_tready;  //synthesis keep 

  // 图像算法输出流。
  wire         process_O_tlast;
  wire         process_O_tuser;
  wire [95:0]  process_O_tdata;
  wire         process_O_tvalid;
  // AWB帧首标记可能早于有效数据，pending用于等待首个有效拍。
  wire         process_I_tuser;
  reg          awb_frame_pending;
  // 算法输出行结束标记延迟一拍，对齐96位到128位打包输出。
  reg          process_O_tlast_d;

  // 打包器输出的官方视频流标志和数据。
  wire         awb_O_tuser_128;  //synthesis keep 
  wire         awb_O_tvalid_128;  //synthesis keep 
  wire [127:0] awb_O_tdata_128;  //synthesis keep 

  // 固定速率链路由顶层提供ready，当前工程不暂停视频流。
  assign awb_O_tready = O_tready;
  assign O_tdata  = awb_O_tdata_128;
  assign O_tlast  = process_O_tlast_d & awb_O_tvalid_128;
  assign O_tuser  = awb_O_tuser_128    ;
  assign O_tvalid = awb_O_tvalid_128   ;

  // AWB保留官方提前帧标记，但RGB数据有效可能延后。
  // 将标记保持到第一个有效AWB输出拍，再交给图像处理模块锁存配置。
  assign process_I_tuser = awb_O_tvalid && (awb_O_tuser || awb_frame_pending);

  // 记录没有伴随有效数据的AWB帧标记。
  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
      if(!I_rst_n)
          awb_frame_pending <= 1'b0;
      else if(awb_O_tuser && !awb_O_tvalid)
          awb_frame_pending <= 1'b1;
      else if(awb_O_tvalid)
          awb_frame_pending <= 1'b0;
  end
  
  //assign m_aixs_tready = O_tready;
  //assign O_tdata  = m_aixs_tdata;
  //assign O_tlast  = m_aixs_tlast    ;
  //assign O_tuser  = m_aixs_tuser    ;
  //assign O_tvalid = m_aixs_tvalid   ;
 
 
//********************************************************************//
//***************************** ISP Pipeline *************************//
//********************************************************************//
// RAW10两路MIPI数据经过demosaic后形成四像素RGB流。
demosaic #(
    .IMG_HEIGHT          (600),  // 图像高度
    .IMG_WIDTH           (1024),   // 图像宽度
    .data_complete_delay (50  ),
    .BAYER_MODE          ("BGGR")
)
u_demosaic
(
    .I_clk   			(axi4s_video_aclk)	,   // 时钟信号
    .I_rst_n 			(I_rst_n)	,   // 复位信号，低有效
    .axi4s_video_tdata 	(I_tdata)	,  // AXI4-Stream视频数据
    .axi4s_video_tdest 	(I_tdest)	,
    .axi4s_video_tlast 	(I_tlast)	,  // 行结束信号
    .axi4s_video_tvalid	(I_tvalid)	,  // 数据有效信号
    .axi4s_video_tuser 	(I_tuser)	,  // 帧开始信号
    .axi4s_video_tready	(I_tready)	,  // 从模块准备好接受数据
    .O_tlast  			(m_aixs_tlast)	,  // 输出行结束信号
    .O_tuser  			(m_aixs_tuser)	,  // 输出帧开始信号
    .O_tdata  			(m_aixs_tdata)	,  // 输出数据
    .O_tvalid 			(m_aixs_tvalid)	,  // 输出数据有效信号
    .O_tready   		(m_aixs_tready)	   // 输出数据准备好信号
);
 
// 官方数据格式转换：128位四像素数据转为96位RGB888数据。
data128_96 u_data128_96 (
    .I_tdata(m_aixs_tdata),
    .O_tdata(m_aixs_tdata_96)
);

// 自动白平衡，保持官方AWB输出时序。
awb #(
    .IMG_HEIGHT(600),
    .IMG_WIDTH (1024)
) u_awb (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tlast (m_aixs_tlast),
    .I_tuser (m_aixs_tuser),
    .I_tdata (m_aixs_tdata_96),
    .I_tvalid(m_aixs_tvalid),
    .I_tready(m_aixs_tready),
    .O_tlast (awb_O_tlast ),
    .O_tuser (awb_O_tuser ),
    .O_tdata (awb_O_tdata ),
    .O_tvalid(awb_O_tvalid),
    .O_tready(awb_O_tready)
);

// 本次迁移的实时算法：灰度、Sobel、腐蚀和膨胀。
// 模式在帧首拍锁存，处理模块不使用暂停式反压。
image_process_stream_96 #(
    .IMG_HEIGHT(600),
    .IMG_WIDTH (1024)
) u_image_process_stream_96 (
    .I_clk           (axi4s_video_aclk),
    .I_rst_n         (I_rst_n),
    .I_tuser         (process_I_tuser),
    .I_tlast         (awb_O_tlast),
    .I_tvalid        (awb_O_tvalid),
    .I_tdata         (awb_O_tdata),
    .I_algo_mode     (I_algo_mode),
    .I_edge_threshold(EDGE_THRESHOLD),
    .O_tuser         (process_O_tuser),
    .O_tlast         (process_O_tlast),
    .O_tvalid        (process_O_tvalid),
    .O_tdata         (process_O_tdata)
);

// 算法行结束标记随算法输出寄存，供下游128位流边界对齐。
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if(!I_rst_n)
        process_O_tlast_d <= 1'b0;
    else
        process_O_tlast_d <= process_O_tlast;
end

// 官方数据格式转换：四拍96位数据拼接为三拍128位数据。
// 帧首标记按官方协议提前输出，行结束由算法标记延迟对齐。
    data_96bit_to_128bit u_data_96bit_to_128bit(
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),
	
        .I_96b_frame_start  ( process_O_tuser   ),
        .I_96b_valid        ( process_O_tvalid  ),
		.I_96b_data         ( process_O_tdata    ),
	
        .O_128b_frame_start ( awb_O_tuser_128  	),
        .O_128b_valid       ( awb_O_tvalid_128 	),
        .O_128b_data        ( awb_O_tdata_128  	)
    );



//data96_128 u_data96_128 (
//    .I_tdata(awb_O_tdata),
//    .O_tdata(awb_O_tdata_128)
//);
	
endmodule
