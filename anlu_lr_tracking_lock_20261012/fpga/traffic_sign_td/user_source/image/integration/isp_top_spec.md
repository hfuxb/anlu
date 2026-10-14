# isp_top

## 功能

模块连接官方 Demosaic、AWB、实时图像算法、传统路牌识别和 96 位转 128 位打包器。

AWB输出先由`process_stage_*`寄存，再进入共用11级去雾／等延迟直通核心。环境统计取自去雾前AWB，SIG在帧首选择正常／去雾RGB，KEY3可强制正常。该核心输出同时送同一个路牌识别器及空间算法；Gamma／锐化不进入识别器。

显示路径依次经过5级空间算法、7级Gamma／限幅锐化、2级MOT及官方96→128位DDR打包器。RAW／SIG／MOT／DEH走空间算法RGB支路，ERO／DIL保持原Sobel→腐蚀／开运算。增强只在DEH或SIG自动去雾帧启用。共用去雾＋增强＋MOT共20级额外延迟，比旧版增加7拍；各模式延迟相同，不改变像素顺序、DDR布局或HDMI读取。

所有模式／有效／行尾控制随RGB同步延迟。DDR打包器帧首仍遵循官方提前AWB标记协议。内部`O_recognition_path={force_normal,dehaze_SIG}`由顶层同步后在HDMI帧首锁存。详细操作与参数见`docs/自动去雾识别与增强.md`。

## 复位和时序

- `I_rst_n` 是低有效异步复位。
- 复位后寄存器级输出无效，模式默认 RAW。
- `process_stage_tuser` 与 `process_stage_tdata`、`process_stage_tvalid` 同拍对齐。
- 当 AWB 的帧首早于有效数据时，`awb_frame_pending` 将帧首保持到第一个有效数据拍。

```wavedrom
{signal:[
  {name:'awb_O_tvalid',wave:'01010'},
  {name:'awb_O_tuser', wave:'01000'},
  {name:'stage_tvalid',wave:'00101'},
  {name:'stage_tuser', wave:'00100'},
  {name:'process output',wave:'00101'}
]}
```

## 验证

- RTL 综合必须检查 AWB 到图像算法的最差路径已在 `process_stage_*` 寄存器结束。
- 小尺寸独立数值参考、完整1280×720统计和吞吐、真实左右模板合成雾识别、实际DDR打包、PATH和坐标字体／RGB回归必须通过。
- 最终资源及setup／hold由TD布局布线报告确认。
