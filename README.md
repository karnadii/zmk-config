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

There are two layers of configuration to disable a hardware feature at
compile time (both must agree):

1. **DTS-visible macros** in `boards/karnadii/geulis/geulis_options.h`:
   set `GEULIS_*_ON` to `0` to remove the matching node from the
   devicetree. (E.g. `GEULIS_RGB_UNDERGLOW_ON 0` to skip the WS2812
   strip.)
2. **Kconfig driver selection** in `boards/karnadii/geulis/geulis_defconfig`:
   set `CONFIG_GEULIS_DRIVER_*` to `n` to strip the driver source.

After editing either file, rebuild with
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
