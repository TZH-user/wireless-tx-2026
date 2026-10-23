# Test Data AI Output (Round2 Minimal Capture)

- time: 2026-05-06 03:28:40
- data_root: "D:\CodexProject\2026年校电赛\AI分发_方案决策_20260506\40_娴嬭瘯閲囨暟_绗簩杞甠20260506_032759"
- instrument: DG CH1, SIN, 1.5Vpp, 0V offset, HIGHZ
- serial: COM15 @ 115200

## Summary

| case | fw_id | sigdet_final | mod_count | log_path |
|---|---|---|---:|---|
| CW_40M_SIGDET | False | False | 29 | "D:\CodexProject\2026年校电赛\AI分发_方案决策_20260506\40_娴嬭瘯閲囨暟_绗簩杞甠20260506_032759\logs\01_CW_40M_SIGDET_merged_dg4062_merged-log_2026-05-06_032815-157.log" |
| ASK_40M_a0p75_r10k | False | False | 23 | "D:\CodexProject\2026年校电赛\AI分发_方案决策_20260506\40_娴嬭瘯閲囨暟_绗簩杞甠20260506_032759\logs\02_ASK_40M_a0p75_r10k_merged_dg4062_merged-log_2026-05-06_032827-746.log" |
| PSK_40M_p180_r10k | False | False | 21 | "D:\CodexProject\2026年校电赛\AI分发_方案决策_20260506\40_娴嬭瘯閲囨暟_绗簩杞甠20260506_032759\logs\03_PSK_40M_p180_r10k_merged_dg4062_merged-log_2026-05-06_032840-296.log" |

## Key Lines

### CW_40M_SIGDET
- fw_id: <none>
- sigdet: <none>
- mod1: [2026-05-06 03:27:59.908] [INFO] [RX] mod,mode=FM,blk=536192,car=1,ac=45944011,env=153,edge=110,lvl=8,freq=109,psk=31,hist=1,pos=87,neg=12,bias=3866199 | {"format": "ASCII", "bytes": 113}
- mod2: [2026-05-06 03:28:00.444] [INFO] [RX] mod,mode=FM,blk=536256,car=1,ac=46333755,env=121,edge=104,lvl=8,freq=114,psk=32,hist=1,pos=88,neg=11,bias=4110152 | {"format": "ASCII", "bytes": 113}

### ASK_40M_a0p75_r10k
- fw_id: <none>
- sigdet: <none>
- mod1: [2026-05-06 03:28:15.672] [INFO] [RX] mod,mode=AM,blk=1664,car=1,ac=30131828,env=598,edge=34,lvl=8,freq=103,psk=0,hist=1,pos=98,neg=1,bias=2856608 | {"format": "ASCII", "bytes": 108}
- mod2: [2026-05-06 03:28:15.862] [INFO] [RX] mod,m=UNKNOWN,ac=0,env=0,edge=0,lvl=0,fq=0,psk=0,hist=0,+=0,-=0,blk=0 | {"format": "ASCII", "bytes": 69}

### PSK_40M_p180_r10k
- fw_id: <none>
- sigdet: <none>
- mod1: [2026-05-06 03:28:28.417] [INFO] [RX] mod,m=UNKNOWN,ac=0,env=0,edge=0,lvl=0,fq=0,psk=0,hist=0,+=0,-=0,blk=0 | {"format": "ASCII", "bytes": 69}
- mod2: [2026-05-06 03:28:29.598] [INFO] [RX] mod,mode=FM,blk=64,car=1,ac=46945950,env=131,edge=80,lvl=8,freq=105,psk=16,hist=1,pos=9,neg=90,bias=-3560359 | {"format": "ASCII", "bytes": 108}

