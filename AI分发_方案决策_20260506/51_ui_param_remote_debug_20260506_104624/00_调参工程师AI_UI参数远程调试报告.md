# UI 参数远程调试报告

- 时间：2026-05-06 11:06
- 工程：`D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation`
- 最新 ELF：`D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation\build\Debug\Simple_wireless_IQ_demodulation.elf`
- 最新 fw_id：`fw_id,moddet_param_ui_20260506,build=20260506_1058,ask=strong_env_ui,psk=param_scale_v1`
- 输出目录：`D:\CodexProject\2026年校电赛\AI分发_方案决策_20260506\51_ui_param_remote_debug_20260506_104624`

## 1. 结论

- 烧录成功：是。
- 新 `fw_id` 命中：是。
- `sigdet_final` 命中：18/18。
- `mod` 扩展字段命中：18/18，字段含 `stable/conf/rate/depth/dev/shift`。
- `ui` 代理日志命中：18/18，字段含 `mode/inst/conf/rate/depth/dev/shift`。
- 稳定模式多数判决：18/18 通过。
- 当前参数可支撑 UI 显示；FSK rate 仍有较大波动，但 shift 稳定且数量级正确。
- 当前不建议继续阈值调参；继续改 FSK rate 会明显偏向本轮数据，边际收益低。
- 不建议本轮上 Goertzel/FFT；等扩展速率矩阵后再决定。

## 2. 修改记录

- 备份 1：`D:\CodexProject\2026年校电赛\AI分发_方案决策_20260506\51_ui_param_remote_debug_20260506_104624\backups\before_ui_proxy_20260506_104659`
- 备份 2：`D:\CodexProject\2026年校电赛\AI分发_方案决策_20260506\51_ui_param_remote_debug_20260506_104624\backups\before_compact_mod_ui_20260506_105331`
- 备份 3：`D:\CodexProject\2026年校电赛\AI分发_方案决策_20260506\51_ui_param_remote_debug_20260506_104624\backups\before_param_scale_v1_20260506_105729`
- 修改 `Core/App/Signal/app_mod_detect.c`：增加紧凑 `mod` 扩展日志、`ui` 代理日志；修正参数估计输出。
- 修改 `Core/App/Tasks/PrintfTask.c`：更新 `fw_id` 到 `build=20260506_1058`。
- 未修改 ADC DMA 双缓冲、PC4/PB1 映射、DDS/AD9959 底层和 CMake 工具链。

## 3. 链路与稳定模式

| case | expected | link | stable | pass | mod | ui | counts |
|---|---:|---:|---:|---:|---:|---:|---|
| CW_30M | CW | True | CW | True | 19 | 19 | CW:19 |
| AM_30M_10k_50pct | AM | True | AM | True | 19 | 19 | AM:19 |
| ASK_30M_10k_low0 | ASK | True | ASK | True | 19 | 19 | ASK:19 |
| FM_30M_10k_dev75k | FM | True | FM | True | 18 | 18 | FM:18 |
| FSK_30M_10k_hop20k | FSK | True | FSK | True | 18 | 18 | FSK:18 |
| PSK_30M_10k_180 | PSK | True | PSK | True | 19 | 19 | PSK:19 |
| CW_40M | CW | True | CW | True | 19 | 19 | CW:19 |
| AM_40M_10k_50pct | AM | True | AM | True | 18 | 18 | AM:18 |
| ASK_40M_10k_low0 | ASK | True | ASK | True | 18 | 18 | ASK:18 |
| FM_40M_10k_dev75k | FM | True | FM | True | 18 | 18 | FM:18 |
| FSK_40M_10k_hop20k | FSK | True | FSK | True | 18 | 18 | FSK:18 |
| PSK_40M_10k_180 | PSK | True | PSK | True | 19 | 19 | PSK:19 |
| CW_50M | CW | True | CW | True | 19 | 19 | CW:19 |
| AM_50M_10k_50pct | AM | True | AM | True | 19 | 19 | AM:19 |
| ASK_50M_10k_low0 | ASK | True | ASK | True | 19 | 19 | ASK:19 |
| FM_50M_10k_dev75k | FM | True | FM | True | 18 | 18 | FM:18 |
| FSK_50M_10k_hop20k | FSK | True | FSK | True | 19 | 18 | FSK:19 |
| PSK_50M_10k_180 | PSK | True | PSK | True | 19 | 19 | PSK:19 |

## 4. 参数统计

| case | rate avg Hz | depth avg pm | dev avg Hz | shift avg Hz | conf avg % |
|---|---:|---:|---:|---:|---:|
| CW_30M | 0 | 0 | 0 | 0 | 99.74 |
| AM_30M_10k_50pct | 9202.26 | 460.53 | 0 | 0 | 100 |
| ASK_30M_10k_low0 | 9288.53 | 964.74 | 0 | 0 | 94.63 |
| FM_30M_10k_dev75k | 11432.33 | 0 | 75264.72 | 0 | 100 |
| FSK_30M_10k_hop20k | 16731.06 | 0 | 20394.94 | 18108.67 | 94.06 |
| PSK_30M_10k_180 | 11044.84 | 0 | 0 | 0 | 100 |
| CW_40M | 0 | 0 | 0 | 0 | 100 |
| AM_40M_10k_50pct | 8880.22 | 525.61 | 0 | 0 | 100 |
| ASK_40M_10k_low0 | 10836.39 | 915.78 | 0 | 0 | 75.94 |
| FM_40M_10k_dev75k | 11137.33 | 0 | 75808.06 | 0 | 100 |
| FSK_40M_10k_hop20k | 7056.78 | 0 | 19829.22 | 19829.22 | 100 |
| PSK_40M_10k_180 | 9422.05 | 0 | 0 | 0 | 100 |
| CW_50M | 0 | 0 | 0 | 0 | 100 |
| AM_50M_10k_50pct | 10411.21 | 365.11 | 0 | 0 | 100 |
| ASK_50M_10k_low0 | 9450.37 | 963.11 | 0 | 0 | 100 |
| FM_50M_10k_dev75k | 10694.56 | 0 | 75106.56 | 0 | 100 |
| FSK_50M_10k_hop20k | 5731.21 | 0 | 19965.21 | 19965.21 | 100 |
| PSK_50M_10k_180 | 9654 | 0 | 0 | 0 | 100 |

## 5. 参数可用性判断

- CW：`rate/depth/dev/shift` 全部为 0，可用。
- AM 10 kHz 50%：rate 约 8.9-10.4 kHz，depth 约 365-526 pm；40 MHz 附近最接近 50%，端点幅度估计有硬件/锁定相关偏差，但不会数量级错误。
- ASK 10 kbps low=0：rate 约 9.3-10.8 kHz，depth 约 916-965 pm，可用。
- FM 10 kHz dev=75 kHz：rate 约 10.7-11.4 kHz，dev 约 75.1-75.8 kHz，可用。
- FSK 10 kbps hop=20 kHz：shift 约 18.1-20.5 kHz，可用；rate 约 5.7-16.7 kHz，数量级正确但波动较大，UI 可以显示为估计值。
- PSK 10 kbps 180°：rate 约 9.4-11.0 kHz，可用。

## 6. 暂停原因

- 当前稳定模式和主要参数已经满足 UI 代理显示验收。
- 剩余最弱项是 FSK rate，它来自符号翻转计数，受 FSK 数据码型和锁定差频影响较大；继续用阈值修正容易过拟合。
- 若后续要求 FSK rate 更准，建议采集 1k/5k/10k/20k 速率矩阵后，再考虑 Goertzel 或小 FFT/自相关估计，不建议现在直接接 FFT 主链路。

## 7. 安全停机

- DG4062 CH1 输出：关闭。
- DG4062 CH1 调制：关闭。
- DG4062 CH2 输出：关闭。

## 8. 产物

- `01_summary.csv`：链路和 stable 统计。
- `02_param_stats.csv`：参数 min/avg/max 和首条日志样本。
- `logs/ui_param_full_matrix/*.log`：18 个 case 合并日志。
- `scripts/run_ui_param_full_matrix.ps1`：完整矩阵采集脚本。
