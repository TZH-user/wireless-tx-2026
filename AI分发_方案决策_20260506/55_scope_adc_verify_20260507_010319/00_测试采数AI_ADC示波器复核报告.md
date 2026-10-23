# 00_测试采数AI_ADC示波器复核报告

time: 2026-05-07 01:05:39
data_root: "D:\CodexProject\2026年校电赛\AI分发_方案决策_20260506\55_scope_adc_verify_20260507_010319"
scope_channel_used: CH2
scope_node: MCU_ADC_CH2_USER_WIRED_NEED_ONSITE_CONFIRM
probe_ratio: 1
scope_coupling: DC
ground_point: NEED_USER_CONFIRM
vref_v: <unmeasured>
stop_triggered: False

## A1~A4 (CW 40MHz)
| case | rf_vpp | scope_vmax | scope_vmin | scope_vpp | adc_imin | adc_imax | adc_qmin | adc_qmax | fw_id | sigdet_hit | stop_reason |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| A1 | 0.5 | 2.28125 | 1.6875 | 0.59375 | 8073 | 8206 | 7827 | 8320 | True | True |  |
| A2 | 1 | 2.28125 | 1.6875 | 0.59375 | 8095 | 8234 | 7777 | 8296 | True | True |  |
| A3 | 1.5 | 2.28125 | 1.6875 | 0.59375 | 8058 | 8254 | 7720 | 8286 | True | True |  |
| A4 | 2 | 2.28125 | 1.6875 | 0.59375 | 8036 | 8225 | 7829 | 8271 | True | True |  |

## B1~B3 (CW Frequency Cross Check)
| case | rf_mhz | rf_vpp | scope_vmax | scope_vmin | scope_vpp | adc_imin | adc_imax | adc_qmin | adc_qmax | fw_id | sigdet_hit | stop_reason |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| B1 | 30 | 1.5 | 2.28125 | 1.6875 | 0.59375 | 7410 | 8441 | 7002 | 8356 | True | True |  |
| B2 | 45 | 1.5 | 2.28125 | 1.6875 | 0.59375 | 8097 | 8222 | 7818 | 8330 | True | True |  |
| B3 | 50 | 1.5 | 2.28125 | 1.6875 | 0.59375 | 7823 | 8245 | 7796 | 8304 | True | True |  |

## C1~C5 (Modulated Peak Check)
| case | mod | rf_vpp | scope_vmax | scope_vmin | scope_vpp | adc_imin | adc_imax | adc_qmin | adc_qmax | fw_id | sigdet_hit | stop_reason |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| C1 | AM | 1.5 | 2.28125 | 1.6875 | 0.59375 | 8043 | 8266 | 7796 | 8308 | True | True |  |
| C2 | ASK | 1.5 | 2.28125 | 1.6875 | 0.59375 | 8063 | 8228 | 7823 | 8294 | True | True |  |
| C3 | FM | 1.5 | 2.28125 | 1.6875 | 0.59375 | 8070 | 8228 | 7811 | 8297 | True | True |  |
| C4 | FSK | 1.5 | 2.28125 | 1.6875 | 0.59375 | 8068 | 8231 | 7831 | 8278 | True | True |  |
| C5 | PSK | 1.5 | 2.28125 | 1.6875 | 0.59375 | 7919 | 8371 | 7764 | 8356 | True | True |  |

## 任务书问题回答（自动侧）
1. 4V 是否为 PC4 电压：自动测试无法独立确认，当前仅按用户链路描述记录为 CH2 接 MCU ADC 节点，需现场测点复核。
2. VREF+/VDDA：本轮未实测，需万用表补录。
3. raw 无 near/clip 与高电压并存：若测点不在 PC4 或存在前级钳位/分压，可能出现该现象。
4. 安全 RF VPP 上限：在未完成 VREF 实测与测点实锤前，仅可暂用 1.5VPP。
5. 后续算法测试幅度建议：默认 1.5VPP；若现场确认 PC4 接近 VREF+，降到 1.0VPP。
6. 是否需要硬件处理：待 VREF 与 PC4 实测后由方案决策 AI 最终裁定。

## 输出文件
- 01_scope_adc_cw_matrix.csv
- 02_scope_adc_frequency_matrix.csv
- 03_scope_adc_modulated_matrix.csv
- logs/*.log
- scope/*.csv
