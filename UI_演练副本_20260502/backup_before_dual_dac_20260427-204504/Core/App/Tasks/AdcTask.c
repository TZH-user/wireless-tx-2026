#include "cmsis_os2.h"
#include "main.h"
#include "adc.h"
#include "tim.h"
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "RtosTypes.h"
#include "dac.h"
/* 处理策略：ISR 置位 + 信号量唤醒，任务线程按 half/full 分块消费并回填 DAC。 */

/* 将 16bit 原始码线性换算成 1e-4 V 定点值，便于无浮点格式化输出。 */
static uint32_t adc_raw_to_v_1e4(uint16_t raw)
{
    return (uint32_t)((((uint64_t)raw * 33000ULL) + 8191ULL) / 16383ULL);
}

/* H7 开启 D-Cache 时，DMA 读写前后需要 Cache 维护，且地址按 32B 对齐。 */
#if (__DCACHE_PRESENT == 1U)
static void adc_invalidate_cache_range(const void *addr, uint32_t size)
{
    uintptr_t start = (uintptr_t)addr;
    uintptr_t aligned_start = start & ~(uintptr_t)0x1FU;
    uintptr_t aligned_end = (start + (uintptr_t)size + 31U) & ~(uintptr_t)0x1FU;
    SCB_InvalidateDCache_by_Addr((uint32_t *)aligned_start, (int32_t)(aligned_end - aligned_start));
}

static void adc_clean_cache_range(const void *addr, uint32_t size)
{
    uintptr_t start = (uintptr_t)addr;
    uintptr_t aligned_start = start & ~(uintptr_t)0x1FU;
    uintptr_t aligned_end = (start + (uintptr_t)size + 31U) & ~(uintptr_t)0x1FU;
    SCB_CleanDCache_by_Addr((uint32_t *)aligned_start, (int32_t)(aligned_end - aligned_start));
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

/* 失效 ADC 指定分块缓存，确保 CPU 读取到 DMA 最新写入的数据。 */
static void adc_invalidate_block(uint32_t offset)
{
    const uint32_t bytes = ADC_BLOCK_N * sizeof(uint16_t);
    adc_invalidate_cache_range(&adc1_buf[offset], bytes);
    adc_invalidate_cache_range(&adc2_buf[offset], bytes);
}

/* 清理 DAC 指定分块缓存，确保 DMA 读取到 CPU 最新回填的数据。 */
static void dac_clean_block(uint32_t offset)
{
    const uint32_t bytes = ADC_BLOCK_N * sizeof(uint16_t);
    adc_clean_cache_range(&dac1_buf[offset], bytes);
}

/* 示例回放链路：把 ADC1 的 16bit 数据右移 4bit 后写入 DAC12bit 缓冲。 */
static void dac_fill_block_from_adc(uint32_t offset)
{
    uint32_t i;

    for (i = 0U; i < ADC_BLOCK_N; ++i)
    {
        /* ADC16-bit right aligned -> DAC12-bit right aligned */
        dac1_buf[offset + i] = (uint16_t)(adc1_buf[offset + i] >> 2);  // 14bit -> 12bit
    }

    dac_clean_block(offset);
}

/* 原子读取并清零 ready_mask，避免与 ISR 并发更新发生竞态。 */
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

/* 按步进抽样后打包为 VOFA 文本帧，分片投递到打印队列。 */
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

/* 统一停流顺序：先停触发源，再停 ADC/DAC DMA，避免继续产生新采样。 */
static void adc_stop_stream(void)
{
    (void)HAL_TIM_Base_Stop(&htim6);
    (void)HAL_ADC_Stop_DMA(&hadc1);
    (void)HAL_ADC_Stop_DMA(&hadc2);
    (void)HAL_DAC_Stop_DMA(&hdac1, DAC_CHANNEL_1);
}

/* 重新启动前清空标志位与输出缓冲，确保双缓冲从干净状态进入循环。 */
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
    /* 先启动 DAC DMA，让输出端先进入循环读取状态。 */
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
/* 主循环：阻塞等信号量 -> 取 ready_mask -> 分半块/全块处理 -> 可选串口发送。 */
{
    uint8_t ready_mask;

    (void)argument;

    adc_start_stream();

    for (;;)
    {
        if (osSemaphoreAcquire(AdcFrameReadySemHandle, osWaitForever) != osOK)
        /* osWaitForever 为阻塞等待，未收到信号量时任务挂起，不占用 CPU。 */
        {
            continue;
        }

        ready_mask = adc_fetch_and_clear_ready_mask();
        if (ready_mask == 0U)
        {
            continue;
        }

        if ((ready_mask & 0x01U) != 0U)
        /* 处理前半块：索引区间 [0, ADC_BLOCK_N)。 */
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
        /* 处理后半块：索引区间 [ADC_BLOCK_N, ADC_BUFFER_N)。 */
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