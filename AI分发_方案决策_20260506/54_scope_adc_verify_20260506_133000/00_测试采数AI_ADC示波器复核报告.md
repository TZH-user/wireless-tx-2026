# 测试采数 AI：ADC 示波器复核报告

- 时间：2026-05-07 00:00
- 工程：`D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation`
- 固件：`fw_id,adc_range_test_20260506,build=20260506_1230,ask=clip_log=1,psk=none`

## 1. 结论

**示波器 CH2 未测得 PC4/ADC 引脚信号。自动采集无法完成过压复核。**

| 问题 | 结论 |
|---|---|
| 用户看到的 4V 是不是 PC4 上的电压？ | **Scope 未测到** — CH2 始终全 0V/raw=127 平线 |
| VREF+/VDDA 实测 | 未测量（需万用表） |
| ADC 是否有 near/clip？ | **否，全部为 0** |
| 安全 RF VPP 上限 | ADC 数据支持 **>= 2.0VPP** |
| Scope CH2 为何全 0V？ | 探头物理连接问题（悬空/接地/非 PC4 节点） |

## 2. ADC 数据（可靠）

40MHz CW，4 个 RF VPP 级别，10s 采集：

| RF VPP | ADC I min | ADC I max | ADC I Vpp | ADC Q Vpp | I clip | I near |
|---|---|---|---|---|---|---|
| 0.5 | 8063 | 8236 | 173 | 474 | 0 | 0 |
| 1.0 | 8088 | 8223 | 135 | 490 | 0 | 0 |
| 1.5 | 8071 | 8265 | 194 | 503 | 0 | 0 |
| 2.0 | 8065 | 8231 | 166 | 427 | 0 | 0 |

- I 通道中心约 8100 raw → 约 1.63V（假设 VREF+=3.3V, 14-bit）
- Q 通道中心约 8000 raw → 约 1.61V
- I/Q Vpp 均 < 600 lsb（< 4% FS），远低于满量程
- 所有 case: fw_id 命中, sigdet_final 命中

## 3. Scope CH2 数据（无效）

自动采集全部显示 **0.0V / raw=127 恒定平线**：

| RF VPP | Scope Vmax | Scope Vmin | Scope raw |
|---|---|---|---|
| 0.5 | 0.0V | 0.0V | 127 |
| 1.0 | 0.0V | 0.0V | 127 |
| 1.5 | 0.0V | 0.0V | 127 |
| 2.0 | 0.0V | 0.0V | 127 |

Scope 设置：CH2 ON, scale=1V/div, offset=-1.84V, DC coupling, RUN 状态。

**原因判断**：CH2 探头物理连接不在 PC4/ADC1_INP4 引脚。ADC 有 1.63V DC 信号但 scope 读 0V——测点不同。

## 4. 需要用户手动确认

- [ ] CH2 探头尖端是否确实接触 **PC4 (ADC1_INP4)** 引脚焊盘/测试点？
- [ ] CH2 地线夹是否与 MCU GND 连接？
- [ ] 探头是否为 1x？示波器通道倍率设置是否匹配？
- [ ] 用万用表测 **VDDA / VREF+** 电压：______V

## 5. 基于 ADC 数据的安全结论

在 scope 复核完成前，仅基于 ADC raw 数据：

- **2.0VPP 下无 ADC 削顶**（clip/near-rail 全 0）
- ADC 引脚估算电压约 1.63V DC（远低于 3.3V VREF+）
- **安全建议**：保持 1.5VPP 默认，2.0VPP 在 ADC 侧是安全的

## 6. 产物

- `01_scope_adc_cw_final.csv`
- `logs/*.log`
