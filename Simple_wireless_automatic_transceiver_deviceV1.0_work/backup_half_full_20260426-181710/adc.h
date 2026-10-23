/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    adc.h
  * @brief   This file contains all the function prototypes for
  *          the adc.c file
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
#ifndef __ADC_H__
#define __ADC_H__

#ifdef __cplusplus
extern "C" {
#endif

/* Includes ------------------------------------------------------------------*/
#include "main.h"

/* USER CODE BEGIN Includes */

/* USER CODE END Includes */

extern ADC_HandleTypeDef hadc1;
extern ADC_HandleTypeDef hadc2;

/* USER CODE BEGIN Private defines */
#define ADC_BLOCK_N      4096U
#define ADC_BUFFER_N     (ADC_BLOCK_N * 2U)
#define sample_count     ADC_BUFFER_N
/* USER CODE END Private defines */

void MX_ADC1_Init(void);
void MX_ADC2_Init(void);

/* USER CODE BEGIN Prototypes */
extern uint16_t adc1_buf[ADC_BUFFER_N];
extern uint16_t adc2_buf[ADC_BUFFER_N];

/* ISR flags */
extern volatile uint8_t adc1_half_ready;
extern volatile uint8_t adc1_full_ready;
extern volatile uint8_t adc2_half_ready;
extern volatile uint8_t adc2_full_ready;

/* Task-consumed block flags: bit0=half, bit1=full */
extern volatile uint8_t adc_block_ready_mask;
extern volatile uint32_t adc_overrun_cnt;

void HAL_ADC_ConvHalfCpltCallback(ADC_HandleTypeDef *hadc);
void HAL_ADC_ConvCpltCallback(ADC_HandleTypeDef *hadc);
/* USER CODE END Prototypes */

#ifdef __cplusplus
}
#endif

#endif /* __ADC_H__ */
