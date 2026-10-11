# traffic_sign_display_filter

## 功能

该模块只处理屏幕结果。首次识别或方向变化须连续两帧同类；已锁定方向的短时未知结果最多保持两帧，第三帧未知时清除。相同方向的新有效框立即更新，允许牌面因距离变化而改变尺寸。车辆控制仍使用原始逐帧结果。

## 接口

`I_result_valid` 为原始帧结果脉冲。`I_ascii` 取 `S`、`L`、`R` 或 `?`。`I_bbox_valid` 和坐标与该结果同拍。输出为同一时钟域中寄存后的显示结果；每个输入结果产生一个 `O_result_valid` 脉冲。

## 时序

```wavedrom
{ "signal": [
  {"name":"clk", "wave":"p......"},
  {"name":"I_result_valid", "wave":"0101010"},
  {"name":"I_ascii", "wave":"x=L=L=?=", "data":["L","L","?"]},
  {"name":"O_ascii", "wave":"x?=?=L=", "data":["?","L","L"]}
]}
```

## 验证

`sim/video720/tb_traffic_sign_display_filter.sv` 检查首次确认、框尺寸变化、短暂未知、方向切换、持续失踪清除和结果脉冲宽度。
