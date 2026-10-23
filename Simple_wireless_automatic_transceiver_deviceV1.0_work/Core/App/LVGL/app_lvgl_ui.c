#include "app_lvgl_ui.h"

#include "lvgl.h"

static lv_obj_t *g_touch_status_label = NULL;
static uint32_t g_touch_click_count = 0U;

static lv_obj_t *App_LvglUiCreatePanel(lv_obj_t *parent);
static lv_obj_t *App_LvglUiCreateTitle(lv_obj_t *parent);
static lv_obj_t *App_LvglUiCreateSubtitle(lv_obj_t *parent, lv_obj_t *title);
static lv_obj_t *App_LvglUiCreateTouchButton(lv_obj_t *parent, lv_obj_t *subtitle);
static lv_obj_t *App_LvglUiCreateTouchStatus(lv_obj_t *parent, lv_obj_t *button);
static void App_LvglUiOnTouchTestClicked(lv_event_t *e);

void App_LvglUiInit(void)
{
  lv_obj_t *screen = lv_screen_active();
  lv_obj_t *panel = NULL;
  lv_obj_t *title = NULL;
  lv_obj_t *subtitle = NULL;
  lv_obj_t *touch_button = NULL;

  lv_obj_set_style_bg_color(screen, lv_color_hex(0x102030), 0);
  lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);

  panel = App_LvglUiCreatePanel(screen);
  title = App_LvglUiCreateTitle(panel);
  subtitle = App_LvglUiCreateSubtitle(panel, title);
  touch_button = App_LvglUiCreateTouchButton(panel, subtitle);
  g_touch_status_label = App_LvglUiCreateTouchStatus(panel, touch_button);

  g_touch_click_count = 0U;
}

static lv_obj_t *App_LvglUiCreatePanel(lv_obj_t *parent)
{
  lv_obj_t *panel = lv_obj_create(parent);

  lv_obj_set_size(panel, 500, 240);
  lv_obj_center(panel);
  lv_obj_set_style_bg_color(panel, lv_color_hex(0x1B2A41), 0);
  lv_obj_set_style_bg_opa(panel, LV_OPA_COVER, 0);
  lv_obj_set_style_border_color(panel, lv_color_hex(0x3A506B), 0);
  lv_obj_set_style_border_width(panel, 2, 0);
  lv_obj_set_style_radius(panel, 16, 0);
  lv_obj_set_style_shadow_width(panel, 0, 0);

  return panel;
}

static lv_obj_t *App_LvglUiCreateTitle(lv_obj_t *parent)
{
  lv_obj_t *title = lv_label_create(parent);

  lv_label_set_text(title, "LVGL 9.5.0 Running");
  lv_obj_set_style_text_color(title, lv_color_hex(0xFFFFFF), 0);
  lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 28);

  return title;
}

static lv_obj_t *App_LvglUiCreateSubtitle(lv_obj_t *parent, lv_obj_t *title)
{
  lv_obj_t *subtitle = lv_label_create(parent);

  lv_label_set_text(subtitle, "H743 RGB + FreeRTOS + LTDC");
  lv_obj_set_style_text_color(subtitle, lv_color_hex(0xB8C4D6), 0);
  lv_obj_align_to(subtitle, title, LV_ALIGN_OUT_BOTTOM_MID, 0, 14);

  return subtitle;
}

static lv_obj_t *App_LvglUiCreateTouchButton(lv_obj_t *parent, lv_obj_t *subtitle)
{
  lv_obj_t *button = lv_button_create(parent);
  lv_obj_t *button_text = lv_label_create(button);

  lv_obj_set_size(button, 180, 46);
  lv_obj_align_to(button, subtitle, LV_ALIGN_OUT_BOTTOM_MID, 0, 18);
  lv_obj_add_event_cb(button, App_LvglUiOnTouchTestClicked, LV_EVENT_CLICKED, NULL);

  lv_label_set_text(button_text, "Touch Test");
  lv_obj_center(button_text);

  return button;
}

static lv_obj_t *App_LvglUiCreateTouchStatus(lv_obj_t *parent, lv_obj_t *button)
{
  lv_obj_t *status = lv_label_create(parent);

  lv_label_set_text(status, "Touch count: 0");
  lv_obj_set_style_text_color(status, lv_color_hex(0xD7E3F4), 0);
  lv_obj_align_to(status, button, LV_ALIGN_OUT_BOTTOM_MID, 0, 14);

  return status;
}

static void App_LvglUiOnTouchTestClicked(lv_event_t *e)
{
  (void)e;

  g_touch_click_count++;
  if(g_touch_status_label != NULL) {
    lv_label_set_text_fmt(g_touch_status_label, "Touch count: %lu", (unsigned long)g_touch_click_count);
  }
}
