# `uial2axis` 模块规格

## 计数和标记

- `I_data_start` 将横向和纵向计数器置零。
- `I_data_end` 也将两个计数器置零，避免下一帧继承不完整链路的计数状态。
- `axis_tlast` 仍由有效数据拍的横向计数产生，`axis_tuser` 仍标记第一行第一个有效数据拍。

## 验证边界

- 需要覆盖正常帧、提前结束和下一帧开始前计数恢复。
- ModelSim 仿真应检查 `axis_tuser`、`axis_tlast` 与四像素数据的对齐。
