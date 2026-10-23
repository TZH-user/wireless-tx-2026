#include "cmsis_os2.h"
#include "main.h"
#include "adc.h"
#include "tim.h"
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "RtosTypes.h"

static uint32_t adc_raw_to_v_1e4(uint16_t raw)
{
    return (uint32_t)((((uint64_t)raw * 33000ULL) + 32767ULL) / 65535ULL);
}

#if (__DCACHE_PRESENT == 1U)
static void adc_invalidate_cache_range(const void *addr, uint32_t size)
{
    uintptr_t start = (uintptr_t)addr;
    uintptr_t aligned_start = start & ~(uintptr_t)0x1FU;
    uintptr_t aligned_end = (start + (uintptr_t)size + 31U) & ~(uintptr_t)0x1FU;
    SCB_InvalidateDCache_by_Addr((uint32_t *)aligned_start, (int32_t)(aligned_end - aligned_start));
}
#else
static void adc_invalidate_cache_range(const void *addr, uint32_t size)
{
    (void)addr;
    (void)size;
}
#endif

static void adc_invalidate_block(uint32_t offset)
{
    const uint32_t bytes = ADC_BLOCK_N * sizeof(uint16_t);
    adc_invalidate_cache_range(&adc1_buf[offset], bytes);
    adc_invalidate_cache_range(&adc2_buf[offset], bytes);
}

static inline uint8_t adc_fetch_and_clear_ready_mask(void)  //从 ADC 中断安全地获取并清除数据块准备好的标志
{
    uint8_t mask;

    __disable_irq();
    mask = adc_block_ready_mask;
    adc_block_ready_mask = 0U;
    __enable_irq();

    return mask;
}

static void adc_print_msg_flush(print_msg_t *msg)
{
    if (msg->len > 0U)
    {
        (void)osMessageQueuePut(PrintQueueHandle, msg, 0U, osWaitForever);
        msg->len = 0U;
    }
}

static void adc_send_block_to_vofa(uint32_t start_index)
{
    uint32_t end_index = start_index + ADC_BLOCK_N;
    print_msg_t msg;
    int n;
    uint32_t i;

    memset(&msg, 0, sizeof(msg));
    msg.kind = PRINT_KIND_VOFA;

    for (i = start_index; i < end_index; i += VOFA_SEND_STEP)
    {
        uint32_t adc1_v_1e4 = adc_raw_to_v_1e4(adc1_buf[i]);
        uint32_t adc2_v_1e4 = adc_raw_to_v_1e4(adc2_buf[i]);

        n = snprintf(&msg.data[msg.len],
                     sizeof(msg.data) - msg.len,
                     "%lu.%04lu,%lu.%04lu\n",
                     adc1_v_1e4 / 10000UL,
                     adc1_v_1e4 % 10000UL,
                     adc2_v_1e4 / 10000UL,
                     adc2_v_1e4 % 10000UL);

        if (n <= 0)
        {
            continue;
        }

        if ((size_t)n >= (sizeof(msg.data) - msg.len))
        {
            adc_print_msg_flush(&msg);

            n = snprintf(&msg.data[msg.len],
                         sizeof(msg.data) - msg.len,
                         "%lu.%04lu,%lu.%04lu\n",
                         adc1_v_1e4 / 10000UL,
                         adc1_v_1e4 % 10000UL,
                         adc2_v_1e4 / 10000UL,
                         adc2_v_1e4 % 10000UL);

            if ((n <= 0) || ((size_t)n >= sizeof(msg.data)))
            {
                continue;
            }
        }

        msg.len += (uint16_t)n;
    }

    adc_print_msg_flush(&msg);
}

static void adc_stop_stream(void)
{
    (void)HAL_TIM_Base_Stop(&htim6);
    (void)HAL_ADC_Stop_DMA(&hadc1);
    (void)HAL_ADC_Stop_DMA(&hadc2);
}

static void adc_start_stream(void)
{
    adc_stop_stream();

    adc1_half_ready = 0U;
    adc1_full_ready = 0U;
    adc2_half_ready = 0U;
    adc2_full_ready = 0U;
    adc_block_ready_mask = 0U;

    if (HAL_ADC_Start_DMA(&hadc1, (uint32_t *)adc1_buf, ADC_BUFFER_N) != HAL_OK)
    {
        Error_Handler();
    }

    if (HAL_ADC_Start_DMA(&hadc2, (uint32_t *)adc2_buf, ADC_BUFFER_N) != HAL_OK)
    {
        Error_Handler();
    }

    if (HAL_TIM_Base_Start(&htim6) != HAL_OK)
    {
        Error_Handler();
    }
}

void StartAdcTask(void *argument)
{
    uint8_t ready_mask;

    (void)argument;

    adc_start_stream();

    for (;;)
    {
        if (osSemaphoreAcquire(AdcFrameReadySemHandle, osWaitForever) != osOK)  //等待 ADC 数据块准备好的信号量
        {
            continue;
        }

        ready_mask = adc_fetch_and_clear_ready_mask();
        if (ready_mask == 0U)
        {
            continue;
        }

        if ((ready_mask & 0x01U) != 0U) //半块数据准备好
        {
            adc_task_half_cnt++;
            if (g_uart_mode == UART_MODE_VOFA)
            {
                adc_invalidate_block(0U);
                adc_send_block_to_vofa(0U);
            }
        }

        if ((ready_mask & 0x02U) != 0U) //全块数据准备好
        {
            adc_task_full_cnt++;
            if (g_uart_mode == UART_MODE_VOFA)
            {
                adc_invalidate_block(ADC_BLOCK_N);
                adc_send_block_to_vofa(ADC_BLOCK_N);
            }
        }
    }
}
