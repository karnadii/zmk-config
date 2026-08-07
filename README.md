# ZMK user-config for my keyboards

ZMK v0.3 user-config repository for my keyboard builds. Each
keyboard lives under `boards/karnadii/<keyboard>/` (monolithic board)
or `boards/shields/<keyboard>/` (split shield). Default board for
shields is `nrfmicro_13`; override with `--board <name>`.

## Keyboards

| Keyboard | Path | Layout | Build command |
| --- | --- | --- | --- |
| **Geulis** (Alice, 7×10) | `boards/arm/geulis/` | monolithic nRF52840 board | `./docker/build.sh --regular --board geulis` |
| **Marvelous65 Rev2** (65% ANSI) | `boards/arm/marvelous65/` | monolithic nRF52840 board | `./docker/build.sh --regular --board marvelous65` |
| **Marvelous65 Ergo** (65% ergo, split B) | `boards/arm/marvelous65_ergo/` | monolithic nRF52840 board | `./docker/build.sh --regular --board marvelous65_ergo` |
| **Marvelous65 Split** | `boards/shields/marvelous65_split/` | shield on Pro Micro pin-compatible MCU | `./docker/build.sh --regular --shield marvelous65_split_left` and `--shield marvelous65_split_right` |

Each board/shield has its own `## <Name>` section below with hardware
notes, build commands, and any caveats.

## TODO

- Create `zmk,physical-layout` definitions and enable ZMK Studio for all
  Marvelous65 variants: Rev2, Ergo, and Split.
- Add dongle support for every keyboard, with all keyboards connecting
  through one shared dongle.

## Keymap

![keymap](/keymap-drawer/geulis.svg)

(Rendered automatically by CI on changes to any `.keymap` or `.dtsi`.)

## Repository layout

```
.
├── build.yaml                # CI build matrix
├── config/west.yml           # West manifest (zmkfirmware/zmk @ v0.3)
├── zephyr/module.yml         # Registers this repo as a Zephyr module
├── boards/
│   ├── arm/
│   │   ├── geulis/                # Alice (nRF52840)
│   │   ├── marvelous65/           # 65% ANSI (nRF52840)
│   │   └── marvelous65_ergo/      # 65% ergo, split B (nRF52840)
│   └── shields/
│       └── marvelous65_split/     # Split (Pro Micro pin-compatible)
├── keymap-drawer/            # Generated SVG / YAML (CI-updated)
├── docker/                   # Local build toolchain
└── .github/workflows/
    ├── build.yml             # CI firmware builds
    └── draw-keymaps.yml      # CI keymap-drawer renders
```

## Building the firmware

### Prerequisites

- Docker with the Compose plugin (`docker compose version`)
- A working USB connection if you plan to flash (UF2 bootloader)

### One-time setup

```bash
docker compose -f docker/docker-compose.yml build
```

The first build pulls ~1 GB of toolchain. Subsequent builds reuse the
cached image and the named `zmk_workspace_cache` volume (≈5 min on
first west update, near-instant on subsequent builds).

### Variants

Each board/shield produces four UF2 files (one per `--action`):

| Action | Flag | Artifact | Notes |
| --- | --- | --- | --- |
| `regular` | `--regular` | `<board>-zmk.uf2` | Plain USB HID + BLE. Daily-use firmware. |
| `studio` | `--studio` | `<board>-zmk-studio.uf2` | ZMK Studio (needs `zmk,physical-layout`). |
| `logging` | `--logging` | `<board>-zmk-logging.uf2` | USB CDC logging for debugging. |
| `reset` | `--reset` | `<board>-zmk-reset.uf2` | Factory-reset (clears bonding, RGB, etc.). |

For shields, the artifact name is `<board>-<shield>-zmk.uf2` so left
and right halves don't clobber each other. Example: `nrfmicro_13-marvelous65_split_left-zmk.uf2`.

### Examples

```bash
# All four variants for the default board (geulis)
./docker/build.sh --regular
./docker/build.sh --studio
./docker/build.sh --logging
./docker/build.sh --reset

# Specific board
./docker/build.sh --regular --board marvelous65
./docker/build.sh --regular --board marvelous65_ergo

# Split keyboard: build both halves
./docker/build.sh --regular --shield marvelous65_split_left
./docker/build.sh --regular --shield marvelous65_split_right
```

If `--studio` fails with `static assertion failed` mentioning
`zmk,physical-layout`, that board doesn't yet declare a physical
layout — add one in its DTS before requesting Studio.

### Other commands

```bash
./docker/build.sh --clean          # wipe build cache
./docker/build.sh --init           # run only west init + west update
./docker/build.sh --shell          # bash inside the container
docker compose -f docker/docker-compose.yml down -v   # wipe west cache
```

### Flashing

1. Put the keyboard into bootloader mode — double-tap the reset
   button, or use the `&bootloader` binding or `<BOOT>` combo.
2. The host mounts a new USB drive labelled with the keyboard name
   (e.g. `GEULIS`).
3. Copy the `.uf2` file onto that drive:
   ```bash
   cp firmware/geulis-zmk.uf2 /media/$USER/GEULIS/
   ```
4. The keyboard reboots automatically after ~2 seconds.

To factory-reset, flash the `-reset.uf2` artifact first, then re-flash
the regular variant.

## Toggling hardware features (per-board)

Each board's `## <Name>` section below documents the per-feature
toggles. Most Marvelous65 variants are monolithic — RGB + OLED +
encoder are always compiled in. The Geulis uses a per-feature
`geulis_options.h` header (see the Geulis section).

## CI

Pull requests, pushes to `v0.3-stable` or `main`, weekly schedules,
and manual `workflow_dispatch` runs all trigger `.github/workflows/build.yml`.
The build matrix is `build.yaml` (16 entries — all 4 boards ×
variants). Each entry produces one UF2 file.

A successful push to `v0.3-stable` (or a manual dispatch) publishes
all the UF2 files to a rolling `latest` GitHub release via
`softprops/action-gh-release@v2`. The weekly schedule and PR builds
just exercise the matrix without publishing.

## Boards

### Geulis

**Path:** `boards/arm/geulis/` &nbsp;·&nbsp; **Layout:** Alice (7 rows × 10 cols, 1.5°–12° slanted halves merged into one PCB with thumb cluster) &nbsp;·&nbsp; **MCU:** nRF52840

Hardware: 3 EC11 rotary encoders, WS2812 RGB underglow (18 LEDs on
SPI3), SSD1306 128×32 OLED on I2C0, battery sense on AIN2, EXT_POWER
on P1.09.

ZMK Studio supported — board declares a `zmk,physical-layout`.

Build: `./docker/build.sh --regular --board geulis` (or any variant).

#### Feature toggles

Geulis uses a per-feature toggle header `boards/arm/geulis/geulis_options.h`.
Set `GEULIS_*_ON` to `0` to remove the matching node from the
devicetree. Pair with the matching `CONFIG_GEULIS_DRIVER_*` Kconfig
in `geulis_defconfig` to also disable the driver source.

| Feature | options.h macro | defconfig symbol |
| --- | --- | --- |
| Top encoder (P0.26 / P0.06) | `GEULIS_ENCODER_TOP_ON` | `CONFIG_GEULIS_DRIVER_ENCODER` |
| Middle encoder (P0.08 / P0.27) | `GEULIS_ENCODER_MID_ON` | `CONFIG_GEULIS_DRIVER_ENCODER` |
| Bottom encoder (P1.08 / P0.11) | `GEULIS_ENCODER_BOT_ON` | `CONFIG_GEULIS_DRIVER_ENCODER` |
| WS2812 underglow (SPI3, P0.05) | `GEULIS_RGB_UNDERGLOW_ON` | `CONFIG_GEULIS_DRIVER_RGB_UNDERGLOW` |
| SSD1306 OLED (I2C0, 0x3C) | `GEULIS_OLED_ON` | `CONFIG_GEULIS_DRIVER_OLED` |

At least one encoder must be enabled — `geulis.dts` has a `#error`
if all three are `0`.

#### Layout variants

The board has 4 backspace × right-shift variants. Set
`zmk,physical-layout = &layout0..&layout3` in `geulis.dts` to
switch. See `geulis-layout.dtsi` for the position map.

#### Keymap notes

- Layers: `macos` (0), `windows` (1), `functions` (2), `settings` (3)
- Top encoder: volume on layers 0/1, RGB brightness+hue on 2/3
- Middle encoder: vertical scroll on 0/1, Ctrl+Z / Ctrl+Y on 2/3
- Bottom encoder: horizontal scroll on 0/1, browser back/forward on 2/3

### Marvelous65 Rev2

**Path:** `boards/arm/marvelous65/` &nbsp;·&nbsp; **Layout:** 65% ANSI (5 rows × 8 cols, single encoder top-right) &nbsp;·&nbsp; **MCU:** nRF52840

Hardware: 1 EC11 encoder on P0.09/P0.10, WS2812 RGB underglow
(14 LEDs on SPI1 / P0.32), SSD1306 128×32 OLED on I2C0, battery
sense on AIN2, EXT_POWER on P1.09 (50 ms init delay).

ZMK Studio **not yet** supported — board has no `zmk,physical-layout`.

Build: `./docker/build.sh --regular --board marvelous65` (or any
non-studio variant).

#### Keymap notes

- 4 layers: `macos` (0), `windows` (1), `functions` (2), `settings` (3)
- Top-right encoder: volume on layers 0/1, track skip on 2, scrub on 3

### Marvelous65 Ergo

**Path:** `boards/arm/marvelous65_ergo/` &nbsp;·&nbsp; **Layout:** 65% ergo with split B key across row 3 (left half) and row 4 (right half) &nbsp;·&nbsp; **MCU:** nRF52840

Hardware: identical to the Rev2 (same Pro Micro pinout), but the
**row 3** GPIO is wired to **P0.20** instead of P1.4 (PCB trace
routing), and `EXT_POWER` uses a 300 ms init delay.

ZMK Studio **not yet** supported.

Build: `./docker/build.sh --regular --board marvelous65_ergo` (or
any non-studio variant).

#### Keymap notes

- 4 layers: `macos` (0), `windows` (1), `functions` (2), `settings` (3)
- Top-right encoder: same as Rev2

### Marvelous65 Split

**Path:** `boards/shields/marvelous65_split/` &nbsp;·&nbsp; **Layout:** true ZMK split — two halves pair over BLE, each with encoder + OLED + RGB &nbsp;·&nbsp; **Default MCU:** nRF52840 (`nrfmicro_13`)

Each half runs the same firmware image; the `Kconfig.shield` picks
the role (central / peripheral) based on `-DSHIELD=marvelous65_split_{left,right}`.

Hardware (per half):
- 1 EC11 encoder (only one enabled at a time — left/right)
- SSD1306 128×32 OLED on I2C0
- WS2812 RGB underglow (14 LEDs) on SPI1
- 8×5 matrix; right half sets `col-offset = <8>` so its keys land
  in cols 8–15 of a shared 16-col logical matrix

**Default board is `nrfmicro_13`** — override with `--board <name>`
for any other Pro Micro pin-compatible controller (nice!nano, etc.).
The shield is designed against the Pro Micro pin aliases (D-row + A-row)
so the GPIO assignments work on any board that exposes those pins.

Build:
```bash
./docker/build.sh --regular --shield marvelous65_split_left
./docker/build.sh --regular --shield marvelous65_split_right
```

Both halves must be flashed; the central role handles USB. After
flashing, the halves pair over BLE on first power-up.

#### Keymap notes

- 4 layers: `macos` (0), `windows` (1), `functions` (2), `settings` (3)
- 16-col × 5-row keymap shared by both halves; right half's
  `col-offset = <8>` shifts its keys into the right half of the matrix
- Both halves' encoders are bound to the same action (volume on
  layers 0/1, track skip on 2, scrub on 3) — the unused encoder
  is a no-op on each half

See `AGENTS.md` for hardware specs, keymap conventions, and a full
list of build / flash gotchas.