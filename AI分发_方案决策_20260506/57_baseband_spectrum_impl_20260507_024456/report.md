# 基带频谱显示接入实现报告

- 时间：2026-05-07 02:44
- 工程：`D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation`
- 固件标识：`fw_id,bbsp_ui_20260507,build=20260507_0235,ask=mod_nochange,psk=bbsp_task`

## 1. 本轮目标

在不改 ADC/DDS 底层、不改调制识别阈值和顺序的前提下，接入锁定后基带频谱摘要显示。

## 2. 实现结果

- 新增独立任务：`Core/App/Tasks/BasebandSpectrumTask.c/.h`
- 新增频谱模块：`Core/App/Signal/app_baseband_spectrum.c/.h`
- `AdcTask.c` 只在锁定后提交 I/Q block 快照，不做频谱计算
- `app_baseband_spectrum.c` 负责快照抽取后的频谱特征计算与状态维护
- `app_lvgl_ui.c` 只读取状态并显示，不参与算法判断
- 串口新增低频日志：`bbsp,valid=...,peak=...,mag=...,noise=...,dc=...,blk=...`

## 3. 频谱实现策略

- 只在 `APP_SIGDET_STAGE_VPP_LOCKED && locked && carrier_present` 后提交数据
- 频谱任务与 ADC 任务解耦，低优先级后台运行
- 每次从现有 I/Q block 中按步长抽取 `256` 点
- 默认等效频谱采样率约 `3.2MHz / 16 = 200kHz`
- 先减均值，再做小窗口复数 DFT，输出：
  - `peak_hz`
  - `peak_mag`
  - `noise_floor`
  - `dc_mag`
- UI 刷新周期改为 `80ms`，目标约每秒 `12~13` 次刷新
- 若锁定失效，频谱状态立即置 `valid=0`，不保留旧值

## 4. 修改文件

- `D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation\Core\App\Tasks\AdcTask.c`
- `D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation\Core\App\LVGL\app_lvgl_ui.c`
- `D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation\Core\App\Tasks\PrintfTask.c`
- `D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation\CMakeLists.txt`
- `D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation\Core\App\Tasks\BasebandSpectrumTask.c`
- `D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation\Core\App\Tasks\BasebandSpectrumTask.h`
- `D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation\Core\App\Signal\app_baseband_spectrum.c`
- `D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation\Core\App\Signal\app_baseband_spectrum.h`

## 5. 构建结果

执行：

```powershell
& 'C:\Users/<user>\AppData\Local\stm32cube\bundles\cmake\4.2.3+st.1\bin\cmake.exe' --build 'D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation\build\Debug'
```

结果：`Debug` 构建通过。

内存占用：

- `DTCMRAM`: `111224 B / 128 KB (84.86%)`
- `RAM_D2`: `32 KB / 288 KB (11.11%)`
- `FLASH`: `611984 B / 2 MB (29.18%)`

## 6. 后续测试关注点

1. 实时串口确认 `fw_id,bbsp_ui_20260507,build=20260507_0235,ask=mod_nochange,psk=bbsp_task`
2. 锁定后确认每秒能看到多次 UI 刷新，至少应出现数帧有效频谱摘要
3. 串口确认 `bbsp,...` 为低频输出，不应刷屏影响 `sigdet/mod` 日志
4. 若出现 `valid=0` 持续不变，优先检查：
   - 是否已进入锁定态
   - 当前 block 是否持续提交给频谱模块
   - 是否有采集链路或锁定状态反复失效