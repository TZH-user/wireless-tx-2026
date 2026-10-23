#ifndef APP_BASEBAND_SPECTRUM_PENDING_H
#define APP_BASEBAND_SPECTRUM_PENDING_H

#include <stdint.h>

#define APP_BBSP_BAR_COUNT          41U
#define APP_BBSP_BAR_STEP_HZ        5000U
#define APP_BBSP_BAR_START_HZ      (-100000)
#define APP_BBSP_BAR_STOP_HZ        100000
#define APP_BBSP_CENTER_INDEX       20U

typedef struct
{
  uint8_t valid;
  uint8_t reserved[3];
  uint32_t block_count;
  uint32_t sample_rate_hz;
  uint32_t lo_hz;
  uint32_t carrier_hz;
  uint32_t update_tick_ms;
  uint16_t bars[APP_BBSP_BAR_COUNT];
  int32_t bin_hz[APP_BBSP_BAR_COUNT];
  uint32_t peak_hz;
  uint32_t peak_mag;
  uint32_t noise_floor;
  uint32_t dc_mag;
} app_baseband_spectrum_pending_status_t;

void app_bbsp_pending_init(uint32_t sample_rate_hz);
void app_bbsp_pending_process_block(const uint16_t *i_buf,
                                    const uint16_t *q_buf,
                                    uint32_t sample_cnt,
                                    uint32_t lo_hz,
                                    uint32_t carrier_hz);
void app_bbsp_pending_get_status(app_baseband_spectrum_pending_status_t *out);

#endif