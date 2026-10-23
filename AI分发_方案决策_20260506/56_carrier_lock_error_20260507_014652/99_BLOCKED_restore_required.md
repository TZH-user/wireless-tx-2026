# BLOCKED: app_signal_detect.c restore required

- 时间：2026-05-07 01:53:52
- 阻塞原因：工程目录写入提权被系统拒绝，提示使用限制到 4:48 AM。
- 影响文件：D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation\Core\App\Signal\app_signal_detect.c
- 当前状态：该文件因一次正则替换误匹配而需要从本轮备份恢复。
- 已保存坏态快照：backups\app_signal_detect.c.broken_20260507_015352
- 原始备份：backups\app_signal_detect.c.bak_before_lockerr
- 最小恢复脚本：scripts\restore_app_signal_detect_c_only.ps1

## 恢复后说明

- 先恢复 app_signal_detect.c，确保工程可重新构建。
- 头文件 app_signal_detect.h 已多出 raw_estimate_hz / demod_lo_hz / correction_hz / coarse_estimate_hz 字段；即使 C 文件恢复原版，这些字段未使用也不应影响构建。
- PrintfTask.c 的 fw_id 已更新为 carrier_lockerr_20260507，用于后续烧录识别。
- 恢复完成后再补充短日志，不再使用跨大段正则替换。
