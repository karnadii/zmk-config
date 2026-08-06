/*
 * Copyright (c) 2026 Geulis ZMK Module Contributors
 * SPDX-License-Identifier: MIT
 *
 * Driver for `zmk,indicator-leds` — maps either a HID indicator bit
 * (Caps Lock, Num Lock, Scroll Lock, Compose, Kana) or an active layer
 * index to one or more GPIO LEDs defined as standard `gpio-leds` children.
 *
 * This is a backport of the `zmk,indicator-leds` driver that exists in
 * ZMK 4.x but is not present in ZMK v0.3.
 *
 * Each child of the `zmk,indicator-leds` node declares one indicator.
 * Exactly one of `indicator` or `layer` must be set.
 *
 *   indicators {
 *       compatible = "zmk,indicator-leds";
 *       caps_lock {
 *           compatible = "zmk,indicator-leds-entry";
 *           indicator = <1>;            // HID_INDICATOR_CAPS_LOCK
 *           leds = <&green_led>;
 *       };
 *       macos_active {
 *           compatible = "zmk,indicator-leds-entry";
 *           layer = <0>;
 *           leds = <&blue_led>;
 *       };
 *   };
 *
 * The `leds` phandles reference existing `gpio-leds` children (the same
 * ones bound by the standard Zephyr GPIO LED driver). The LED's GPio
 * spec is resolved at compile time via `GPIO_DT_SPEC_GET_BY_IDX`, then
 * driven directly with `gpio_pin_set_dt()` — no `led_on`/`led_off` indirection.
 *
 * A single shared event listener subscribes to
 * `zmk_hid_indicators_changed` (when CONFIG_ZMK_HID_INDICATORS=y) and
 * `zmk_layer_state_changed`; on either event it walks the static table
 * and turns each indicator's LEDs on or off.
 *
 * Per-entry LED count is fixed at INDICATOR_LEDS_MAX. If a child has
 * more, the extras are silently dropped (silent at compile time because
 * the driver is intentionally permissive).
 */

#define DT_DRV_COMPAT zmk_indicator_leds

#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include <zmk/event_manager.h>
#include <zmk/events/hid_indicators_changed.h>
#include <zmk/events/layer_state_changed.h>
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

static void set_entry(const struct indicator_entry *e, bool on) {
    for (uint8_t i = 0; i < e->led_count; i++) {
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

static void update_all(void) {
#if IS_ENABLED(CONFIG_ZMK_HID_INDICATORS)
    const zmk_hid_indicators_t hid = zmk_hid_indicators_get_current_profile();
#else
    const zmk_hid_indicators_t hid = 0;
#endif
    const zmk_keymap_layer_index_t top = zmk_keymap_highest_layer_active();

    for (size_t i = 0; i < entry_count; i++) {
        const struct indicator_entry *e = &entries[i];
        bool active = (e->hid_bit >= 0) ? ((hid & BIT(e->hid_bit)) != 0)
                                        : (top == e->layer);
        set_entry(e, active);
    }
}

static int indicator_leds_init(const struct device *dev) {
    ARG_UNUSED(dev);
    for (size_t i = 0; i < entry_count; i++) {
        configure_entry(&entries[i]);
    }
    update_all();
    return 0;
}

static int event_listener(const zmk_event_t *eh) {
    ARG_UNUSED(eh);
    update_all();
    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(indicator_leds_listener, event_listener);
#if IS_ENABLED(CONFIG_ZMK_HID_INDICATORS)
ZMK_SUBSCRIPTION(indicator_leds_listener, zmk_hid_indicators_changed);
#endif
ZMK_SUBSCRIPTION(indicator_leds_listener, zmk_layer_state_changed);

DEVICE_DT_INST_DEFINE(0, indicator_leds_init, NULL, NULL, NULL, POST_KERNEL,
                      CONFIG_APPLICATION_INIT_PRIORITY, NULL);
