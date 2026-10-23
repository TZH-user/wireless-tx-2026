# 2026 无线收发 —— 自动扫频收发装置工作区

<p align="center">
  <em>2026 校电子设计竞赛 F 题（简易无线自动收发装置）—— STM32H743 + AD9959 固件，以及产出它的完整多 AI 工程过程档案：调度书、决策审查、逐轮实验证据。</em>
</p>

## 项目简介

本仓库是一个**完整保真的竞赛工作区**：主固件之外，还保留了全部过程产物 —— 多 AI 执行调度书、参数审查决策书、逐轮实验目录（脚本+报告）、带 `manifest.jsonl` 溯源的采集矩阵、文件/方案改动记录。"多个专职 AI（代码 / 测试采数 / 数据分析 / 审查）通过门控文档协同"这套工程方法本身，与固件同为本仓库的交付物。

固件是 **STM32H743XIH6 自动收发装置**：AD9959 四通道 DDS、双 ADC 相干 I/Q 采集、DAC 播放、LTDC + LVGL + SDRAM 触摸界面，FreeRTOS 任务划分（`AdcTask`、`DDSTask`、`PrintfTask`、显示）。配套文档覆盖兄弟项目（扫频解调）的工作：30~50 MHz 实验频段自动扫频锁定 + AM/ASK/FM/FSK/PM/PSK 调制识别，110~130 MHz 赛题频段预留。

> 🇬🇧 English version: [README.md](README.md)

## 核心亮点

- 📡 **AD9959 四通道 DDS 栈** —— 应用层（`app_dds_ctrl` + 默认状态缓存）+ 硬件层，固定的 LO/RF 通道映射
- 📊 **双 ADC 相干 I/Q** —— `adc1_buf → I (PC4/ADC1_INP4)`、`adc2_buf → Q (PB1/ADC2_INP5)`，VOFA 调试输出可开关
- 🖥️ **完整 UI 栈** —— LTDC + LVGL + SDRAM + 触摸，显示任务 + UI 参数远程调试轮（第 51 轮）
- 🤖 **多 AI 调度纪律** —— 调度书含各 AI 状态区（执行前必须核对前置任务状态）；决策书可以**否决**方案（"仍停留在多方案并列，没有唯一执行方案"）；文件/方案改动全程留痕
- 🧪 **证据优先的实验** —— 采集矩阵（`raw_iq / logs / metrics / scope / context / manifest.jsonl`）、调参闭环（第 50~59 轮：基线 → 频率矩阵 → ADC 量程 → 示波器-ADC 互证 → 载波锁定排错 → 基带频谱）、PowerShell 测试夹具与重采脚本
- 🗂️ **过程保真** —— 保留带日期的整包备份与 UI 演练副本，演化可回溯

## 技术栈

<div>
  <img src="https://img.shields.io/badge/STM32-H743XIH6-0072CE"/>
  <img src="https://img.shields.io/badge/AD9959-4ch_DDS-FF6F00"/>
  <img src="https://img.shields.io/badge/FreeRTOS-tasks-9C27B0"/>
  <img src="https://img.shields.io/badge/LVGL%20%2B%20LTDC%20%2B%20SDRAM-UI-47B955"/>
  <img src="https://img.shields.io/badge/CMake-3.20+-064F8C"/>
  <img src="https://img.shields.io/badge/Arm%20GNU-toolchain-263238"/>
  <img src="https://img.shields.io/badge/PowerShell-test_harness-5391FE"/>
  <img src="https://img.shields.io/badge/Multi--AI-dispatch_docs-8E44AD"/>
</div>

## 仓库结构

```
Simple_wireless_automatic_transceiver_deviceV1.0_work/   # 主固件（CMake、CubeMX .ioc）
├── Core/App/          # DDS_9959 · LTDC · LVGL · SDRAM · Tasks · Touch
├── Core/ Drivers/ Middlewares/ cmake/ 启动文件 · 链接脚本
└── backup_*/          # 工程内小体积带日期代码快照
Simple_wireless_automatic_transceiver_deviceV1.0_fullbackup_20260427-213827/  # 带日期整包备份
UI_演练副本_20260502/    # UI 演练副本
00_总控/                 # 多 AI 协作补充规定（目录结构、编码与写入方式）
AI分发_参数分析_20260506/ # 参数分析分发轮
AI分发_方案决策_20260506/ # 30+ 实验轮（调参闭环、矩阵、示波器互证……）
capture_matrix_20260506_021122/  # 采集矩阵：metrics + scope + manifest.jsonl
赛题/                    # 赛题原文（B/C/F，版权归主办方）
交接文档_20260504.md      # 兄弟项目（扫频/调制识别）参数交接
决策书_参数分析审查_20260506.md  # 审查决策书
多AI执行调度书_20260506.md       # 多 AI 执行调度书（各 AI 状态区）
文件改动记录.md · 方案改动记录.md # 文件与方案改动日志
```

## 编译与运行

```bash
cd Simple_wireless_automatic_transceiver_deviceV1.0_work
cmake --preset Debug            # Arm GNU 工具链 + Ninja
cmake --build build/Debug -j8   # 产物 .elf，经 STM32_Programmer_CLI / DAPLink 烧录
```

实验夹具是普通 PowerShell 脚本（根目录 `capture_matrix_03.ps1`、各轮内 `run_*_matrix.ps1`）——先读该轮的 `report.md`。

## 文档

- 多 AI 执行调度书：[多AI执行调度书_20260506.md](多AI执行调度书_20260506.md)
- 参数审查决策书：[决策书_参数分析审查_20260506.md](决策书_参数分析审查_20260506.md)
- 兄弟项目交接（扫频/调制识别阈值）：[交接文档_20260504.md](交接文档_20260504.md)
- 改动日志：[文件改动记录.md](文件改动记录.md) · [方案改动记录.md](方案改动记录.md)

## 说明

- 串口/运行日志与构建产物不入库（见 `.gitignore`）；实验轮保留脚本、报告与指标。
- `赛题/` 下赛题 PDF 版权归赛事主办方，仅作参考收录。

## 许可证

固件、脚本与过程文档以 **CC BY-NC 4.0** © 2026 TZH-user 发布，详见 [LICENSE](LICENSE)。赛题原文版权归主办方所有。
