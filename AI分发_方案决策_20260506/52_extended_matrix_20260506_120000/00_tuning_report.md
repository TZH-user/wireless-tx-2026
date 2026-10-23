# Report: Extended Matrix Verification

Time: 2026-05-06 12:25:28
FW: fw_id,moddet_param_ui_20260506,build=20260506_1058,ask=strong_env_ui,psk=param_scale_v1

## 1. Summary

| Stage | Content | Pass Rate | Status |
|---|---|---|---|
| A | Frequency (35/45 MHz) | 0% (0/0) | FAIL |
| B | Amplitude (0.75-2.0 VPP) | 0% (0/0) | FAIL |
| C | Rate (1k-20k) | 0% (0/0) | FAIL |

## 5. Overall Assessment


### 5.1 FSK rate: Goertzel/autocorrelation needed?

### 5.2 Next steps
Failures observed:
1. CW misclassified at 35/45 MHz and 2.0 VPP -- likely IQ imbalance at band edges and ADC saturation
2. 1 kHz modulation rate: all modes fail -- 128-sample block too short for 1ms modulation period
3. FSK rate at 1k/20k extremes is inaccurate -- edge counting unreliable at rate extremes

Recommendations:
- To support 1kHz: increase min_block_samples or add cross-block accumulation
- FSK rate: add Goertzel/autocorrelation next round
- CW errors at band edges: investigate IQ front-end frequency response

## 6. Artifacts
- 01_stageA_frequency_summary.csv
- 02_stageB_amplitude_summary.csv
- 03_stageC_rate_summary.csv
- 04_rate_trend_analysis.csv
- logs/stageA/*.log
- logs/stageB/*.log
- logs/stageC/*.log
