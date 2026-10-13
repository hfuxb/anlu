# HX1P35A 最新完整工程：坐标、慢刷新 LAT 与 STM32 角度反馈

本分支 `coord-latency-closed-loop-20261013` 上传当前完整版本，主工程位于 [anlu_lr_tracking_lock_20261012](anlu_lr_tracking_lock_20261012/README.md)。仓库根目录继承的其他项目保留；本版本应打开下方主工程链接。

- [TD 工程](anlu_lr_tracking_lock_20261012/fpga/traffic_sign_td/td_project/traffic_sign_td.al)
- [普通 bit](anlu_lr_tracking_lock_20261012/fpga/traffic_sign_td/td_project/bitstream/traffic_sign_td_lr_tracking_lock.bit)
- [同设计压缩 bit](anlu_lr_tracking_lock_20261012/fpga/traffic_sign_td/td_project/bitstream/traffic_sign_td_lr_tracking_lock_compress.bit)
- [配套 4WD_Car STM32 HEX](anlu_lr_tracking_lock_20261012/stm32/WHEELTEC_C50X_FPGA_PD89/OBJ/cli_4WD/4WD_Car_FPGA_PD89.hex)
- [STM32 协议、接线和联调说明](anlu_lr_tracking_lock_20261012/stm32/闭环转向说明.md)
- [构建结果、最终时序及测试记录](anlu_lr_tracking_lock_20261012/构建结果.md)

## 当前功能

1280×720、SC500CS、自动曝光/白平衡；KEY4：RAW → ERO → DIL → MOT → DEH → SIG → RAW。DIL 为 Sobel→腐蚀→膨胀；MOT 帧差标红；DEH 轻量暗通道去雾。只有 SIG 识别左右转及显示 DIR/MATCH/框，确认 L/R 且框有效时显示中心像素坐标，例如 `L (0640,0360)`；问号、等待、无框和非 SIG 隐藏坐标。保留三帧确认、六帧强反向换牌、十四帧丢失保持。

右上角 LAT 仍每帧测量，健康数字约每1秒在帧首更新为最近完整值；首次、失效、溢出及恢复及时发布，1.5秒无测量更新失效。它不包含摄像头曝光和屏幕内部延迟。

FPGA 发送带序号的相对 ±90°请求，STM32 根据校准后的物理陀螺仪角速度执行角度外环，并保留编码器轮速 PI。匹配 ACCEPTED/RUNNING 后的 DONE 才结束转向，停止、故障和超时撤销 ARM。新协议必须使用本包配套 HEX；本次坐标/LAT更新未改变该 HEX。尚未实车验证转向符号和精度，转向时机仍是稳定识别确认，未加入路口距离判断。

自动正常/去雾识别、KEY3正常锁定及去雾后视觉增强均仍是讨论方案，本次没有实现。

## 验证与重新编译

坐标：14个完整720P帧、29,120个标签黄金像素及14项锁存/避让检查。LAT保持：3531项检查，含完整75,000,000拍一秒计时；另十一完整720P帧检查保持、失效和RGB/同步/DDR时序。其他已通过测试见构建结果。

本次最终布线 Setup WNS +0.205ns、Hold WNS +0.020ns，Setup/Hold TNS均为0。生成和仿真未替代实机验证。

普通 bit SHA-256：`D0C3046D0E1C41A366C14FE50447AAD1613A53C70278ED4B1F303C3EAD487F79`。STM32 HEX SHA-256：`27C94C3B4E7EBEF7FFA1F8C1B2E48CF1A726CF64AACD2727D42B2571FF4DCEA1`。

PowerShell运行 `anlu_lr_tracking_lock_20261012/integration/build_tracking_bit.ps1`，可用 `-TdRunPath` 指定本机TD；STM32选择Keil的 **4WD_Car**，或运行 `stm32/build_armcc.py`。原版核验/源参考路径保留在报告脚本中，在其他电脑复跑相关核验需提供原版工程。

上传包含完整源码、IP、约束、参考图与仿真输入、构建/测试脚本、两份 bit、配套 HEX/BIN/AXF/MAP 和结果证据；TD数据库、仿真编译缓存及对象文件由本机重建。上传清单和逐文件校验见 `UPLOAD_MANIFEST.json`。
