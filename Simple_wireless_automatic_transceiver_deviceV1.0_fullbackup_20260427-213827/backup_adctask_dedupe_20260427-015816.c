#include "cmsis_os2.h"
#include "main.h"
#include "adc.h"
#include "dac.h"
#include "tim.h"
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "RtosTypes.h"
#include "dac.h"

/*------------ 缓存清理（写 DAC 缓冲后要 clean) ------------*/
#if (__DCACHE_PRESENT == 1U)
static void adc_clean_cache_range(const void *addr, uint32_t size)
{
    uintptr_t start = (uintptr_t)addr;
    uintptr_t aligned_start = start & ~(uintptr_t)0x1FU;
    uintptr_t aligned_end = (start + (uintptr_t)size + 31U) & ~(uintptr_t)0x1FU;
    SCB_CleanDCache_by_Addr((uint32_t *)aligned_start, (int32_t)(aligned_end - aligned_start));
}
#else
static void adc_clean_cache_range(const void *addr, uint32_t size) { (void)addr; (void)size; }
#endif
/*------------ 块拷贝函数（ADC16bit -> DAC12bit） ------------*/
static void dac_fill_block_from_adc(uint32_t offset)
{
    uint32_t i;
    for (i = 0; i < ADC_BLOCK_N; ++i)
    {
        dac1_buf[offset + i] = (uint16_t)(adc1_buf[offset + i] >> 4); // 16b->12b
    }
    adc_clean_cache_range(&dac1_buf[offset], ADC_BLOCK_N * sizeof(uint16_t));
}


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

static void adc_clean_cache_range(const void *addr, uint32_t size)
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

static void dac_clean_block(uint32_t offset)
{
    const uint32_t bytes = ADC_BLOCK_N * sizeof(uint16_t);
    adc_clean_cache_range(&dac1_buf[offset], bytes);
}

static void dac_fill_block_from_adc(uint32_t offset)
{
    uint32_t i;

    for (i = 0U; i < ADC_BLOCK_N; ++i)
    {
        /* ADC16-bit right aligned -> DAC12-bit right aligned */
        dac1_buf[offset + i] = (uint16_t)(adc1_buf[offset + i] >> 4);
    }

    dac_clean_block(offset);
}

static inline uint8_t adc_fetch_and_clear_ready_mask(void)
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
    (void)HAL_DAC_Stop_DMA(&hdac1, DAC_CHANNEL_1);
}

static void adc_start_stream(void)
{
    adc_stop_stream();

    adc1_half_ready = 0U;
    adc1_full_ready = 0U;
    adc2_half_ready = 0U;
    adc2_full_ready = 0U;
    adc_block_ready_mask = 0U;

    memset(dac1_buf, 0, sizeof(dac1_buf));
    adc_clean_cache_range(dac1_buf, sizeof(dac1_buf));

    if (HAL_DAC_Start_DMA(&hdac1, DAC_CHANNEL_1, (uint32_t *)dac1_buf, ADC_BUFFER_N, DAC_ALIGN_12B_R) != HAL_OK)
    {
        Error_Handler();
    }

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
        if (osSemaphoreAcquire(AdcFrameReadySemHandle, osWaitForever) != osOK)
        {
            continue;
        }

        ready_mask = adc_fetch_and_clear_ready_mask();
        if (ready_mask == 0U)
        {
            continue;
        }

        if ((ready_mask & 0x01U) != 0U)
        {
            adc_invalidate_block(0U);
            dac_fill_block_from_adc(0U);
            adc_task_half_cnt++;

            if (g_uart_mode == UART_MODE_VOFA)
            {
                adc_send_block_to_vofa(0U);
            }
        }

        if ((ready_mask & 0x02U) != 0U)
        {
            adc_invalidate_block(ADC_BLOCK_N);
            dac_fill_block_from_adc(ADC_BLOCK_N);
            adc_task_full_cnt++;

            if (g_uart_mode == UART_MODE_VOFA)
            {
                adc_send_block_to_vofa(ADC_BLOCK_N);
            }
        }
    }
}