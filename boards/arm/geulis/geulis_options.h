/*
 * Copyright (c) 2026 Ujang Karnadi
 * SPDX-License-Identifier: MIT
 *
 * Geulis board feature toggles — single source of truth for what
 * hardware is enabled in the compiled firmware.
 *
 * This header is `#include`d by `boards/arm/geulis/geulis.dts` BEFORE
 * the DTS preprocessor runs. Edit values here (0 or 1) to toggle
 * features. After changing, rebuild with `docker build.sh --clean`.
 *
 * IMPORTANT: when you set a feature to 0 here, also disable the matching
 * GEULIS_DRIVER_* Kconfig in `geulis_defconfig` (or via `geulis.conf`) so
 * that the driver source isn't compiled. Otherwise the driver will be
 * present but no device tree node will reference it.
 */

#ifndef GEULIS_OPTIONS_H_
#define GEULIS_OPTIONS_H_

/* --- Hardware presence ----------------------------------------------------- */
/* Set to 0 to remove the matching hardware from the devicetree. */

/* Top encoder (P0.26 / P0.06). Default rotation axis for media
 * volume. Always enabled — the `sensors` node anchors on this. */
#define GEULIS_ENCODER_TOP_ON    1

/* Middle encoder (P0.08 / P0.27). The PCB pads are exposed even if the
 * encoder isn't populated — leave this ON so the user can solder an EC11
 * in later without re-flashing. */
#define GEULIS_ENCODER_MID_ON    1

/* Bottom encoder (P1.08 / P0.11). The PCB pads are exposed even if the
 * encoder isn't populated — leave this ON so the user can solder an EC11
 * in later without re-flashing. */
#define GEULIS_ENCODER_BOT_ON    1

/* 18-LED WS2812 strip on SPI3 (P0.05). */
#define GEULIS_RGB_UNDERGLOW_ON  1

/* SSD1306 128x32 OLED on I2C0 (SDA = P0.15, SCL = P0.17). */
#define GEULIS_OLED_ON           1

#endif /* GEULIS_OPTIONS_H_ */
