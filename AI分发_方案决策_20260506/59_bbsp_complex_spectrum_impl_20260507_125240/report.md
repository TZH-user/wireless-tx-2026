# 复数基带频谱写入报告

- 时间：2026-05-07 12:52
- 工程：`D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation`
- 固件标识：`fw_id,bbsp_complex_20260507,build=20260507_1130,ask=mod_nochange,psk=bbsp41_goertzel`

## 1. 本轮写入内容

在上一阶段“基带频谱摘要显示”基础上，升级为复数基带条形频谱显示：

- 中心：`0Hz`
- 范围：`-100kHz ~ +100kHz`
- 柱数：`41`
- 步进：`5kHz`
- 算法：固定频点复数能量投影，优先按 Goertzel/定点频点能量思路实现

## 2. 仍保持的分层

- `AdcTask.c`
  - 只负责锁定后提交 I/Q block 快照
- `app_signal_detect.c`
  - 只负责载波锁定
- `app_mod_detect.c`
  - 只负责调制识别
- `app_baseband_spectrum.c`
  - 负责复数基带频谱状态与 41 柱能量计算
- `app_lvgl_ui.c`
  - 只读取状态并显示图表与摘要
- `BasebandSpectrumTask.c`
  - 独立低优先级调度任务

## 3. 算法说明

- 仍使用当前独立频谱任务结构
- 每次从现有 I/Q block 中抽取 `256` 点
- 等效采样率保持约 `3.2MHz / 16 = 200kHz`
- 频点集合固定为：
  - `-100kHz, -95kHz, ... 0Hz ... +95kHz, +100kHz`
- `0Hz` 柱单独使用 `dc_mag`
- 其余频点使用去均值后的复数基带序列做离散频点能量计算
- 图表显示值做相对归一化和平方根压缩，范围 `0~1000`

## 4. UI 显示

底部区域现在包含：

- `LV_CHART_TYPE_BAR` 柱状图
- 横轴提示：`-100k / 0 / +100k`
- 摘要文本：
  - `valid`
  - `Peak`
  - `Mag`
  - `Noise`
  - `DC`
  - `LO`
  - `Carrier`

UI 刷新周期保持 `80ms`，目标约每秒 `12~13` 次刷新。

## 5. 修改文件

- `D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation\Core\App\Signal\app_baseband_spectrum.h`
- `D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation\Core\App\Signal\app_baseband_spectrum.c`
- `D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation\Core\App\LVGL\app_lvgl_ui.c`
- `D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation\Core\App\Tasks\PrintfTask.c`

## 6. 构建结果

执行：

```powershell
& 'C:\Users/<user>\AppData\Local\stm32cube\bundles\cmake\4.2.3+st.1\bin\cmake.exe' --build 'D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation\build\Debug'
```

结果：`Debug` 构建通过。

内存占用：

- `DTCMRAM`: `111488 B / 128 KB (85.06%)`
- `RAM_D2`: `32 KB / 288 KB (11.11%)`
- `FLASH`: `615920 B / 2 MB (29.37%)`

## 7. 测试关注点

1. 实时串口确认：`fw_id,bbsp_complex_20260507,build=20260507_1130,ask=mod_nochange,psk=bbsp41_goertzel`
2. 锁定后屏幕底部应显示 `41` 柱复数基带频谱
3. 中间柱对应 `0Hz`
4. 失锁后图表应清零并回到 `valid=0`
5. 串口 `bbsp,...` 日志应仍为低频，不影响 `sigdet/mod`