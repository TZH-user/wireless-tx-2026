#include "app_mod_detect.h"

#include <string.h>
#include <stdio.h>

#include "RtosTypes.h"

#define APP_MODDET_DPHI_HIST_BIN_COUNT 5U

typedef struct
{
  app_mod_detect_config_t config;
  app_mod_detect_status_t status;
  uint8_t mode_vote[APP_MODDET_MODE_PSK + 1U];
} app_mod_detect_ctx_t;

static app_mod_detect_ctx_t g_moddet;

static uint32_t app_moddet_abs_i64_to_u32(int64_t value)
{
  if (value < 0)
  {
    value = -value;
  }

  if (value > 0xFFFFFFFFLL)
  {
    return 0xFFFFFFFFUL;
  }

  return (uint32_t)value;
}

static uint32_t app_moddet_abs_diff_u64(uint64_t a, uint64_t b)
{
  uint64_t diff = (a > b) ? (a - b) : (b - a);

  if (diff > 0xFFFFFFFFULL)
  {
    return 0xFFFFFFFFUL;
  }

  return (uint32_t)diff;
}

static uint32_t app_moddet_percent_u32(uint32_t numerator, uint32_t denominator)
{
  if (denominator == 0U)
  {
    return 0U;
  }

  return (uint32_t)(((uint64_t)numerator * 100ULL) / denominator);
}

static uint32_t app_moddet_permille_u64(uint64_t numerator, uint64_t denominator)
{
  if (denominator == 0ULL)
  {
    return 0U;
  }

  return (uint32_t)((numerator * 1000ULL) / denominator);
}

static uint32_t app_moddet_div_round_u64(uint64_t numerator, uint64_t denominator)
{
  if (denominator == 0ULL)
  {
    return 0U;
  }

  return (uint32_t)((numerator + (denominator / 2ULL)) / denominator);
}

static uint32_t app_moddet_isqrt_u64(uint64_t value)
{
  uint64_t bit = 1ULL << 62;
  uint64_t root = 0ULL;

  while (bit > value)
  {
    bit >>= 2;
  }

  while (bit != 0ULL)
  {
    if (value >= (root + bit))
    {
      value -= root + bit;
      root = (root >> 1) + bit;
    }
    else
    {
      root >>= 1;
    }
    bit >>= 2;
  }

  if (root > 0xFFFFFFFFULL)
  {
    return 0xFFFFFFFFUL;
  }

  return (uint32_t)root;
}

static uint32_t app_moddet_max_u32(uint32_t a, uint32_t b)
{
  return (a > b) ? a : b;
}

static uint32_t app_moddet_count_bits_u32(uint32_t value)
{
  uint32_t count = 0U;

  while (value != 0U)
  {
    count += (value & 1U);
    value >>= 1U;
  }

  return count;
}

static uint16_t app_moddet_count_hist_peaks(const uint32_t *hist, uint32_t hist_len, uint32_t sample_cnt)
{
  uint16_t peak_count = 0U;
  uint32_t idx;
  uint32_t min_peak_count;

  if ((hist == 0) || (hist_len == 0U))
  {
    return 0U;
  }

  min_peak_count = (sample_cnt * APP_MODDET_HIST_PEAK_MIN_PERCENT) / 100U;
  if (min_peak_count == 0U)
  {
    min_peak_count = 1U;
  }

  for (idx = 0U; idx < hist_len; idx++)
  {
    uint32_t left = (idx == 0U) ? 0U : hist[idx - 1U];
    uint32_t right = (idx + 1U >= hist_len) ? 0U : hist[idx + 1U];

    if ((hist[idx] >= min_peak_count) &&
        (hist[idx] >= left) &&
        (hist[idx] >= right))
    {
      peak_count++;
    }
  }

  return peak_count;
}

static void app_moddet_set_default_config(app_mod_detect_config_t *config)
{
  config->sample_rate_hz = APP_MODDET_DEFAULT_SAMPLE_RATE_HZ;
  config->min_block_samples = 128U;
  config->reserved = 0U;
}

static uint32_t app_moddet_rate_from_edges(uint32_t edge_count, uint32_t sample_cnt, uint32_t sample_rate_hz)
{
  if ((edge_count == 0U) || (sample_cnt == 0U) || (sample_rate_hz == 0U))
  {
    return 0U;
  }

  return app_moddet_div_round_u64((uint64_t)edge_count * (uint64_t)sample_rate_hz,
                                  (uint64_t)sample_cnt * 2ULL);
}

static uint32_t app_moddet_am_depth_pm(uint64_t env_min, uint64_t env_max)
{
  uint32_t min_amp = app_moddet_isqrt_u64(env_min);
  uint32_t max_amp = app_moddet_isqrt_u64(env_max);
  uint32_t sum_amp = min_amp + max_amp;

  if ((max_amp <= min_amp) || (sum_amp == 0U))
  {
    return 0U;
  }

  return (uint32_t)(((uint64_t)(max_amp - min_amp) * 1000ULL) / (uint64_t)sum_amp);
}

static void app_moddet_update_stable_mode(app_mod_detect_status_t *st)
{
  uint32_t idx;
  uint8_t best_vote = 0U;
  app_mod_detect_mode_t best_mode = st->mode;
  uint32_t total_vote = 0U;

  for (idx = 0U; idx <= (uint32_t)APP_MODDET_MODE_PSK; idx++)
  {
    if (g_moddet.mode_vote[idx] > 0U)
    {
      g_moddet.mode_vote[idx]--;
    }
  }

  if ((uint32_t)st->mode <= (uint32_t)APP_MODDET_MODE_PSK)
  {
    uint32_t vote = (uint32_t)g_moddet.mode_vote[st->mode] + 6U;
    g_moddet.mode_vote[st->mode] = (vote > 60U) ? 60U : (uint8_t)vote;
  }

  for (idx = 0U; idx <= (uint32_t)APP_MODDET_MODE_PSK; idx++)
  {
    total_vote += g_moddet.mode_vote[idx];
    if (g_moddet.mode_vote[idx] > best_vote)
    {
      best_vote = g_moddet.mode_vote[idx];
      best_mode = (app_mod_detect_mode_t)idx;
    }
  }

  st->stable_mode = best_mode;
  st->stable_confidence_percent = (uint16_t)app_moddet_percent_u32(best_vote, total_vote);
}

static uint8_t app_moddet_is_single_sign_dominant(const app_mod_detect_status_t *st)
{
  uint16_t major = (st->positive_freq_percent > st->negative_freq_percent) ?
                   st->positive_freq_percent : st->negative_freq_percent;
  uint16_t minor = (st->positive_freq_percent > st->negative_freq_percent) ?
                   st->negative_freq_percent : st->positive_freq_percent;

  return ((major >= APP_MODDET_SIGN_DOMINANT_PERCENT) &&
          (minor <= APP_MODDET_SIGN_MINOR_PERCENT)) ? 1U : 0U;
}

static app_mod_detect_mode_t app_moddet_classify(const app_mod_detect_status_t *st)
{
  uint8_t single_sign;

  if (st->carrier_present == 0U)
  {
    return APP_MODDET_MODE_NO_CARRIER;
  }

  if ((st->env_variation_pm >= APP_MODDET_AM_ENV_PM_THRESHOLD) &&
      (((st->env_edge_pm >= APP_MODDET_ASK_MIN_EDGE_PM) &&
        (st->freq_activity >= APP_MODDET_ASK_MIN_FREQ_PM)) ||
       ((st->env_variation_pm >= APP_MODDET_ASK_STRONG_ENV_PM) &&
        (st->env_edge_pm >= APP_MODDET_ASK_STRONG_EDGE_PM))))
  {
    return APP_MODDET_MODE_ASK;
  }

  if (st->env_variation_pm >= APP_MODDET_AM_ENV_PM_THRESHOLD)
  {
    return APP_MODDET_MODE_AM;
  }

  single_sign = app_moddet_is_single_sign_dominant(st);

  if ((single_sign != 0U) &&
      (st->freq_activity <= APP_MODDET_PSK_MAX_FREQ_PM) &&
      ((st->freq_activity >= APP_MODDET_PSK_MIN_FREQ_PM) ||
       (st->env_edge_pm >= APP_MODDET_PSK_MIN_EDGE_PM)) &&
      (st->psk_jump_pm >= APP_MODDET_PSK_JUMP_PM_THRESHOLD) &&
      (st->dphi_hist_peak_count <= APP_MODDET_PSK_MAX_HIST_PEAKS) &&
      (st->env_variation_pm < APP_MODDET_PSK_MAX_ENV_PM))
  {
    return APP_MODDET_MODE_PSK;
  }

  if ((single_sign != 0U) &&
      (st->freq_activity >= APP_MODDET_FSK_MIN_FREQ_PM) &&
      (st->psk_jump_pm < APP_MODDET_PSK_JUMP_PM_THRESHOLD) &&
      (st->env_variation_pm < APP_MODDET_PSK_MAX_ENV_PM))
  {
    return APP_MODDET_MODE_FSK;
  }

  if (st->freq_activity >= APP_MODDET_FREQ_ACTIVITY_THRESHOLD)
  {
    return APP_MODDET_MODE_FM;
  }

  return APP_MODDET_MODE_CW;
}
void app_mod_detect_init(const app_mod_detect_config_t *config)
{
  memset(&g_moddet, 0, sizeof(g_moddet));

  if (config != 0)
  {
    g_moddet.config = *config;
  }
  else
  {
    app_moddet_set_default_config(&g_moddet.config);
  }
}

void app_mod_detect_process_iq_block(const uint16_t *i_buf, const uint16_t *q_buf, uint32_t sample_cnt)
{
  uint64_t sum_i = 0ULL;
  uint64_t sum_q = 0ULL;
  uint64_t power_sum = 0ULL;
  uint64_t env_dev_sum = 0ULL;
  uint64_t env_prev_mag2 = 0ULL;
  int64_t freq_metric_sum = 0LL;
  uint64_t freq_abs_sum = 0ULL;
  uint32_t positive_freq_cnt = 0U;
  uint32_t negative_freq_cnt = 0U;
  uint32_t psk_jump_cnt = 0U;
  uint32_t env_edge_cnt = 0U;
  uint32_t env_transition_cnt = 0U;
  uint32_t freq_sign_transition_cnt = 0U;
  uint32_t env_level_mask = 0U;
  uint32_t dphi_hist[APP_MODDET_DPHI_HIST_BIN_COUNT];
  uint32_t pair_cnt;
  uint32_t idx;
  int32_t mean_i;
  int32_t mean_q;
  int32_t prev_i = 0;
  int32_t prev_q = 0;
  uint64_t mean_power;
  uint64_t env_min = 0ULL;
  uint64_t env_max = 0ULL;
  uint64_t env_span;
  uint64_t env_mid;
  uint64_t env_hyst;
  uint32_t env_edge_threshold;
  uint8_t env_state = 0U;
  uint8_t env_state_valid = 0U;
  int8_t prev_freq_sign = 0;
  app_mod_detect_status_t st;

  if ((i_buf == 0) || (q_buf == 0) || (sample_cnt < g_moddet.config.min_block_samples))
  {
    return;
  }

  for (idx = 0U; idx < sample_cnt; idx++)
  {
    sum_i += i_buf[idx];
    sum_q += q_buf[idx];
  }

  mean_i = (int32_t)(sum_i / sample_cnt);
  mean_q = (int32_t)(sum_q / sample_cnt);

  memset(&dphi_hist[0], 0, sizeof(dphi_hist));

  for (idx = 0U; idx < sample_cnt; idx++)
  {
    int32_t ci = (int32_t)i_buf[idx] - mean_i;
    int32_t cq = (int32_t)q_buf[idx] - mean_q;
    uint64_t mag2 = (uint64_t)(((int64_t)ci * (int64_t)ci) + ((int64_t)cq * (int64_t)cq));

    power_sum += mag2;
    if (idx == 0U)
    {
      env_min = mag2;
      env_max = mag2;
    }
    else
    {
      if (mag2 < env_min)
      {
        env_min = mag2;
      }
      if (mag2 > env_max)
      {
        env_max = mag2;
      }
    }
  }

  mean_power = power_sum / sample_cnt;
  env_span = env_max - env_min;
  env_mid = env_min + (env_span / 2ULL);
  env_hyst = env_span / 16ULL;
  env_edge_threshold = app_moddet_max_u32((uint32_t)(env_span / 8ULL),
                                          app_moddet_max_u32((uint32_t)(mean_power / 64ULL), 1U));

  for (idx = 0U; idx < sample_cnt; idx++)
  {
    int32_t ci = (int32_t)i_buf[idx] - mean_i;
    int32_t cq = (int32_t)q_buf[idx] - mean_q;
    uint64_t mag2 = (uint64_t)(((int64_t)ci * (int64_t)ci) + ((int64_t)cq * (int64_t)cq));
    uint32_t env_bin;

    env_dev_sum += app_moddet_abs_diff_u64(mag2, mean_power);

    if (env_span == 0ULL)
    {
      env_bin = 0U;
    }
    else
    {
      env_bin = (uint32_t)(((mag2 - env_min) * APP_MODDET_ENV_LEVEL_BINS) / (env_span + 1ULL));
      if (env_bin >= APP_MODDET_ENV_LEVEL_BINS)
      {
        env_bin = APP_MODDET_ENV_LEVEL_BINS - 1U;
      }
    }
    env_level_mask |= (1UL << env_bin);

    if (idx > 0U)
    {
      int64_t cross = ((int64_t)ci * (int64_t)prev_q) - ((int64_t)cq * (int64_t)prev_i);
      int64_t dot = ((int64_t)ci * (int64_t)prev_i) + ((int64_t)cq * (int64_t)prev_q);
      uint32_t abs_cross = app_moddet_abs_i64_to_u32(cross);
      uint32_t cross_pm = app_moddet_permille_u64((uint64_t)abs_cross, mean_power);
      uint32_t hist_bin = 2U;
      int8_t freq_sign = 0;

      if (app_moddet_abs_diff_u64(mag2, env_prev_mag2) >= env_edge_threshold)
      {
        env_edge_cnt++;
      }

      freq_metric_sum += cross;
      freq_abs_sum += abs_cross;

      if (cross > 0)
      {
        positive_freq_cnt++;
        freq_sign = 1;
      }
      else if (cross < 0)
      {
        negative_freq_cnt++;
        freq_sign = -1;
      }

      if (freq_sign != 0)
      {
        if ((prev_freq_sign != 0) && (freq_sign != prev_freq_sign))
        {
          freq_sign_transition_cnt++;
        }
        prev_freq_sign = freq_sign;
      }

      if (dot < 0)
      {
        psk_jump_cnt++;
      }

      if (cross_pm <= APP_MODDET_DPHI_ZERO_PM_THRESHOLD)
      {
        hist_bin = 2U;
      }
      else if (cross < 0)
      {
        hist_bin = (cross_pm >= APP_MODDET_DPHI_STRONG_PM_THRESHOLD) ? 0U : 1U;
      }
      else
      {
        hist_bin = (cross_pm >= APP_MODDET_DPHI_STRONG_PM_THRESHOLD) ? 4U : 3U;
      }
      dphi_hist[hist_bin]++;
    }

    if (env_span != 0ULL)
    {
      uint8_t next_env_state = env_state;

      if (mag2 > (env_mid + env_hyst))
      {
        next_env_state = 1U;
      }
      else if (mag2 < ((env_mid > env_hyst) ? (env_mid - env_hyst) : 0ULL))
      {
        next_env_state = 0U;
      }

      if (env_state_valid == 0U)
      {
        env_state = next_env_state;
        env_state_valid = 1U;
      }
      else if (next_env_state != env_state)
      {
        env_transition_cnt++;
        env_state = next_env_state;
      }
    }

    prev_i = ci;
    prev_q = cq;
    env_prev_mag2 = mag2;
  }

  pair_cnt = sample_cnt - 1U;

  memset(&st, 0, sizeof(st));
  st.block_count = g_moddet.status.block_count + 1U;
  st.ac_power = (uint32_t)mean_power;
  st.carrier_present = (st.ac_power >= APP_MODDET_MIN_AC_POWER) ? 1U : 0U;
  st.env_variation_pm = app_moddet_permille_u64(env_dev_sum / sample_cnt, mean_power);
  st.env_edge_pm = app_moddet_permille_u64(env_edge_cnt, pair_cnt);
  st.freq_activity = app_moddet_permille_u64(freq_abs_sum / pair_cnt, mean_power);
  st.freq_bias = (int32_t)(freq_metric_sum / (int64_t)pair_cnt);
  st.fsk_balance_pm = app_moddet_permille_u64((uint64_t)(positive_freq_cnt + negative_freq_cnt), pair_cnt);
  st.psk_jump_pm = app_moddet_permille_u64(psk_jump_cnt, pair_cnt);
  st.modulation_rate_hz = app_moddet_rate_from_edges(env_transition_cnt, sample_cnt, g_moddet.config.sample_rate_hz);
  st.am_depth_pm = app_moddet_am_depth_pm(env_min, env_max);
  st.fm_deviation_hz = app_moddet_div_round_u64((uint64_t)st.freq_activity *
                                                (uint64_t)g_moddet.config.sample_rate_hz,
                                                6283ULL);
  st.fsk_shift_hz = st.fm_deviation_hz;
  st.env_level_count = (uint16_t)app_moddet_count_bits_u32(env_level_mask);
  st.dphi_hist_peak_count = app_moddet_count_hist_peaks(&dphi_hist[0],
                                                        APP_MODDET_DPHI_HIST_BIN_COUNT,
                                                        pair_cnt);
  st.positive_freq_percent = (uint16_t)app_moddet_percent_u32(positive_freq_cnt, pair_cnt);
  st.negative_freq_percent = (uint16_t)app_moddet_percent_u32(negative_freq_cnt, pair_cnt);
  st.mode = app_moddet_classify(&st);
  if ((st.mode == APP_MODDET_MODE_FM) || (st.mode == APP_MODDET_MODE_FSK))
  {
    st.modulation_rate_hz = app_moddet_rate_from_edges(freq_sign_transition_cnt,
                                                       sample_cnt,
                                                       g_moddet.config.sample_rate_hz);
  }
  else if (st.mode == APP_MODDET_MODE_PSK)
  {
    st.modulation_rate_hz = app_moddet_div_round_u64((uint64_t)psk_jump_cnt *
                                                     (uint64_t)g_moddet.config.sample_rate_hz,
                                                     (uint64_t)pair_cnt);
  }
  app_moddet_update_stable_mode(&st);

  g_moddet.status = st;

#if (APP_MODDET_UART_TRACE_ENABLE != 0U)
  if ((g_uart_mode == UART_MODE_LOG) &&
      ((APP_MODDET_TRACE_DECIMATION_BLOCKS == 0U) ||
       ((st.block_count % APP_MODDET_TRACE_DECIMATION_BLOCKS) == 0U)))
  {
    char line[125];
    int n = snprintf(line,
                     sizeof(line),
                     "mod,mode=%s,stable=%s,conf=%u,rate=%lu,depth=%lu,dev=%lu,shift=%lu\r\n",
                     app_mod_detect_mode_name(st.mode),
                     app_mod_detect_mode_name(st.stable_mode),
                     (unsigned)st.stable_confidence_percent,
                     (unsigned long)st.modulation_rate_hz,
                     (unsigned long)st.am_depth_pm,
                     (unsigned long)st.fm_deviation_hz,
                     (unsigned long)st.fsk_shift_hz);
    if ((n > 0) && ((size_t)n < sizeof(line)))
    {
      print_queue_send_log(line);
    }

    n = snprintf(line,
                 sizeof(line),
                 "ui,mode=%s,inst=%s,conf=%u,rate=%lu,depth=%lu,dev=%lu,shift=%lu\r\n",
                 app_mod_detect_mode_name(st.stable_mode),
                 app_mod_detect_mode_name(st.mode),
                 (unsigned)st.stable_confidence_percent,
                 (unsigned long)st.modulation_rate_hz,
                 (unsigned long)st.am_depth_pm,
                 (unsigned long)st.fm_deviation_hz,
                 (unsigned long)st.fsk_shift_hz);
    if ((n > 0) && ((size_t)n < sizeof(line)))
    {
      print_queue_send_log(line);
    }
  }
#endif
}

void app_mod_detect_get_status(app_mod_detect_status_t *status_out)
{
  if (status_out == 0)
  {
    return;
  }

  *status_out = g_moddet.status;
}

const char *app_mod_detect_mode_name(app_mod_detect_mode_t mode)
{
  switch (mode)
  {
    case APP_MODDET_MODE_NO_CARRIER:
      return "NO_CARRIER";
    case APP_MODDET_MODE_CW:
      return "CW";
    case APP_MODDET_MODE_AM:
      return "AM";
    case APP_MODDET_MODE_ASK:
      return "ASK";
    case APP_MODDET_MODE_FM:
      return "FM";
    case APP_MODDET_MODE_FSK:
      return "FSK";
    case APP_MODDET_MODE_PSK:
      return "PSK";
    case APP_MODDET_MODE_UNKNOWN:
    default:
      return "UNKNOWN";
  }
}
