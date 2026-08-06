# Firmware for my [Geulis Keyboard](https://github.com/karnadii/geulis/)
![alt text](https://github.com/karnadii/geulis/blob/main/images/geulis_keyboard_acrylic_case_2021-Jun-04_11-50-24AM-000_CustomizedView44178749806.png?raw=true)

ZMK **main-branch** user-config repository for the Geulis — a single-piece
Alice-style keyboard built on the nRF52840, with three EC11 rotary encoders
and an optional WS2812 underglow strip.

> **Status: this branch is the active migration target.** The board structure
> has been ported to ZMK main's HWMv2 (Hardware Model v2) variant scheme.
> All three firmware variants compile cleanly. The `zmk,indicator-leds`
> node is intentionally absent — see the LED status note below.

## Keymap
![keymap](/keymap-drawer/geulis.svg)

## Building the firmware

All firmware variants are built inside a Docker container that wraps the
upstream `zmkfirmware/zmk-build-arm:stable` toolchain. You do not need a
local Zephyr / ZMK / west installation on your host.

### Prerequisites

- Docker with the Compose plugin (`docker compose version`)
- A working USB connection if you plan to flash (UF2 bootloader)

### One-time setup

Build the local image (pulls `zmkfirmware/zmk-build-arm:stable`):

```bash
docker compose -f docker/docker-compose.yml build
```

The first build pulls ~1 GB of toolchain. Subsequent builds reuse the
cached image.

### Build the firmware variants

The repository builds three artifacts (`.bin` / `.uf2`):

| Artifact | Command | Purpose |
| --- | --- | --- |
| `geulis-zmk-studio` | `./docker/build.sh --studio` | Default. ZMK Studio over USB. |
| `geulis-zmk-logging` | `./docker/build.sh --logging` | USB CDC logging for debugging. |
| `geulis-zmk-reset-settings` | `./docker/build.sh --reset` | Factory-reset firmware (clears bonding, RGB, etc.). |

```bash
# Build the Studio variant (default)
docker compose -f docker/docker-compose.yml run --rm build ./docker/build.sh --studio

# Build the logging variant
docker compose -f docker/docker-compose.yml run --rm build ./docker/build.sh --logging

# Build the reset-settings variant
docker compose -f docker/docker-compose.yml run --rm build ./docker/build.sh --reset
```

Each invocation:

1. Copies the local `config/` directory into a named docker volume
   (`zmk_workspace_cache`, mounted at `/zmk-workspace`) so west's
   `zephyr/`, `modules/`, `zmk/` checkouts don't clobber the
   bind-mounted repo (which would overwrite `zephyr/module.yml`).
2. Runs `west init` + `west update --fetch-opt=--filter=tree:0` to fetch
   Zephyr + ZMK main (≈5 min on first run; cached afterward).
3. Runs `west zephyr-export` and then `west build -s zmk/app -b geulis/nrf52840/zmk`
   with `-DZMK_EXTRA_MODULES=/workspace` so the
   `boards/karnadii/geulis/` board definition is registered.
4. Copies the resulting `.bin` to `./firmware/` on the host.

The named volume persists the ZMK/Zephyr checkouts between runs, so the
second and subsequent builds only re-compile changed source.

### Other commands

```bash
# Wipe the build cache (forces a full rebuild from scratch)
docker compose -f docker/docker-compose.yml run --rm build ./docker/build.sh --clean

# Drop into a shell inside the container for ad-hoc west invocations
docker compose -f docker/docker-compose.yml run --rm build ./docker/build.sh --shell

# Wipe the west workspace cache and force west to fetch ZMK from scratch
docker compose -f docker/docker-compose.yml down -v
```

### Flashing

After `docker build.sh` finishes, the `.bin` lands in `./firmware/` on
your host:

```
firmware/geulis-zmk-studio.bin
firmware/geulis-zmk-logging.bin
firmware/geulis-zmk-reset-settings.bin
```

To flash the Geulis:

1. Put the Geulis into bootloader mode — double-tap the reset button,
   or use the `&bootloader` binding or `<BOOT>` combo on the keyboard.
2. The host mounts a new USB drive labelled `GEULIS`.
3. Copy the `.bin` file onto that drive:
   ```bash
   cp firmware/geulis-zmk-studio.bin /media/$USER/GEULIS/
   ```
   (or just drag-and-drop in a file manager; the bootloader accepts both
   `.uf2` and `.bin` UF2-style firmware blobs.)
4. The Geulis reboots automatically after ~2 seconds.

To factory-reset the device (clear saved Bluetooth bonds, RGB settings,
etc.), flash the `geulis-zmk-reset-settings` artifact and then re-flash
the Studio variant.

## Hardware features

- **Three EC11 rotary encoders** (top, middle, bottom). All three are
  enabled in firmware by default so a user can solder one in
  (or swap one out) without re-flashing.
- **18-LED WS2812 RGB underglow** driven via SPI3 (P0.05).
  Brightness is capped at **70%** by default — ZMK's `BRT_MAX` is in
  percent, and 70% on 18 LEDs keeps the strip under ~300 mA so the USB
  data lines don't brown-out when the host port is marginal.
- **SSD1306 128x32 OLED** on I2C0 (P0.15 SDA, P0.17 SCL) at address
  0x3C. ZMK's built-in status screen shows the active layer, battery
  percentage, output (USB/BLE), and WPM. Selected by default via
  `CONFIG_GEULIS_DRIVER_OLED=y` in `boards/karnadii/geulis/Kconfig.geulis`.

### LED indicator status

The `zmk,indicator-leds` node is **not** declared in this branch's DTS.
On ZMK main + Zephyr 4.1, the upstream `app/src/indicators/indicator_leds.c`
has a macro `LED_DT_SPEC_GET_BY_IDX` whose expansion is rejected by the
preprocessor under gcc -std=c11 -Wfatal-errors. The fix is expected to
land upstream; until then, both the Caps Lock LED and the macOS-layer
LED are disabled on this branch.

The `boards/karnadii/geulis/geulis_nrf52840_zmk.dts` includes a comment
block explaining the situation. To restore the LEDs after upstream
fixes the macro, uncomment the `indicators { ... }` block in that DTS
(see AGENTS.md "Branches" for the migration plan).

See `AGENTS.md` for hardware specs, keymap conventions, and a full
list of build / flash gotchas.

## Toggling hardware features

Each optional feature has two layers of configuration that must agree
to disable it at compile time. The DTS layer strips the device tree
node; the Kconfig layer strips the driver source. Setting only one
layer results in a build error (e.g. `A zmk,underglow chosen node must
be declared`).

### 1. OLED display (SSD1306 128x32 on I2C0)

DTS — `boards/karnadii/geulis/geulis_options.h`:
```c
// Comment out (or set to 0) the OLED macro to remove the display node.
/* #define GEULIS_OLED_ON  1 */
```

Kconfig — `boards/karnadii/geulis/Kconfig.geulis`:
```
# CONFIG_GEULIS_DRIVER_OLED is not set
```
(Or comment out the `select SSD1306` / `select ZMK_DISPLAY` lines in the
Kconfig.)

The DTS `&i2c0 { ... ssd1306@3c { ... } }` block and the
`chosen/zephyr,display = &oled` line stay declared; only the LVGL display
driver code and the ZMK status screen code are dropped. Saves about
120 KB of flash.

### 2. Rotary encoders (top, middle, bottom — EC11)

DTS — `boards/karnadii/geulis/geulis_options.h`:
```c
// Each defaults to 1; set to 0 to remove that encoder's DTS node.
#define GEULIS_ENCODER_TOP_ON  1   // top encoder (always required — anchors sensors array)
#define GEULIS_ENCODER_MID_ON   0   // set to 1 if the middle encoder is soldered
#define GEULIS_ENCODER_BOT_ON   0   // set to 1 if the bottom encoder is soldered
```

Kconfig — `boards/karnadii/geulis/geulis_defconfig`:
```
CONFIG_EC11=y
CONFIG_EC11_TRIGGER_GLOBAL_THREAD=y
```
(Leave both enabled; the EC11 driver is shared across all three encoders.
To disable encoders entirely, also set `CONFIG_GEULIS_DRIVER_ENCODER=n` in
`boards/karnadii/geulis/Kconfig.geulis`.)

At least one of `GEULIS_ENCODER_TOP_ON` / `_MID_ON` / `_BOT_ON` must be `1`
(the `sensors` node anchors on whichever is enabled first, defaulting to
top). A `#error` enforces this at compile time.

### 3. RGB underglow (WS2812 18-LED strip on SPI3)

DTS — `boards/karnadii/geulis/geulis_options.h`:
```c
#define GEULIS_RGB_UNDERGLOW_ON  0   // set to 1 to keep the strip driver compiled
```

Kconfig — `boards/karnadii/geulis/Kconfig.geulis`:
```
# CONFIG_GEULIS_DRIVER_RGB_UNDERGLOW is not set
```
(Or comment out the `select WS2812_STRIP` / `select ZMK_RGB_UNDERGLOW`
lines in the Kconfig.)

This disables the WS2812 strip driver and ZMK's RGB underglow layer,
saving roughly 5–10 KB of flash. The `&spi3 { ... led_strip { ... } }`
block stays declared; only the driver code is dropped. If you remove
`GEULIS_RGB_UNDERGLOW_ON = 0` but leave the Kconfig enabled, you'll get
a build error from ZMK's `rgb_underglow.c`.

### 4. Other Kconfig knobs (no DTS changes needed)

| Setting | File | Effect |
| --- | --- | --- |
| `CONFIG_GEULIS_RGB_UNDERGLOW_AUTO_OFF_USB=n` | `geulis_defconfig` | Turn off RGB on USB (ZMK's symbol name is misleading — `y` actually turns OFF on USB). |
| `CONFIG_ZMK_RGB_UNDERGLOW_BRT_MAX=70` | `geulis_defconfig` | Cap brightness at 70% (~300 mA on USB, safe for marginal hosts). Range 0–100 percent. |
| `CONFIG_ZMK_DISPLAY_BLANK_ON_IDLE=n` | `geulis_defconfig` | Keep OLED on while keyboard is idle on battery (otherwise blanks after timeout). |
| `CONFIG_GEULIS_RGB_UNDERGLOW_HUE_START=160` | `geulis_defconfig` | Default boot hue for the underglow. |

After editing any of the above, rebuild with
`docker compose -f docker/docker-compose.yml run --rm build ./docker/build.sh --clean`
because cmake caches the devicetree evaluation.

## CI

Pull requests run the upstream `zmkfirmware/zmk/build-user-config.yml@main`
workflow on GitHub Actions. CI should now pass — the board structure
follows the main-branch HWMv2 conventions, and the local `module/` has
been removed (the upstream `zmk,indicator-leds` driver is built in).

## Keymap notes

- Layer 0 (`macos`), 1 (`windows`), 2 (`functions`), 3 (`settings`).
- The top encoder is volume on layers 0/1 and RGB brightness+hue on
  layers 2/3.
- The middle encoder is vertical scroll (↑/↓) on layers 0/1 and
  Ctrl+Z / Ctrl+Y (undo/redo) on layers 2/3.
- The bottom encoder is horizontal scroll (←/→) on layers 0/1 and
  browser back / forward on layers 2/3.

See `boards/karnadii/geulis/geulis.keymap` for the full layout and the
`MORPH(...)` / `ENCODER(...)` macros at the top of the file.
