# Wireless TX/RX 2026 — Auto-Sweep Transceiver Workspace

<p align="center">
  <em>Campus contest 2026 (Problem F: simple wireless auto transceiver) — an STM32H743 + AD9959 firmware, plus the complete multi-AI engineering process archive that produced it: dispatch books, decision reviews, and per-round experiment evidence.</em>
</p>

## Overview

This repository is a **whole contest workspace, kept honest**: alongside the main firmware there are the raw process artifacts — multi-AI dispatch schedules (调度书), parameter-review decision books (决策书), per-round experiment directories with scripts/reports, capture matrices with `manifest.jsonl` provenance, and file/plan change logs. The engineering story — several specialized AI agents (code, test-capture, data-analysis, review) coordinated through gated documents — is as much the deliverable as the firmware.

The firmware itself is a **STM32H743XIH6 auto transceiver**: AD9959 4-channel DDS, dual-ADC coherent I/Q capture, DAC playback, and an LTDC + LVGL + SDRAM touch UI, with FreeRTOS tasks (`AdcTask`, `DDSTask`, `PrintfTask`, display). Companion documents cover the sibling sweep/demodulation work (30–50 MHz experimental band auto-sweep lock with AM/ASK/FM/FSK/PM/PSK recognition; 110–130 MHz contest band reserved).

> 🇨🇳 中文版说明见 [README_CN.md](README_CN.md)

## Highlights

- 📡 **AD9959 4-channel DDS stack** — app layer (`app_dds_ctrl` + default-state cache) over a hardware layer, fixed channel mapping for LO/RF paths
- 📊 **Coherent dual-ADC I/Q** — `adc1_buf → I (PC4/ADC1_INP4)`, `adc2_buf → Q (PB1/ADC2_INP5)`, with VOFA debug output switch
- 🖥️ **Full UI stack** — LTDC + LVGL + SDRAM + touch, display task plus remote UI-parameter debug round (round 51)
- 🤖 **Multi-AI dispatch discipline** — dispatch books with per-AI status zones (must check predecessors' state before executing), decision books that can *reject* a plan ("analysis not accepted: stays multi-option, no unique executable plan"), plan/file change logs
- 🧪 **Evidence-first experiments** — capture matrices (`raw_iq / logs / metrics / scope / context / manifest.jsonl`), tuning loops (rounds 50–59: baseline → freq matrices → ADC range → scope-ADC verify → carrier-lock error → baseband spectrum), PowerShell harnesses with retest scripts
- 🗂️ **Process fidelity** — a dated full backup and a UI rehearsal copy are kept so the evolution is traceable

## Tech Stack

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

## Repository Layout

```
Simple_wireless_automatic_transceiver_deviceV1.0_work/   # MAIN firmware (CMake, CubeMX .ioc)
├── Core/App/          # DDS_9959 · LTDC · LVGL · SDRAM · Tasks · Touch
├── Core/ Drivers/ Middlewares/ cmake/ startup · linker
└── backup_*/          # tiny dated code snapshots inside the project
Simple_wireless_automatic_transceiver_deviceV1.0_fullbackup_20260427-213827/  # dated full backup
UI_演练副本_20260502/    # UI rehearsal copy
00_总控/                 # multi-AI collaboration rules (dir structure, coding/write discipline)
AI分发_参数分析_20260506/ # parameter-analysis dispatch round
AI分发_方案决策_20260506/ # 30+ experiment rounds (tuning loops, matrices, scope verify, ...)
capture_matrix_20260506_021122/  # capture matrix: metrics + scope + manifest.jsonl
赛题/                    # contest problem statements (B/C/F, organizer copyright)
交接文档_20260504.md      # handoff: sweep/mod-detect parameters of the companion project
决策书_参数分析审查_20260506.md  # review decision book
多AI执行调度书_20260506.md       # multi-AI dispatch book (per-AI status zones)
文件改动记录.md · 方案改动记录.md # file & plan change logs
```

## Getting Started

```bash
cd Simple_wireless_automatic_transceiver_deviceV1.0_work
cmake --preset Debug            # Arm GNU toolchain + Ninja
cmake --build build/Debug -j8   # flash the .elf via STM32_Programmer_CLI / DAPLink
```

Experiment harnesses are plain PowerShell scripts (`capture_matrix_03.ps1`, `run_*_matrix.ps1` in each round) — read the round's `report.md` first.

## Documentation

- Multi-AI dispatch book: [多AI执行调度书_20260506.md](多AI执行调度书_20260506.md)
- Parameter review decision: [决策书_参数分析审查_20260506.md](决策书_参数分析审查_20260506.md)
- Companion-project handoff (sweep/mod-detect thresholds): [交接文档_20260504.md](交接文档_20260504.md)
- Change logs: [文件改动记录.md](文件改动记录.md) · [方案改动记录.md](方案改动记录.md)

## Notes

- Serial/runtime logs and build outputs are excluded from git (see `.gitignore`); experiment rounds keep scripts, reports and metrics.
- Contest problem PDFs under `赛题/` belong to the contest organizers and are included for reference only.

## License

Firmware, scripts and process documents are released under **CC BY-NC 4.0** © 2026 TZH-user — see [LICENSE](LICENSE). Contest problem statements remain the property of their organizers.
