#include "app_lvgl_ui.h"

#include "adc.h"
#include "RtosTypes.h"
#include "tim.h"
#include "lvgl.h"

#include <stdbool.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>

#define UI_POINT_COUNT              96U
#define UI_UPDATE_PERIOD_MS         80U
#define UI_CHART_HEIGHT             300
#define UI_CHART_WIDTH              560

#define UI_ALARM_HI_MV              2600U
#define UI_ALARM_HIHI_MV            3000U
#define UI_ALARM_FLASH_DIV          3U
#define UI_ALARM_RAISE_CONFIRM      2U
#define UI_ALARM_CLEAR_CONFIRM      3U

#define UI_ACK_ARM_TIMEOUT_MS       2500U
#define UI_ADC_RAW_MID              8192U
#define UI_ADC_RAW_HYST             96U

typedef enum
{
  UI_VIEW_BOTH = 0,
  UI_VIEW_CH1,
  UI_VIEW_CH2
} ui_view_mode_t;

typedef struct
{
  uint32_t ch1_mv;
  uint32_t ch2_mv;
  uint32_t vpp_mv;
  uint32_t freq_tenth_hz;
  uint8_t raw_alarm_level;
  uint32_t block_offset;
} ui_metrics_t;

static lv_obj_t *g_status_bar = NULL;
static lv_obj_t *g_lbl_mode = NULL;
static lv_obj_t *g_lbl_status = NULL;
static lv_obj_t *g_lbl_latest = NULL;
static lv_obj_t *g_lbl_alarm = NULL;

static lv_obj_t *g_btn_ack = NULL;
static lv_obj_t *g_lbl_ack_btn = NULL;
static lv_obj_t *g_lbl_event = NULL;

static lv_obj_t *g_chart = NULL;
static lv_chart_series_t *g_ser_hihi = NULL;
static lv_chart_series_t *g_ser_hi = NULL;
static lv_chart_series_t *g_ser_ch1 = NULL;
static lv_chart_series_t *g_ser_ch2 = NULL;
static lv_chart_cursor_t *g_chart_cursor = NULL;
static lv_obj_t *g_lbl_metrics = NULL;
static lv_obj_t *g_lbl_probe = NULL;

static lv_timer_t *g_ui_timer = NULL;

static ui_view_mode_t g_view_mode = UI_VIEW_BOTH;
static bool g_wave_frozen = false;
static bool g_alarm_ack = false;
static bool g_alarm_ack_armed = false;
static bool g_alarm_flash_on = false;

static uint32_t g_last_full_count = 0U;
static uint32_t g_sample_rate_hz = 0U;
static uint32_t g_ui_fps = 0U;
static uint32_t g_ui_refresh_count = 0U;
static uint32_t g_ui_fps_tick_ms = 0U;
static uint32_t g_ack_arm_tick_ms = 0U;

static uint8_t g_alarm_level = 0U;
static uint8_t g_alarm_pending_level = 0U;
static uint8_t g_alarm_pending_count = 0U;
static uint8_t g_alarm_flash_tick = 0U;

static ui_metrics_t g_metrics = {0};

static void App_LvglUiBuildLayout(lv_obj_t *screen);
static void App_LvglUiBuildStatusBar(lv_obj_t *parent);
static void App_LvglUiBuildControlPanel(lv_obj_t *parent);
static void App_LvglUiBuildWavePanel(lv_obj_t *parent);

static void App_LvglUiUpdateModeText(void);
static void App_LvglUiApplySeriesVisibility(void);
static uint32_t App_LvglUiGetConfiguredSampleRateHz(void);
static void App_LvglUiUpdateFpsEstimate(void);
static uint32_t App_LvglUiAdcRawToMv(uint16_t raw);
static void App_LvglUiFeedChartFromBlock(uint32_t offset);
static uint8_t App_LvglUiCalcAlarmLevel(uint32_t ch1_mv, uint32_t ch2_mv);
static bool App_LvglUiUpdateAlarmState(uint8_t raw_level);
static ui_metrics_t App_LvglUiCollectMetricsFromBlock(uint32_t offset);
static void App_LvglUiUpdateStatusLabels(void);
static void App_LvglUiUpdateAlarmPresentation(void);
static void App_LvglUiLogEvent(const char *fmt, ...);

static void App_LvglUiOnModeClicked(lv_event_t *e);
static void App_LvglUiOnFreezeClicked(lv_event_t *e);
static void App_LvglUiOnAckClicked(lv_event_t *e);
static void App_LvglUiOnChartValueChanged(lv_event_t *e);
static void App_LvglUiOnTimer(lv_timer_t *timer);

void App_LvglUiInit(void)
{
  lv_obj_t *screen = lv_screen_active();

  App_LvglUiBuildLayout(screen);

  g_view_mode = UI_VIEW_BOTH;
  g_wave_frozen = false;
  g_alarm_ack = false;
  g_alarm_ack_armed = false;
  g_alarm_flash_on = false;
  g_alarm_level = 0U;
  g_alarm_pending_level = 0U;
  g_alarm_pending_count = 0U;
  g_alarm_flash_tick = 0U;
  g_last_full_count = adc_task_full_cnt;
  g_sample_rate_hz = App_LvglUiGetConfiguredSampleRateHz();
  g_ui_fps = 0U;
  g_ui_refresh_count = 0U;
  g_ui_fps_tick_ms = lv_tick_get();
  g_ack_arm_tick_ms = 0U;

  App_LvglUiUpdateModeText();
  App_LvglUiApplySeriesVisibility();
  App_LvglUiUpdateStatusLabels();
  App_LvglUiLogEvent("UI ready, measurement running");

  g_ui_timer = lv_timer_create(App_LvglUiOnTimer, UI_UPDATE_PERIOD_MS, NULL);
}

static void App_LvglUiBuildLayout(lv_obj_t *screen)
{
  lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
  lv_obj_set_style_bg_color(screen, lv_color_hex(0x121921), 0);
  lv_obj_set_style_bg_grad_color(screen, lv_color_hex(0x0A0F14), 0);
  lv_obj_set_style_bg_grad_dir(screen, LV_GRAD_DIR_VER, 0);
  lv_obj_set_style_pad_all(screen, 12, 0);

  App_LvglUiBuildStatusBar(screen);
  App_LvglUiBuildControlPanel(screen);
  App_LvglUiBuildWavePanel(screen);
}

static void App_LvglUiBuildStatusBar(lv_obj_t *parent)
{
  lv_obj_t *bar = lv_obj_create(parent);

  g_status_bar = bar;
  lv_obj_set_size(bar, 776, 66);
  lv_obj_align(bar, LV_ALIGN_TOP_MID, 0, 0);
  lv_obj_set_style_radius(bar, 10, 0);
  lv_obj_set_style_bg_color(bar, lv_color_hex(0x1A2531), 0);
  lv_obj_set_style_bg_grad_color(bar, lv_color_hex(0x141D27), 0);
  lv_obj_set_style_bg_grad_dir(bar, LV_GRAD_DIR_VER, 0);
  lv_obj_set_style_border_color(bar, lv_color_hex(0x314152), 0);
  lv_obj_set_style_border_width(bar, 1, 0);
  lv_obj_set_style_shadow_width(bar, 12, 0);
  lv_obj_set_style_shadow_color(bar, lv_color_hex(0x000000), 0);
  lv_obj_set_style_shadow_opa(bar, LV_OPA_30, 0);
  lv_obj_set_style_pad_all(bar, 8, 0);

  g_lbl_mode = lv_label_create(bar);
  lv_obj_set_style_text_color(g_lbl_mode, lv_color_hex(0xE8F0FA), 0);
  lv_obj_align(g_lbl_mode, LV_ALIGN_LEFT_MID, 8, -16);

  g_lbl_status = lv_label_create(bar);
  lv_obj_set_style_text_color(g_lbl_status, lv_color_hex(0x9DB4CF), 0);
  lv_obj_align(g_lbl_status, LV_ALIGN_LEFT_MID, 8, 8);

  g_lbl_alarm = lv_label_create(bar);
  lv_obj_set_style_text_color(g_lbl_alarm, lv_color_hex(0x6BD59A), 0);
  lv_obj_align(g_lbl_alarm, LV_ALIGN_RIGHT_MID, -8, -16);

  g_lbl_latest = lv_label_create(bar);
  lv_obj_set_style_text_color(g_lbl_latest, lv_color_hex(0xC6D6E8), 0);
  lv_obj_align(g_lbl_latest, LV_ALIGN_RIGHT_MID, -8, 10);
}

static void App_LvglUiBuildControlPanel(lv_obj_t *parent)
{
  lv_obj_t *panel = lv_obj_create(parent);
  lv_obj_t *title = NULL;
  lv_obj_t *mode_btn = NULL;
  lv_obj_t *freeze_btn = NULL;
  lv_obj_t *policy = NULL;
  lv_obj_t *hint = NULL;

  lv_obj_set_size(panel, 198, 388);
  lv_obj_align(panel, LV_ALIGN_BOTTOM_LEFT, 0, 0);
  lv_obj_set_style_radius(panel, 10, 0);
  lv_obj_set_style_bg_color(panel, lv_color_hex(0x18232E), 0);
  lv_obj_set_style_bg_grad_color(panel, lv_color_hex(0x121B25), 0);
  lv_obj_set_style_bg_grad_dir(panel, LV_GRAD_DIR_VER, 0);
  lv_obj_set_style_border_color(panel, lv_color_hex(0x334455), 0);
  lv_obj_set_style_border_width(panel, 1, 0);
  lv_obj_set_style_pad_all(panel, 12, 0);

  title = lv_label_create(panel);
  lv_label_set_text(title, "Signal Analyzer");
  lv_obj_set_style_text_color(title, lv_color_hex(0xF0F6FF), 0);
  lv_obj_align(title, LV_ALIGN_TOP_LEFT, 0, 0);

  mode_btn = lv_button_create(panel);
  lv_obj_set_size(mode_btn, 172, 44);
  lv_obj_align(mode_btn, LV_ALIGN_TOP_LEFT, 0, 34);
  lv_obj_set_style_radius(mode_btn, 8, 0);
  lv_obj_set_style_bg_color(mode_btn, lv_color_hex(0x2A4A6A), 0);
  lv_obj_set_style_bg_grad_color(mode_btn, lv_color_hex(0x355B81), 0);
  lv_obj_set_style_bg_grad_dir(mode_btn, LV_GRAD_DIR_VER, 0);
  lv_obj_add_event_cb(mode_btn, App_LvglUiOnModeClicked, LV_EVENT_CLICKED, NULL);
  {
    lv_obj_t *txt = lv_label_create(mode_btn);
    lv_label_set_text(txt, "Switch View");
    lv_obj_center(txt);
  }

  freeze_btn = lv_button_create(panel);
  lv_obj_set_size(freeze_btn, 172, 44);
  lv_obj_align(freeze_btn, LV_ALIGN_TOP_LEFT, 0, 86);
  lv_obj_set_style_radius(freeze_btn, 8, 0);
  lv_obj_set_style_bg_color(freeze_btn, lv_color_hex(0x4D5A68), 0);
  lv_obj_set_style_bg_grad_color(freeze_btn, lv_color_hex(0x5B6878), 0);
  lv_obj_set_style_bg_grad_dir(freeze_btn, LV_GRAD_DIR_VER, 0);
  lv_obj_add_event_cb(freeze_btn, App_LvglUiOnFreezeClicked, LV_EVENT_CLICKED, NULL);
  {
    lv_obj_t *txt = lv_label_create(freeze_btn);
    lv_label_set_text(txt, "Freeze / Run");
    lv_obj_center(txt);
  }

  g_btn_ack = lv_button_create(panel);
  lv_obj_set_size(g_btn_ack, 172, 44);
  lv_obj_align(g_btn_ack, LV_ALIGN_TOP_LEFT, 0, 138);
  lv_obj_set_style_radius(g_btn_ack, 8, 0);
  lv_obj_set_style_bg_color(g_btn_ack, lv_color_hex(0x79512A), 0);
  lv_obj_set_style_bg_grad_color(g_btn_ack, lv_color_hex(0x8F6133), 0);
  lv_obj_set_style_bg_grad_dir(g_btn_ack, LV_GRAD_DIR_VER, 0);
  lv_obj_add_event_cb(g_btn_ack, App_LvglUiOnAckClicked, LV_EVENT_CLICKED, NULL);
  g_lbl_ack_btn = lv_label_create(g_btn_ack);
  lv_label_set_text(g_lbl_ack_btn, "Acknowledge");
  lv_obj_center(g_lbl_ack_btn);

  policy = lv_label_create(panel);
  lv_label_set_text(policy,
                    "Alarm policy\n"
                    "HI/HIHI require ACK\n"
                    "ACK uses 2-step confirm");
  lv_obj_set_style_text_color(policy, lv_color_hex(0xC3B083), 0);
  lv_obj_align(policy, LV_ALIGN_TOP_LEFT, 0, 194);

  hint = lv_label_create(panel);
  lv_label_set_text(hint,
                    "CH1: cyan\n"
                    "CH2: amber\n"
                    "HI: yellow line\n"
                    "HIHI: red line");
  lv_obj_set_style_text_color(hint, lv_color_hex(0x9DB7CF), 0);
  lv_obj_align(hint, LV_ALIGN_BOTTOM_LEFT, 0, -8);

  g_lbl_event = lv_label_create(panel);
  lv_obj_set_width(g_lbl_event, 172);
  lv_label_set_long_mode(g_lbl_event, LV_LABEL_LONG_WRAP);
  lv_obj_set_style_text_color(g_lbl_event, lv_color_hex(0x9FD3AE), 0);
  lv_obj_align(g_lbl_event, LV_ALIGN_BOTTOM_LEFT, 0, -92);
  lv_label_set_text(g_lbl_event, "Event: --");
}

static void App_LvglUiBuildWavePanel(lv_obj_t *parent)
{
  lv_obj_t *panel = lv_obj_create(parent);

  lv_obj_set_size(panel, 570, 388);
  lv_obj_align(panel, LV_ALIGN_BOTTOM_RIGHT, 0, 0);
  lv_obj_set_style_radius(panel, 10, 0);
  lv_obj_set_style_bg_color(panel, lv_color_hex(0x151C25), 0);
  lv_obj_set_style_bg_grad_color(panel, lv_color_hex(0x10161E), 0);
  lv_obj_set_style_bg_grad_dir(panel, LV_GRAD_DIR_VER, 0);
  lv_obj_set_style_border_color(panel, lv_color_hex(0x34485D), 0);
  lv_obj_set_style_border_width(panel, 1, 0);
  lv_obj_set_style_pad_all(panel, 8, 0);

  g_chart = lv_chart_create(panel);
  lv_obj_set_size(g_chart, UI_CHART_WIDTH, UI_CHART_HEIGHT);
  lv_obj_align(g_chart, LV_ALIGN_TOP_MID, 0, 8);
  lv_obj_set_style_bg_color(g_chart, lv_color_hex(0x0A1119), 0);
  lv_obj_set_style_bg_grad_color(g_chart, lv_color_hex(0x0D1520), 0);
  lv_obj_set_style_bg_grad_dir(g_chart, LV_GRAD_DIR_VER, 0);
  lv_obj_set_style_border_color(g_chart, lv_color_hex(0x3D5267), 0);
  lv_obj_set_style_border_width(g_chart, 1, 0);
  lv_obj_set_style_line_color(g_chart, lv_color_hex(0x233444), LV_PART_MAIN);
  lv_obj_set_style_line_width(g_chart, 1, LV_PART_MAIN);
  lv_obj_set_style_line_width(g_chart, 2, LV_PART_ITEMS);
  lv_obj_set_style_width(g_chart, 0, LV_PART_INDICATOR);
  lv_obj_set_style_height(g_chart, 0, LV_PART_INDICATOR);

  lv_chart_set_div_line_count(g_chart, 6, 8);
  lv_chart_set_type(g_chart, LV_CHART_TYPE_LINE);
  lv_chart_set_point_count(g_chart, UI_POINT_COUNT);
  lv_chart_set_axis_range(g_chart, LV_CHART_AXIS_PRIMARY_Y, 0, 3300);
  lv_chart_set_update_mode(g_chart, LV_CHART_UPDATE_MODE_SHIFT);
  lv_obj_add_event_cb(g_chart, App_LvglUiOnChartValueChanged, LV_EVENT_VALUE_CHANGED, NULL);

  g_ser_hihi = lv_chart_add_series(g_chart, lv_color_hex(0xE44D4D), LV_CHART_AXIS_PRIMARY_Y);
  g_ser_hi = lv_chart_add_series(g_chart, lv_color_hex(0xE8C15F), LV_CHART_AXIS_PRIMARY_Y);
  g_ser_ch1 = lv_chart_add_series(g_chart, lv_color_hex(0x3ED6FF), LV_CHART_AXIS_PRIMARY_Y);
  g_ser_ch2 = lv_chart_add_series(g_chart, lv_color_hex(0xFFC46E), LV_CHART_AXIS_PRIMARY_Y);
  g_chart_cursor = lv_chart_add_cursor(g_chart, lv_color_hex(0x9AD1FF), LV_DIR_HOR | LV_DIR_VER);
  lv_chart_set_cursor_point(g_chart, g_chart_cursor, g_ser_ch1, LV_CHART_POINT_NONE);

  lv_chart_set_all_values(g_chart, g_ser_hihi, (int32_t)UI_ALARM_HIHI_MV);
  lv_chart_set_all_values(g_chart, g_ser_hi, (int32_t)UI_ALARM_HI_MV);
  lv_chart_set_all_values(g_chart, g_ser_ch1, 0);
  lv_chart_set_all_values(g_chart, g_ser_ch2, 0);

  g_lbl_metrics = lv_label_create(panel);
  lv_obj_set_width(g_lbl_metrics, UI_CHART_WIDTH);
  lv_obj_set_style_text_color(g_lbl_metrics, lv_color_hex(0xA9C4DD), 0);
  lv_obj_align_to(g_lbl_metrics, g_chart, LV_ALIGN_OUT_BOTTOM_LEFT, 0, 10);
  lv_label_set_text(g_lbl_metrics, "Fs: --  Freq: --  Vpp: --");

  g_lbl_probe = lv_label_create(panel);
  lv_obj_set_width(g_lbl_probe, UI_CHART_WIDTH);
  lv_obj_set_style_text_color(g_lbl_probe, lv_color_hex(0x91AEC9), 0);
  lv_obj_align_to(g_lbl_probe, g_lbl_metrics, LV_ALIGN_OUT_BOTTOM_LEFT, 0, 4);
  lv_label_set_text(g_lbl_probe, "Probe: tap waveform to inspect point");
}

static void App_LvglUiUpdateModeText(void)
{
  const char *mode_text = "BOTH";

  if(g_view_mode == UI_VIEW_CH1) {
    mode_text = "CH1";
  }
  else if(g_view_mode == UI_VIEW_CH2) {
    mode_text = "CH2";
  }

  if(g_lbl_mode != NULL) {
    lv_label_set_text_fmt(g_lbl_mode,
                          "View:%s  Stream:%s",
                          mode_text,
                          g_wave_frozen ? "Frozen" : "Live");
  }
}

static void App_LvglUiApplySeriesVisibility(void)
{
  if((g_chart == NULL) || (g_ser_ch1 == NULL) || (g_ser_ch2 == NULL) ||
     (g_ser_hi == NULL) || (g_ser_hihi == NULL)) {
    return;
  }

  lv_chart_hide_series(g_chart, g_ser_hi, false);
  lv_chart_hide_series(g_chart, g_ser_hihi, false);

  if(g_view_mode == UI_VIEW_BOTH) {
    lv_chart_hide_series(g_chart, g_ser_ch1, false);
    lv_chart_hide_series(g_chart, g_ser_ch2, false);
  }
  else if(g_view_mode == UI_VIEW_CH1) {
    lv_chart_hide_series(g_chart, g_ser_ch1, false);
    lv_chart_hide_series(g_chart, g_ser_ch2, true);
  }
  else {
    lv_chart_hide_series(g_chart, g_ser_ch1, true);
    lv_chart_hide_series(g_chart, g_ser_ch2, false);
  }
}

static uint32_t App_LvglUiGetConfiguredSampleRateHz(void)
{
  uint32_t pclk1_hz = HAL_RCC_GetPCLK1Freq();
  uint32_t tim_clk_hz = pclk1_hz;

  if((RCC->D2CFGR & RCC_D2CFGR_D2PPRE1) != RCC_HCLK_DIV1) {
    tim_clk_hz = pclk1_hz * 2U;
  }

  return tim_clk_hz / ((htim6.Init.Prescaler + 1U) * (htim6.Init.Period + 1U));
}

static void App_LvglUiUpdateFpsEstimate(void)
{
  uint32_t now_ms = lv_tick_get();
  uint32_t dt_ms = now_ms - g_ui_fps_tick_ms;

  if(dt_ms >= 1000U) {
    g_ui_fps = (uint32_t)(((uint64_t)g_ui_refresh_count * 1000ULL + (dt_ms / 2U)) / dt_ms);
    g_ui_refresh_count = 0U;
    g_ui_fps_tick_ms = now_ms;
  }
}

static uint32_t App_LvglUiAdcRawToMv(uint16_t raw)
{
  return (uint32_t)((((uint64_t)raw * 3300ULL) + 8191ULL) / 16383ULL);
}

static void App_LvglUiFeedChartFromBlock(uint32_t offset)
{
  uint32_t i = 0U;
  uint32_t step = ADC_BLOCK_N / UI_POINT_COUNT;

  if(step == 0U) {
    step = 1U;
  }

  for(i = 0U; i < UI_POINT_COUNT; i++) {
    uint32_t index = offset + (i * step);
    uint32_t ch1_mv = 0U;
    uint32_t ch2_mv = 0U;

    if(index >= ADC_BUFFER_N) {
      index = ADC_BUFFER_N - 1U;
    }

    ch1_mv = App_LvglUiAdcRawToMv(adc1_buf[index]);
    ch2_mv = App_LvglUiAdcRawToMv(adc2_buf[index]);

    lv_chart_set_series_value_by_id(g_chart, g_ser_ch1, i, (int32_t)ch1_mv);
    lv_chart_set_series_value_by_id(g_chart, g_ser_ch2, i, (int32_t)ch2_mv);
  }

  lv_chart_refresh(g_chart);
}

static uint8_t App_LvglUiCalcAlarmLevel(uint32_t ch1_mv, uint32_t ch2_mv)
{
  uint32_t max_mv = (ch1_mv > ch2_mv) ? ch1_mv : ch2_mv;

  if(max_mv >= UI_ALARM_HIHI_MV) {
    return 2U;
  }
  if(max_mv >= UI_ALARM_HI_MV) {
    return 1U;
  }
  return 0U;
}

static bool App_LvglUiUpdateAlarmState(uint8_t raw_level)
{
  uint8_t required = 0U;

  if(raw_level == g_alarm_level) {
    g_alarm_pending_level = raw_level;
    g_alarm_pending_count = 0U;
    return false;
  }

  if(raw_level != g_alarm_pending_level) {
    g_alarm_pending_level = raw_level;
    g_alarm_pending_count = 1U;
  }
  else {
    g_alarm_pending_count++;
  }

  required = (raw_level > g_alarm_level) ? UI_ALARM_RAISE_CONFIRM : UI_ALARM_CLEAR_CONFIRM;
  if(g_alarm_pending_count < required) {
    return false;
  }

  g_alarm_level = raw_level;
  g_alarm_pending_count = 0U;
  g_alarm_pending_level = raw_level;

  /* Any level change requires re-ack to avoid stale acknowledgement. */
  g_alarm_ack = false;
  g_alarm_ack_armed = false;
  if(g_lbl_ack_btn != NULL) {
    lv_label_set_text(g_lbl_ack_btn, "Acknowledge");
  }

  return true;
}

static ui_metrics_t App_LvglUiCollectMetricsFromBlock(uint32_t offset)
{
  ui_metrics_t m = {0};
  uint32_t idx_end = offset + (ADC_BLOCK_N - 1U);
  uint16_t min_raw = 0xFFFFU;
  uint16_t max_raw = 0U;
  uint32_t i = 0U;
  uint32_t last_cross_idx = 0U;
  uint32_t period_sum = 0U;
  uint32_t period_cnt = 0U;
  bool has_last_cross = false;

  if(idx_end >= ADC_BUFFER_N) {
    idx_end = ADC_BUFFER_N - 1U;
  }

  m.block_offset = offset;
  m.ch1_mv = App_LvglUiAdcRawToMv(adc1_buf[idx_end]);
  m.ch2_mv = App_LvglUiAdcRawToMv(adc2_buf[idx_end]);
  m.raw_alarm_level = App_LvglUiCalcAlarmLevel(m.ch1_mv, m.ch2_mv);

  for(i = offset; i < (offset + ADC_BLOCK_N) && i < ADC_BUFFER_N; i++) {
    uint16_t s = adc1_buf[i];
    if(s < min_raw) {
      min_raw = s;
    }
    if(s > max_raw) {
      max_raw = s;
    }
  }

  m.vpp_mv = App_LvglUiAdcRawToMv(max_raw) - App_LvglUiAdcRawToMv(min_raw);

  if(g_sample_rate_hz > 0U) {
    uint32_t mid_low = UI_ADC_RAW_MID - UI_ADC_RAW_HYST;
    uint32_t mid_high = UI_ADC_RAW_MID + UI_ADC_RAW_HYST;
    for(i = offset + 1U; i < (offset + ADC_BLOCK_N) && i < ADC_BUFFER_N; i++) {
      uint16_t p = adc1_buf[i - 1U];
      uint16_t c = adc1_buf[i];
      if(((uint32_t)p < mid_low) && ((uint32_t)c >= mid_high)) {
        if(has_last_cross) {
          period_sum += (i - last_cross_idx);
          period_cnt++;
        }
        last_cross_idx = i;
        has_last_cross = true;
      }
    }

    if(period_cnt > 0U) {
      uint32_t avg_period = period_sum / period_cnt;
      if(avg_period > 0U) {
        m.freq_tenth_hz = (uint32_t)((((uint64_t)g_sample_rate_hz * 10ULL) + (avg_period / 2U)) / avg_period);
      }
    }
  }

  return m;
}

static void App_LvglUiUpdateStatusLabels(void)
{
  if(g_lbl_status != NULL) {
    lv_label_set_text_fmt(g_lbl_status,
                          "Fs:%lu Hz  FPS:%lu  UART:%s",
                          (unsigned long)g_sample_rate_hz,
                          (unsigned long)g_ui_fps,
                          (g_uart_mode == UART_MODE_VOFA) ? "VOFA" : "LOG");
  }

  if(g_lbl_latest != NULL) {
    lv_label_set_text_fmt(g_lbl_latest,
                          "CH1:%lu mV  CH2:%lu mV",
                          (unsigned long)g_metrics.ch1_mv,
                          (unsigned long)g_metrics.ch2_mv);
  }

  if(g_lbl_metrics != NULL) {
    lv_label_set_text_fmt(g_lbl_metrics,
                          "Fs:%lu Hz   Freq:%lu.%lu Hz   Vpp:%lu mV",
                          (unsigned long)g_sample_rate_hz,
                          (unsigned long)(g_metrics.freq_tenth_hz / 10U),
                          (unsigned long)(g_metrics.freq_tenth_hz % 10U),
                          (unsigned long)g_metrics.vpp_mv);
  }
}

static void App_LvglUiUpdateAlarmPresentation(void)
{
  uint32_t max_mv = (g_metrics.ch1_mv > g_metrics.ch2_mv) ? g_metrics.ch1_mv : g_metrics.ch2_mv;

  if((g_lbl_alarm == NULL) || (g_status_bar == NULL)) {
    return;
  }

  if(g_alarm_level == 0U) {
    lv_label_set_text(g_lbl_alarm, "ALARM: NORMAL");
    lv_obj_set_style_text_color(g_lbl_alarm, lv_color_hex(0x6BD59A), 0);
    lv_obj_set_style_border_color(g_status_bar, lv_color_hex(0x314152), 0);
    lv_obj_set_style_text_color(g_lbl_latest, lv_color_hex(0xC6D6E8), 0);
    if((g_btn_ack != NULL) && (g_lbl_ack_btn != NULL)) {
      lv_obj_set_style_bg_color(g_btn_ack, lv_color_hex(0x475665), 0);
      lv_obj_set_style_bg_grad_color(g_btn_ack, lv_color_hex(0x566676), 0);
      lv_label_set_text(g_lbl_ack_btn, "Acknowledge");
    }
    return;
  }

  if(g_alarm_level == 1U) {
    lv_label_set_text_fmt(g_lbl_alarm, "ALARM: HIGH [%s]  MAX:%lu mV", g_alarm_ack ? "ACK" : "UNACK", (unsigned long)max_mv);
    lv_obj_set_style_text_color(g_lbl_alarm, (g_alarm_flash_on || g_alarm_ack) ? lv_color_hex(0xFFD66B) : lv_color_hex(0x8D7751), 0);
    lv_obj_set_style_border_color(g_status_bar, (g_alarm_flash_on || g_alarm_ack) ? lv_color_hex(0xFFD66B) : lv_color_hex(0x5E4E36), 0);
    lv_obj_set_style_text_color(g_lbl_latest, (g_alarm_flash_on || g_alarm_ack) ? lv_color_hex(0xFFE9B8) : lv_color_hex(0xC6D6E8), 0);
    if(g_btn_ack != NULL) {
      lv_obj_set_style_bg_color(g_btn_ack, g_alarm_ack ? lv_color_hex(0x2F6C48) : lv_color_hex(0x8A5C27), 0);
      lv_obj_set_style_bg_grad_color(g_btn_ack, g_alarm_ack ? lv_color_hex(0x3D865B) : lv_color_hex(0xA86D2D), 0);
    }
    return;
  }

  lv_label_set_text_fmt(g_lbl_alarm, "ALARM: HIGH HIGH [%s]  MAX:%lu mV", g_alarm_ack ? "ACK" : "UNACK", (unsigned long)max_mv);
  lv_obj_set_style_text_color(g_lbl_alarm, (g_alarm_flash_on || g_alarm_ack) ? lv_color_hex(0xFF6666) : lv_color_hex(0x7E3E3E), 0);
  lv_obj_set_style_border_color(g_status_bar, (g_alarm_flash_on || g_alarm_ack) ? lv_color_hex(0xFF6666) : lv_color_hex(0x613A3A), 0);
  lv_obj_set_style_text_color(g_lbl_latest, (g_alarm_flash_on || g_alarm_ack) ? lv_color_hex(0xFFCBCB) : lv_color_hex(0xC6D6E8), 0);
  if(g_btn_ack != NULL) {
    lv_obj_set_style_bg_color(g_btn_ack, g_alarm_ack ? lv_color_hex(0x6B3D3D) : lv_color_hex(0xA23636), 0);
    lv_obj_set_style_bg_grad_color(g_btn_ack, g_alarm_ack ? lv_color_hex(0x824B4B) : lv_color_hex(0xC03F3F), 0);
  }
}

static void App_LvglUiLogEvent(const char *fmt, ...)
{
  char msg[96];
  va_list ap;

  if(g_lbl_event == NULL) {
    return;
  }

  va_start(ap, fmt);
  (void)vsnprintf(msg, sizeof(msg), fmt, ap);
  va_end(ap);

  lv_label_set_text_fmt(g_lbl_event,
                        "Event:\n[%lu] %s",
                        (unsigned long)adc_task_full_cnt,
                        msg);
}

static void App_LvglUiOnModeClicked(lv_event_t *e)
{
  (void)e;

  if(g_view_mode == UI_VIEW_BOTH) {
    g_view_mode = UI_VIEW_CH1;
  }
  else if(g_view_mode == UI_VIEW_CH1) {
    g_view_mode = UI_VIEW_CH2;
  }
  else {
    g_view_mode = UI_VIEW_BOTH;
  }

  App_LvglUiApplySeriesVisibility();
  App_LvglUiUpdateModeText();
  App_LvglUiLogEvent("View changed");
}

static void App_LvglUiOnFreezeClicked(lv_event_t *e)
{
  (void)e;

  g_wave_frozen = !g_wave_frozen;
  App_LvglUiUpdateModeText();
  App_LvglUiLogEvent(g_wave_frozen ? "Wave display frozen" : "Wave display resumed");
}

static void App_LvglUiOnAckClicked(lv_event_t *e)
{
  uint32_t now_ms = lv_tick_get();

  (void)e;

  if(g_alarm_level == 0U) {
    g_alarm_ack_armed = false;
    if(g_lbl_ack_btn != NULL) {
      lv_label_set_text(g_lbl_ack_btn, "Acknowledge");
    }
    App_LvglUiLogEvent("ACK ignored: no active alarm");
    return;
  }

  if(!g_alarm_ack_armed) {
    g_alarm_ack_armed = true;
    g_ack_arm_tick_ms = now_ms;
    if(g_lbl_ack_btn != NULL) {
      lv_label_set_text(g_lbl_ack_btn, "Confirm ACK");
    }
    App_LvglUiLogEvent("ACK armed, click again to confirm");
    return;
  }

  if((uint32_t)(now_ms - g_ack_arm_tick_ms) > UI_ACK_ARM_TIMEOUT_MS) {
    g_alarm_ack_armed = false;
    if(g_lbl_ack_btn != NULL) {
      lv_label_set_text(g_lbl_ack_btn, "Acknowledge");
    }
    App_LvglUiLogEvent("ACK arm timeout, retry");
    return;
  }

  g_alarm_ack = true;
  g_alarm_ack_armed = false;
  if(g_lbl_ack_btn != NULL) {
    lv_label_set_text(g_lbl_ack_btn, "Acknowledge");
  }
  App_LvglUiLogEvent("Alarm acknowledged");
  App_LvglUiUpdateAlarmPresentation();
}

static void App_LvglUiOnChartValueChanged(lv_event_t *e)
{
  lv_obj_t *chart = lv_event_get_target_obj(e);
  uint32_t idx = lv_chart_get_pressed_point(chart);

  if((idx == LV_CHART_POINT_NONE) || (g_lbl_probe == NULL) || (g_ser_ch1 == NULL) || (g_ser_ch2 == NULL) || (g_chart_cursor == NULL)) {
    return;
  }

  {
    int32_t *y1 = lv_chart_get_series_y_array(chart, g_ser_ch1);
    int32_t *y2 = lv_chart_get_series_y_array(chart, g_ser_ch2);
    uint32_t sample_per_point = ADC_BLOCK_N / UI_POINT_COUNT;
    uint32_t sample_idx = idx * sample_per_point;
    uint32_t time_us = 0U;

    if(sample_per_point == 0U) {
      sample_per_point = 1U;
    }

    if(g_sample_rate_hz > 0U) {
      time_us = (uint32_t)((((uint64_t)sample_idx * 1000000ULL) + (g_sample_rate_hz / 2U)) / g_sample_rate_hz);
    }

    lv_chart_set_cursor_point(chart, g_chart_cursor, g_ser_ch1, idx);
    lv_label_set_text_fmt(g_lbl_probe,
                          "Probe[%lu]: CH1=%ld mV  CH2=%ld mV  t=%lu us",
                          (unsigned long)idx,
                          (long)y1[idx],
                          (long)y2[idx],
                          (unsigned long)time_us);
  }
}

static void App_LvglUiOnTimer(lv_timer_t *timer)
{
  uint32_t full_count = adc_task_full_cnt;
  bool level_changed = false;

  (void)timer;

  /* Use full-block snapshots only to avoid alternating torn-looking waveforms. */
  if(full_count != g_last_full_count) {
    g_metrics = App_LvglUiCollectMetricsFromBlock(ADC_BLOCK_N);
    level_changed = App_LvglUiUpdateAlarmState(g_metrics.raw_alarm_level);

    if(level_changed) {
      if(g_alarm_level == 0U) {
        App_LvglUiLogEvent("Alarm cleared");
      }
      else if(g_alarm_level == 1U) {
        App_LvglUiLogEvent("Alarm entered HIGH");
      }
      else {
        App_LvglUiLogEvent("Alarm entered HIGH HIGH");
      }
    }

    if(!g_wave_frozen) {
      App_LvglUiFeedChartFromBlock(g_metrics.block_offset);
      g_ui_refresh_count++;
    }
    g_last_full_count = full_count;
  }

  App_LvglUiUpdateFpsEstimate();

  if(g_alarm_level > 0U) {
    if(!g_alarm_ack) {
      g_alarm_flash_tick++;
      if(g_alarm_flash_tick >= UI_ALARM_FLASH_DIV) {
        g_alarm_flash_tick = 0U;
        g_alarm_flash_on = !g_alarm_flash_on;
      }
    }
    else {
      g_alarm_flash_tick = 0U;
      g_alarm_flash_on = true;
    }
  }
  else {
    g_alarm_flash_tick = 0U;
    g_alarm_flash_on = false;
  }

  if(g_alarm_ack_armed && ((uint32_t)(lv_tick_get() - g_ack_arm_tick_ms) > UI_ACK_ARM_TIMEOUT_MS)) {
    g_alarm_ack_armed = false;
    if(g_lbl_ack_btn != NULL) {
      lv_label_set_text(g_lbl_ack_btn, "Acknowledge");
    }
    App_LvglUiLogEvent("ACK arm timeout");
  }

  App_LvglUiUpdateStatusLabels();
  App_LvglUiUpdateAlarmPresentation();
}
