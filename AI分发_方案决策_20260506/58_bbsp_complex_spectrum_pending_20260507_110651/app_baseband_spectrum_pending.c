#include "app_baseband_spectrum_pending.h"

#include <math.h>
#include <string.h>

#ifndef APP_BBSP_PENDING_PI
#define APP_BBSP_PENDING_PI 3.14159265358979323846f
#endif

static app_baseband_spectrum_pending_status_t g_pending;

static float app_bbsp_pending_bin_energy(const float *i_data,
                                         const float *q_data,
                                         uint32_t point_count,
                                         uint32_t sample_rate_hz,
                                         int32_t target_hz)
{
  float w = (2.0f * APP_BBSP_PENDING_PI * (float)target_hz) / (float)sample_rate_hz;
  float cw = cosf(w);
  float sw = sinf(w);
  float wr = 1.0f;
  float wi = 0.0f;
  float sum_r = 0.0f;
  float sum_i = 0.0f;

  for (uint32_t n = 0U; n < point_count; n++)
  {
    float xr = i_data[n];
    float xi = q_data[n];
    float next_wr = (wr * cw) - (wi * sw);
    float next_wi = (wr * sw) + (wi * cw);

    sum_r += (xr * wr) - (xi * wi);
    sum_i += (xr * wi) + (xi * wr);

    wr = next_wr;
    wi = next_wi;
  }

  return (sum_r * sum_r) + (sum_i * sum_i);
}

void app_bbsp_pending_init(uint32_t sample_rate_hz)
{
  memset(&g_pending, 0, sizeof(g_pending));
  g_pending.sample_rate_hz = sample_rate_hz;

  for (uint32_t i = 0U; i < APP_BBSP_BAR_COUNT; i++)
  {
    g_pending.bin_hz[i] = APP_BBSP_BAR_START_HZ + ((int32_t)i * (int32_t)APP_BBSP_BAR_STEP_HZ);
  }
}

void app_bbsp_pending_process_block(const uint16_t *i_buf,
                                    const uint16_t *q_buf,
                                    uint32_t sample_cnt,
                                    uint32_t lo_hz,
                                    uint32_t carrier_hz)
{
  (void)i_buf;
  (void)q_buf;
  (void)sample_cnt;
  (void)lo_hz;
  (void)carrier_hz;

  /*
   * Pending-only skeleton:
   * 1. decimate/select 256 or 512 points
   * 2. convert to centered float or fixed-point complex baseband
   * 3. evaluate APP_BBSP_BAR_COUNT target bins
   * 4. normalize/compress bars[] for UI
   * 5. update peak_hz / peak_mag / noise_floor / dc_mag
   */
}

void app_bbsp_pending_get_status(app_baseband_spectrum_pending_status_t *out)
{
  if (out != NULL)
  {
    *out = g_pending;
  }
}