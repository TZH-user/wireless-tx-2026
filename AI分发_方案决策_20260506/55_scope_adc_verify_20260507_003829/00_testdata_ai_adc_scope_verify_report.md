# ADC Scope Verify Report (A1-A4)

time: 2026-05-07 00:39:13
data_root: "D:\CodexProject\2026年校电赛\AI分发_方案决策_20260506\55_scope_adc_verify_20260507_003829"
stage: A1~A4 only (CW 40MHz)
scope_channel_used: CH2
note: no parameter analysis; manual scope node/probe ground/VREF fields are pending.

## Auto Summary (A1~A4)

| case | rf_vpp | scope_vmax | scope_vmin | scope_vpp | flatline | adc_imin | adc_imax | adc_qmin | adc_qmax | fw_id_hit | sigdet_hit | sigdet_locked | stop_reason |
|---|---:|---:|---:|---:|---|---:|---:|---:|---:|---|---|---|---|
| A1 | 0.5 | 0 | 0 | 0 | True | 8046 | 8247 | 7808 | 8323 | True | True | False |  |
| A2 | 1 | 0 | 0 | 0 | True | 8042 | 8250 | 7822 | 8320 | True | True | False |  |
| A3 | 1.5 | 0 | 0 | 0 | True | 8006 | 8223 | 7813 | 8330 | True | True | False |  |
| A4 | 2 | 0 | 0 | 0 | True | 8063 | 8237 | 7823 | 8313 | True | True | False |  |

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
