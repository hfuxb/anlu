# HX1P35A 完整工程：自动曝光、白平衡与自动去雾识别

本分支 `coord-latency-closed-loop-20261013` 保存当前完整版本，主工程位于 [anlu_lr_tracking_lock_20261012](anlu_lr_tracking_lock_20261012/README.md)。本次直接更新原分支。

- [本版本中文改进说明](anlu_lr_tracking_lock_20261012/docs/版本改进说明_20261014.md)
- [TD工程](anlu_lr_tracking_lock_20261012/fpga/traffic_sign_td/td_project/traffic_sign_td.al)
- [普通bit](anlu_lr_tracking_lock_20261012/fpga/traffic_sign_td/td_project/bitstream/traffic_sign_td_lr_tracking_lock.bit)
- [同设计压缩bit](anlu_lr_tracking_lock_20261012/fpga/traffic_sign_td/td_project/bitstream/traffic_sign_td_lr_tracking_lock_compress.bit)
- [配套四驱STM32 HEX](anlu_lr_tracking_lock_20261012/stm32/WHEELTEC_C50X_FPGA_PD89/OBJ/cli_4WD/4WD_Car_FPGA_PD89.hex)
- [自动去雾判据、KEY3和显示增强说明](anlu_lr_tracking_lock_20261012/docs/自动去雾识别与增强.md)
- [STM32角度闭环、接线和协议](anlu_lr_tracking_lock_20261012/stm32/闭环转向说明.md)
- [资源、时序、产物校验及仿真结果](anlu_lr_tracking_lock_20261012/构建结果.md)

## 已实现功能

SC500CS 1280×720，自动曝光和自动白平衡。KEY4顺序为RAW→ERO→DIL→MOT→DEH→SIG。DIL在腐蚀结果上继续膨胀；MOT使用帧差标红。只有SIG识别路牌、显示方向/MATCH/检测框与确认目标的中心坐标。

SIG根据去雾前AWB画面的环境统计，自动选择正常或去雾识别；具备进入/退出确认时间、完整帧数门槛和最少2秒保持。KEY3切换AUTO或强制正常识别，显示PATH:N AUTO、PATH:D AUTO、PATH:N LOCK。DEH与SIG去雾显示加入Gamma 0.85和限幅锐化，识别支路不使用后续Gamma/锐化。

保留提供的左右转参考模板、方向防跳变和14帧丢失保持。右上角LAT每帧测量、健康数字约每秒更新。保留STM32编码器轮速PI和相对±90°陀螺仪角度闭环，配套HEX与bit必须一起使用。

## 验证与固件

最终Slice88.36%、ERAM64.81%、DSP38/40；Setup WNS +0.121ns、Hold WNS +0.020ns，两项TNS均为0。测试覆盖完整720P流、自动环境切换、KEY3、Gamma/锐化数值参考、用户箭头模板的合成雾识别、坐标/LAT与既有串口和角度控制。

普通bit SHA-256：`BDD78B454C8B5F99CD3681E5299E7EA87F279B96732160542E91E415CF4C7E34`。

STM32 HEX SHA-256：`27C94C3B4E7EBEF7FFA1F8C1B2E48CF1A726CF64AACD2727D42B2571FF4DCEA1`。

本包保存超声波升级之前的当前版本，不包含超声波距离触发或绕障。软件构建/仿真不能替代实车转向、制动和真实场景验证。

完整源码、IP、约束、标准标识、测试、构建脚本、bit、HEX和验证证据均已上传。TD数据库、仿真缓存和对象文件由本机重建。逐文件清单见UPLOAD_MANIFEST.json。
