/*
 * Copyright (c) 2026 Geulis ZMK Module Contributors
 * SPDX-License-Identifier: MIT
 *
 * Driver for `zmk,indicator-leds` — backport of the ZMK 4.x driver for
 * ZMK v0.3 (Zephyr 3.5).
 *
 * Modeled after the upstream main-branch implementation at
 * app/src/indicators/indicator_leds.c. Subscribes to the four events
 * that can change LED state, coalesces them into a deferred work item,
 * and reads the current HID indicator state to drive the LEDs.
 *
 * Design note: upstream uses the Zephyr LED API (`struct led_dt_spec`)
 * which is only available in Zephyr 3.6+. We use direct GPIO calls
 * (`gpio_pin_set_dt`) since v0.3 ships Zephyr 3.5.
 *
 * Each child of the `zmk,indicator-leds` node declares one indicator.
 * Exactly one of `indicator` or `layer` must be set (layer indicator is
 * a Geulis-specific extension; upstream only supports HID indicators).
 *
 *   indicators {
 *       compatible = "zmk,indicator-leds";
 *       caps_lock {
 *           compatible = "zmk,indicator-leds-entry";
 *           indicator = <2>;            // HID_INDICATOR_CAPS_LOCK
 *           leds = <&green_led>;
 *       };
 *       macos_active {
 *           compatible = "zmk,indicator-leds-entry";
 *           layer = <0>;
 *           leds = <&blue_led>;
 *       };
 *   };
 *
 * Known limitation: on hosts that don't echo the HID indicator report
 * back to the keyboard (some Windows installs), the Caps Lock LED will
 * not track state. This is the same limitation upstream ZMK has — the
 * hardware protocol requires the host to send the indicator update.
 */

#define DT_DRV_COMPAT zmk_indicator_leds

#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include <zmk/event_manager.h>
#include <zmk/activity.h>
#include <zmk/events/activity_state_changed.h>
#include <zmk/events/endpoint_changed.h>
#include <zmk/events/hid_indicators_changed.h>
#include <zmk/events/layer_state_changed.h>
#include <zmk/events/usb_conn_state_changed.h>
#include <zmk/hid_indicators.h>
#include <zmk/keymap.h>

LOG_MODULE_REGISTER(zmk_indicator_leds, CONFIG_ZMK_LOG_LEVEL);

#define INDICATOR_LEDS_MAX 4

struct indicator_entry {
    int8_t hid_bit; /* -1 = layer indicator */
    int8_t layer;   /* -1 = HID indicator */
    uint8_t led_count;
    struct gpio_dt_spec leds[INDICATOR_LEDS_MAX];
};

#define INDICATOR_LEDS_SPEC(node_id, prop, elem_idx)                          \
    GPIO_DT_SPEC_GET_BY_IDX(DT_PHANDLE_BY_IDX(node_id, prop, elem_idx), gpios, 0)

#define ENTRY_FROM_CHILD(node_id)                                               \
    {                                                                           \
        .hid_bit = COND_CODE_1(DT_NODE_HAS_PROP(node_id, indicator),            \
                               (DT_PROP(node_id, indicator)), (-1)),            \
        .layer = COND_CODE_1(DT_NODE_HAS_PROP(node_id, layer),                  \
                             (DT_PROP(node_id, layer)), (-1)),                  \
        .led_count = MIN(DT_PROP_LEN(node_id, leds), INDICATOR_LEDS_MAX),       \
        .leds = {                                                               \
            DT_FOREACH_PROP_ELEM_SEP(node_id, leds, INDICATOR_LEDS_SPEC, (,))   \
        },                                                                      \
    },

static const struct indicator_entry entries[] = {
    DT_FOREACH_CHILD(DT_INST(0, zmk_indicator_leds), ENTRY_FROM_CHILD)
};

static const size_t entry_count = ARRAY_SIZE(entries);

/* Track the current LED state so we can skip redundant GPIO calls — multiple
 * events in the same work-item invocation may not all change any LED value.
 */
static bool led_state[INDICATOR_LEDS_MAX * 8]; /* rows * leds per row cap */

static void set_entry(const struct indicator_entry *e, bool on, size_t entry_index) {
    for (uint8_t i = 0; i < e->led_count; i++) {
        const size_t flat = entry_index * INDICATOR_LEDS_MAX + i;
        if (led_state[flat] == on) {
            continue;
        }
        led_state[flat] = on;
        int rc = gpio_pin_set_dt(&e->leds[i], on ? 1 : 0);
        if (rc < 0) {
            LOG_WRN("gpio_pin_set_dt failed (rc=%d)", rc);
        }
    }
}

static void configure_entry(const struct indicator_entry *e) {
    for (uint8_t i = 0; i < e->led_count; i++) {
        if (!gpio_is_ready_dt(&e->leds[i])) {
            LOG_WRN("LED GPIO device not ready");
            continue;
        }
        int rc = gpio_pin_configure_dt(&e->leds[i], GPIO_OUTPUT_INACTIVE);
        if (rc < 0) {
            LOG_WRN("gpio_pin_configure_dt failed (rc=%d)", rc);
        }
    }
}

static void refresh_indicators(void) {
#if IS_ENABLED(CONFIG_ZMK_HID_INDICATORS)
    const zmk_hid_indicators_t hid = zmk_hid_indicators_get_current_profile();
#else
    const zmk_hid_indicators_t hid = 0;
#endif
    const zmk_keymap_layer_index_t top = zmk_keymap_highest_layer_active();

    for (size_t i = 0; i < entry_count; i++) {
        const struct indicator_entry *e = &entries[i];
        bool active;
        if (e->hid_bit >= 0) {
            active = (hid & BIT(e->hid_bit)) != 0;
        } else {
            active = (top == e->layer);
        }
        set_entry(e, active, i);
    }
}

static void update_all_indicators(struct k_work *work) {
    ARG_UNUSED(work);
    LOG_DBG("Updating indicator LEDs");
    refresh_indicators();
}

/* Coalesce events: many events may fire for a single state change
 * (e.g. endpoint_changed triggers hid_indicators_changed), so we
 * defer the update to a work item and only update once per batch.
 */
static K_WORK_DEFINE(update_all_indicators_work, update_all_indicators);

static int event_listener(const zmk_event_t *eh) {
    ARG_UNUSED(eh);
    k_work_submit(&update_all_indicators_work);
    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(indicator_leds_listener, event_listener);
#if IS_ENABLED(CONFIG_ZMK_HID_INDICATORS)
ZMK_SUBSCRIPTION(indicator_leds_listener, zmk_hid_indicators_changed);
#endif
ZMK_SUBSCRIPTION(indicator_leds_listener, zmk_activity_state_changed);
ZMK_SUBSCRIPTION(indicator_leds_listener, zmk_usb_conn_state_changed);
ZMK_SUBSCRIPTION(indicator_leds_listener, zmk_endpoint_changed);
ZMK_SUBSCRIPTION(indicator_leds_listener, zmk_layer_state_changed);

static int indicator_leds_init(const struct device *dev) {
    ARG_UNUSED(dev);
    for (size_t i = 0; i < entry_count; i++) {
        configure_entry(&entries[i]);
    }
    refresh_indicators();
    return 0;
}

DEVICE_DT_INST_DEFINE(0, indicator_leds_init, NULL, NULL, NULL, POST_KERNEL,
                      CONFIG_APPLICATION_INIT_PRIORITY, NULL);
