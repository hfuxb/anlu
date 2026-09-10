# `cnn_result_cdc` 模块规格

## CDC 协议

- 源域只在 `I_src_toggle` 变化时更新 ASCII 保持寄存器。
- 目标域使用两级 toggle 同步和两级数据同步。
- 检测到 toggle 变化后再等待一个目标时钟，随后产生一个周期的 `O_dst_valid`。

## 数据约束

- `I_src_ascii` 在结果事件之间可以变化，但目标域只采样稳定的保持寄存器。
- 复位值为 ASCII `A`，不改变原有结果接口。

## 验证边界

- 使用 `sim/cnn/tb_cnn_result_cdc.sv` 检查不同源/目标时钟比下的 toggle、ASCII 和 valid 对齐。
