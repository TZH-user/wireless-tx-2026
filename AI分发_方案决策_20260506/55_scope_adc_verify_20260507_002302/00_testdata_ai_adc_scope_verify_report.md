# ADC Scope Verify Report (A1-A4)

time: 2026-05-07 00:23:51
data_root: "D:\CodexProject\2026年校电赛\AI分发_方案决策_20260506\55_scope_adc_verify_20260507_002302"
stage: A1~A4 only (CW 40MHz)
note: no parameter analysis; manual scope node/probe ground/VREF fields are pending.

## Auto Summary (A1~A4)

| case | rf_vpp | scope_vmax | scope_vmin | scope_vpp | adc_imin | adc_imax | adc_qmin | adc_qmax | fw_id | sigdet_locked | stop_reason |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| A1 | 0.5 | 0 | 0 | 0 | 8076 | 8222 | 7821 | 8306 |  | False |  |
| A2 | 1 | 0 | 0 | 0 | 8057 | 8210 | 7812 | 8329 |  | False |  |
| A3 | 1.5 | 0 | 0 | 0 | 8044 | 8266 | 7818 | 8297 |  | False |  |
| A4 | 2 | 0 | 0 | 0 | 8084 | 8258 | 7842 | 8272 |  | False |  |

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
