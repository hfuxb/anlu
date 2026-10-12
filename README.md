# HX1P35A 最新左右转识别工程：SIG 专用识别版

完整最新版本位于 [anlu_lr_tracking_lock_20261012](anlu_lr_tracking_lock_20261012/README.md)。本次在同一分支、同一工程目录更新，替代此前上传版本。

- [普通 bit](anlu_lr_tracking_lock_20261012/fpga/traffic_sign_td/td_project/bitstream/traffic_sign_td_lr_tracking_lock.bit)
- [压缩 bit](anlu_lr_tracking_lock_20261012/fpga/traffic_sign_td/td_project/bitstream/traffic_sign_td_lr_tracking_lock_compress.bit)
- [TD 工程](anlu_lr_tracking_lock_20261012/fpga/traffic_sign_td/td_project/traffic_sign_td.al)
- [构建结果、时序、校验值和仿真记录](anlu_lr_tracking_lock_20261012/构建结果.md)

仅 SIG 模式运行左右转识别、显示框与 DIR/MATCH。RAW 原画、ERO 腐蚀、DIL 膨胀停止识别并隐藏识别叠加；DIL 仍为先腐蚀再膨胀。保留 1280×720、自动曝光、自动白平衡、统一字号与 FPGA—STM32 控制接口。

默认 RAW，短按并释放 KEY4 三次进入 SIG：RAW → ERO → DIL → SIG。SIG 中连续三帧确认方向，相反方向连续六帧强匹配才换牌，连续丢失第十四帧解除锁定。切出 SIG 立即清空旧锁定，重新进入后从完整帧重新识别。接小车时切出 SIG 停车并解除 ARM，回到 SIG 后需重新按 KEY1 使能。

上传包包含完整源码、IP、约束、正式参考图、仿真输入、两份 bit 及验证记录。TD 数据库与仿真编译缓存由本机重新生成；仓库原有其他文件保留。

PowerShell 执行 `anlu_lr_tracking_lock_20261012/integration/build_tracking_bit.ps1` 可重新编译；脚本按自身位置定位工程，并可用 `-TdRunPath` 指定 TD 安装位置。报告生成脚本中保留了原版本核验路径，在其他电脑重新生成该报告时需提供相应原版工程。

最终布线 Setup WNS +0.196 ns、Hold WNS +0.020 ns，Setup/Hold TNS 均为 0。识别模式切换、完整 720P HDMI 与小车控制仿真通过；本次尚未实机烧录验证。

普通 bit SHA-256：`6D30D717985D6DB7BC6A5E209331383B053CAF173FD86579A535A6A10157DB15`。
