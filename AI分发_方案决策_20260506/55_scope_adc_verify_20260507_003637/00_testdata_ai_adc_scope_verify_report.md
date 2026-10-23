# ADC Scope Verify Report (A1-A4)

time: 2026-05-07 00:37:28
data_root: "D:\CodexProject\2026年校电赛\AI分发_方案决策_20260506\55_scope_adc_verify_20260507_003637"
stage: A1~A4 only (CW 40MHz)
scope_channel_used: CH2
note: no parameter analysis; manual scope node/probe ground/VREF fields are pending.

## Auto Summary (A1~A4)

| case | rf_vpp | scope_vmax | scope_vmin | scope_vpp | flatline | adc_imin | adc_imax | adc_qmin | adc_qmax | fw_id_hit | sigdet_hit | sigdet_locked | stop_reason |
|---|---:|---:|---:|---:|---|---:|---:|---:|---:|---|---|---|---|
| A1 | 0.5 | 0 | 0 | 0 | True | 8064 | 8224 | 7808 | 8323 | True | True | False |  |
| A2 | 1 | 0 | 0 | 0 | True | 8060 | 8207 | 7780 | 8283 | True | True | False |  |
| A3 | 1.5 | 0 | 0 | 0 | True | 8054 | 8248 | 7818 | 8301 | True | True | False |  |
| A4 | 2 | 0 | 0 | 0 | True | 8061 | 8256 | 7831 | 8276 | True | True | False |  |

## Manual Fields To Fill

- scope node name (must confirm if it is PC4 ADC pin)
- probe ratio and scope channel ratio consistency
- coupling mode and ground point
- VREF+/VDDA measured value

## Output Files

- 01_scope_adc_cw_matrix.csv
- 02_scope_adc_frequency_matrix.csv (empty this run)
- 03_scope_adc_modulated_matrix.csv (empty this run)
- logs/
- scope/
