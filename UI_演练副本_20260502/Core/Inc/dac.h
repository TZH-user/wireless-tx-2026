/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    dac.h
  * @brief   This file contains all the function prototypes for
  *          the dac.c file
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2026 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */
/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __DAC_H__
#define __DAC_H__

#ifdef __cplusplus
extern "C" {
#endif

/* Includes ------------------------------------------------------------------*/
#include "main.h"

/* USER CODE BEGIN Includes */
#include "adc.h"
/* 复用 ADC 的块长度定义，保证 ADC 与 DAC DMA 缓冲区一一对应。 */
/* USER CODE END Includes */

extern DAC_HandleTypeDef hdac1;

/* USER CODE BEGIN Private defines */

/* USER CODE END Private defines */

void MX_DAC1_Init(void);

/* USER CODE BEGIN Prototypes */
extern uint32_t dac12_buf[ADC_BUFFER_N];
/* 双 DAC 打包缓冲：低 12bit->CH1，高 12bit->CH2，长度与 ADC 双缓冲一致。 */
/* USER CODE END Prototypes */

#ifdef __cplusplus
}
#endif

#endif /* __DAC_H__ */

