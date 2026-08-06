# ZMK user-config for my keyboards
![alt text](https://github.com/karnadii/geulis/blob/main/images/geulis_keyboard_acrylic_case_2021-Jun-04_11-50-24AM-000_CustomizedView44178749806.png?raw=true)

ZMK v0.3 user-config repository for my keyboard builds. Currently
ships with the **Geulis** — a single-piece Alice-style keyboard built
on the nRF52840, with three EC11 rotary encoders, an optional WS2812
underglow strip, and an SSD1306 128×32 OLED status screen. Additional
boards will be added beside Geulis in `boards/arm/<keyboard>/`.

| Keyboard | MCU | Path | Status |
| --- | --- | --- | --- |
| **Geulis** (Alice, 7×10) | nRF52840 | `boards/arm/geulis/` | stable |
| **Marvelous65 Rev2** (65% ANSI, encoder) | nRF52840 | `boards/arm/marvelous65/` | stable (no ZMK Studio yet) |

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

The repository builds three UF2 files:

| Artifact | Command | Purpose |
| --- | --- | --- |
| `geulis-zmk.uf2` | `./docker/build.sh --studio` | Default. ZMK Studio over USB. |
| `geulis-zmk.uf2` | `./docker/build.sh --logging` | USB CDC logging for debugging (same filename as Studio). |
| `geulis-zmk-reset.uf2` | `./docker/build.sh --reset` | Factory-reset firmware (clears bonding, RGB, etc.). |

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
   Zephyr + ZMK into the volume (≈5 min on first run; cached afterward).
3. Runs `west zephyr-export` and then `west build -s zmk/app -b geulis`
   with `-DZMK_EXTRA_MODULES=/workspace` so the `boards/arm/geulis/`
   board definition is registered.
4. Copies the resulting `.uf2` to `./firmware/` on the host.

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

After `docker build.sh` finishes, the UF2 lands in `./firmware/` on
your host:

```
firmware/geulis-zmk.uf2
firmware/geulis-zmk-reset.uf2
```

To flash the Geulis:

1. Put the Geulis into bootloader mode — double-tap the reset button,
   or use the `&bootloader` binding or `<BOOT>` combo on the keyboard.
2. The host mounts a new USB drive labelled `GEULIS`.
3. Copy the `.uf2` file onto that drive:
   ```bash
   cp firmware/geulis-zmk.uf2 /media/$USER/GEULIS/
   ```
   (or just drag-and-drop in a file manager.)
4. The Geulis reboots automatically after ~2 seconds.

To factory-reset the device (clear saved Bluetooth bonds, RGB settings,
etc.), flash the `geulis-zmk-reset` artifact and then re-flash
the Studio variant.

## Hardware features

- **Three EC11 rotary encoders** (top, middle, bottom). All three are
  enabled in firmware by default so a user can solder one in
  (or swap one out) without re-flashing. Individual encoders can be
  disabled — see [Toggling hardware features](#toggling-hardware-features).
- **18-LED WS2812 RGB underglow** driven via SPI3 (P0.05).
  Brightness is capped at **70%** by default — ZMK's `BRT_MAX` is in
  percent, and 70% on 18 LEDs keeps the strip under ~300 mA so the USB
  data lines don't brown-out when the host port is marginal.
- **SSD1306 128×32 OLED status screen** on I2C0 (SDA = P0.15,
  SCL = P0.17, address `0x3C`). Shows layer name, battery percentage,
  and active output by default.

See `AGENTS.md` for hardware specs, keymap conventions, and a full
list of build / flash gotchas.

## Toggling hardware features

There are two layers of configuration to disable a hardware feature at
compile time (both must agree):

1. **DTS-visible macros** in `boards/arm/geulis/geulis_options.h`:
   set `GEULIS_*_ON` to `0` to remove the matching node from the
   devicetree. (E.g. `GEULIS_RGB_UNDERGLOW_ON 0` to skip the WS2812
   strip.)
2. **Kconfig driver selection** in `boards/arm/geulis/geulis_defconfig`:
   set `CONFIG_GEULIS_DRIVER_*` to `n` to strip the driver source.

After editing either file, rebuild with
`docker compose -f docker/docker-compose.yml run --rm build ./docker/build.sh --clean`
because cmake caches the devicetree evaluation.

### Available toggles

| Feature | options.h macro | defconfig symbol | DTS impact |
| --- | --- | --- | --- |
| Top encoder (P0.26 / P0.06) | `GEULIS_ENCODER_TOP_ON` | `CONFIG_GEULIS_DRIVER_ENCODER` | toggles `top_encoder` `status` |
| Middle encoder (P0.08 / P0.27) | `GEULIS_ENCODER_MID_ON` | `CONFIG_GEULIS_DRIVER_ENCODER` | toggles `mid_encoder` `status` |
| Bottom encoder (P1.08 / P0.11) | `GEULIS_ENCODER_BOT_ON` | `CONFIG_GEULIS_DRIVER_ENCODER` | toggles `bot_encoder` `status` |
| WS2812 underglow strip | `GEULIS_RGB_UNDERGLOW_ON` | `CONFIG_GEULIS_DRIVER_RGB_UNDERGLOW` | toggles `&spi3` `status` + `led_strip` node |
| SSD1306 128×32 OLED on I2C0 | `GEULIS_OLED_ON` | `CONFIG_GEULIS_DRIVER_OLED` | toggles `&i2c0` `status` + `ssd1306@3c` node |

The `GEULIS_DRIVER_*` symbol controls whether the **driver source** is
compiled. The matching `GEULIS_*_ON` macro controls whether the
**devicetree node** is present. Both must be flipped together — leaving
the driver compiled with no DT node (or vice-versa) will fail the
build.

### Examples

**Use only the top encoder (e.g. the PCB only has the top encoder soldered):**

In `boards/arm/geulis/geulis_options.h`:

```c
#define GEULIS_ENCODER_TOP_ON    1
#define GEULIS_ENCODER_MID_ON    0
#define GEULIS_ENCODER_BOT_ON    0
```

Leave `CONFIG_GEULIS_DRIVER_ENCODER=y` in `geulis_defconfig` — the EC11
driver is still needed to drive the top encoder.

Then in `boards/arm/geulis/geulis.keymap`, replace the 3-element
`sensor-bindings` lists so the keymap no longer references the disabled
encoders. Search for `sensor-bindings = <&media_encoder` and change each
one to a single-element list:

```dts
sensor-bindings = <&media_encoder>;
```

The same applies to the function-layer bindings (`<&rgb_encoder ...`).

**Disable all encoders entirely** (keypad-style build with no rotary
knobs):

```c
// geulis_options.h
#define GEULIS_ENCODER_TOP_ON    0
#define GEULIS_ENCODER_MID_ON    0
#define GEULIS_ENCODER_BOT_ON    0
```

```kconfig
# geulis_defconfig
CONFIG_GEULIS_DRIVER_ENCODER=n
```

The devicetree enforces "at least one encoder enabled" via a `#error`
in `geulis.dts`, so flipping all three macros to `0` is impossible
unless you also delete the `#error` line.

**Disable the OLED** (no display module installed):

```c
// geulis_options.h
#define GEULIS_OLED_ON           0
```

```kconfig
# geulis_defconfig
# leave CONFIG_GEULIS_DRIVER_OLED=y; the driver is still harmless
# (DT_HAS_SOLOMON_SSD1306FB_ENABLED goes false and the driver
# source isn't compiled), or set it to n for explicitness.
```

**Disable RGB underglow:**

```c
// geulis_options.h
#define GEULIS_RGB_UNDERGLOW_ON  0
```

```kconfig
# geulis_defconfig
CONFIG_GEULIS_DRIVER_RGB_UNDERGLOW=n
```

Also remove any `&rgb_ug` / `&rgb_underglow` bindings from
`boards/arm/geulis/geulis.keymap` if you use them.

## CI

Pull requests run the upstream `zmkfirmware/zmk/build-user-config.yml@v0.3`
workflow on GitHub Actions. CI builds the same artifacts as the local
Docker workflow above and uploads UF2 files to workflow runs.

## Keymap notes

- Layer 0 (`macos`), 1 (`windows`), 2 (`functions`), 3 (`settings`).
- The top encoder is volume on layers 0/1 and RGB brightness+hue on
  layers 2/3.
- The middle encoder is vertical scroll (↑/↓) on layers 0/1 and
  Ctrl+Z / Ctrl+Y (undo/redo) on layers 2/3.
- The bottom encoder is horizontal scroll (←/→) on layers 0/1 and
  browser back / forward on layers 2/3.

See `boards/arm/geulis/geulis.keymap` for the full layout and the
`MORPH(...)` / `ENCODER(...)` macros at the top of the file.
