# HX1P35A 最新左右转跟踪与方向锁定工程

完整最新版本位于 [anlu_lr_tracking_lock_20261012](anlu_lr_tracking_lock_20261012/README.md)。

- [普通 bit（用于本次烧录验证）](anlu_lr_tracking_lock_20261012/fpga/traffic_sign_td/td_project/bitstream/traffic_sign_td_lr_tracking_lock.bit)
- [TD 工程](anlu_lr_tracking_lock_20261012/fpga/traffic_sign_td/td_project/traffic_sign_td.al)
- [构建结果、时序、校验值和仿真记录](anlu_lr_tracking_lock_20261012/构建结果.md)

保留 1280×720、自动曝光、自动白平衡及 FPGA—STM32 接口。左右模板分别取自用户提供的两张正式标识。连续三帧匹配确认后锁定方向，后续分数下降不改变 L/R；检测框按位置持续跟踪，连续丢失第八帧解除锁定。所有状态字母和数字已统一字号。

本分支保留仓库原有文件，新增完整最新工程。上传包包含源码、IP、约束、仿真输入、正式参考图、两份 bit 和最终验证记录；TD 数据库及 XSim 编译缓存可在本机重新生成。

获取工程后可通过 `anlu_lr_tracking_lock_20261012/integration/build_tracking_bit.ps1` 编译，该脚本按自身位置定位工程。

最终布线 Setup WNS +0.177 ns、Hold WNS +0.020 ns，Setup/Hold TNS 为 0。仿真结果不等同于实物摄像头准确率。
