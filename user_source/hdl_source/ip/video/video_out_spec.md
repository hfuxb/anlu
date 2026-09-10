# `video_out` 模块规格

## DDR 读请求

- `O_ddr_user_req` 表示读突发正在进行，或输出 FIFO 具备新读突发条件。
- `I_ddr_user_ready` 是顶层突发仲裁授权和 DDR FIFO 可接受状态的合取结果。
- 读突发只在获得授权后启动；突发中断时保持原有计数和地址。

## 验证边界

- 必须检查读写请求同时出现时只有一个方向获得授权。
- DDR 返回数据的 FIFO 时序仍由原有 `I_ddr_user_rd_valid` 接口决定。
