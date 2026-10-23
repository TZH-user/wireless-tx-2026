#ifndef APP_RTOS_H
#define APP_RTOS_H

#include "cmsis_os2.h"
#include <stdint.h>

typedef struct  //定义一个消息结构体类型，用于存储要发送的数据
{
    uint16_t len;
    uint8_t kind;
    char data[125];
} print_msg_t;

/*---------------------------------串口打印选择(ADC数据/日志)---------------------------------*/
typedef enum    //串口打印模式
{
    UART_MODE_VOFA = 0,   // 输出 VOFA 采样文本帧
    UART_MODE_LOG         // 仅输出日志文本，不发送 VOFA 采样帧
} uart_mode_t;

typedef enum    //打印类型
{
    PRINT_KIND_VOFA = 0,
    PRINT_KIND_LOG
} print_kind_t;
extern volatile uart_mode_t g_uart_mode;
/* 运行时切换串口输出模式；若需“静默”，可在业务层不投递 PrintQueue 消息。 */

#define VOFA_SEND_STEP 4    // VOFA 下采样步进：每隔 N 个采样点发送一次

extern osMessageQueueId_t PrintQueueHandle;
extern osSemaphoreId_t AdcFrameReadySemHandle;
extern osThreadId_t AdcTaskHandle;
extern osThreadId_t PrintfTaskHandle;
extern osMessageQueueId_t DDSQueueHandle;
extern osThreadId_t DDSTaskHandle;

void print_queue_send_vofa(const char *text);
void print_queue_send_log(const char *text);
void StartDDSTask(void *argument);
void StartPrintfTask(void *argument);
void StartAdcTask(void *argument);

#endif
