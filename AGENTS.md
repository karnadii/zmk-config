# AGENTS.md

Guidance for AI agents (and humans) working in this ZMK user-config repository for the **Geulis** keyboard (nRF52840-based, custom keyboard by karnadii: <https://github.com/karnadii/geulis/>).

## What this repository is

This is a **ZMK user-config repo**, not standalone firmware. It defines the keyboard's board definition, physical layout, matrix transform, keymap, and ZMK config — and is consumed by the upstream `zmkfirmware/zmk` build system via `config/west.yml`. There is no application code to compile locally.

- Upstream firmware: <https://github.com/zmkfirmware/zmk>
- ZMK docs (user config / shields / boards): <https://zmk.dev/docs>

## Repository layout

```
.
├── build.yaml                # CI build matrix (defines the firmware artifacts built)
├── config/west.yml           # West manifest pointing at zmkfirmware/zmk @ main
├── zephyr/module.yml         # Registers this repo as a Zephyr module (board_root: .)
├── module/                   # Local `zmk-indicator-leds` ZMK module (see below)
│   ├── CMakeLists.txt
│   ├── Kconfig
│   ├── zephyr/module.yml     # `name: zmk-indicator-leds` (must be unique vs ZMK's own `module`)
│   ├── dts/bindings/zmk,indicator-leds.yaml
│   ├── include/              # (reserved for public headers)
│   └── src/indicator_leds.c  # backport of `zmk,indicator-leds` for ZMK v0.3
├── boards/arm/geulis/        # Board definition (the keyboard lives here)
│   ├── Kconfig, Kconfig.board, Kconfig.defconfig
│   ├── board.cmake           # nrfjprog / UF2 / openocd runners
│   ├── pre_dt_board.cmake    # Suppresses duplicate unit-address DTC warnings
│   ├── geulis_defconfig      # Kconfig fragments (ZMK + board features)
│   ├── geulis.conf           # Extra .conf layered on by ZMK (PM, idle timeout)
│   ├── geulis.yaml           # Zephyr board YAML (identifier / features / outputs)
│   ├── geulis.zmk.yaml       # ZMK board metadata (features, studio support)
│   ├── geulis.dts            # Board DTS: kscan, encoders, LEDs, RGB SPI, ext-power, ADC, flash partitions
│   ├── geulis-pinctrl.dtsi   # pinctrl groups for I2C0 and SPI3
│   ├── geulis-layout.dtsi    # 4 physical layouts + position_map (for backspace/shift variants)
│   ├── geulis-transform.dtsi # 4 matrix transforms matching the 4 layouts
│   ├── geulis.keymap         # The actual keymap (behaviors, combos, macros, layers)
│   └── geulis.json           # Info.json layout data (used by keymap-drawer)
├── keymap-drawer/            # Generated visual keymap (auto-updated by CI)
│   ├── config.yaml           # keymap-drawer rendering config
│   ├── geulis.svg            # Rendered keymap SVG (do not edit by hand)
│   └── geulis.yaml           # Parsed keymap YAML (do not edit by hand)
├── docker/                   # Local-build toolchain (Docker)
│   ├── Dockerfile            # Wraps zmkfirmware/zmk-build-arm:stable
│   ├── docker-compose.yml    # Mounts the repo + named volumes for caches
│   └── build.sh              # Idempotent wrapper around `west init` + `west build`
└── .github/workflows/
    ├── build.yml             # Calls zmkfirmware/zmk build-user-config.yml (pinned to v0.3)
    └── draw-keymaps.yml      # Calls caksoylar/keymap-drawer draw-zmk.yml
```

## Build / test / firmware generation

CI is the primary build path; local building is supported via Docker (see below).

- **`build.yml`** — pinned to `zmkfirmware/zmk/.github/workflows/build-user-config.yml@v0.3`. Runs on push to `build.yaml`, `config/**`, `boards/**`, or its own file. Also runs on Mondays 10:00 UTC (scheduled). Builds every entry in `build.yaml` and uploads UF2 firmware artifacts. On success, `filterpaper/scripts/publish-artifact.yml@main` rolls them into a "ZMK Firmware / latest" GitHub release.
- **`draw-keymaps.yml`** — runs on push to `boards/arm/geulis/*.keymap` or `*.dtsi`, or via manual dispatch. It calls `caksoylar/keymap-drawer/draw-zmk.yml@main` which parses the keymap + Info.json, generates SVG/YAML in `keymap-drawer/`, and **amends** the commit (so the rendered keymap ships in the same commit).

### Local Docker build (recommended)

All local-build assets live under `docker/`:

```bash
# one-time build of the local image (pulls zmkfirmware/zmk-build-arm:stable)
docker compose -f docker/docker-compose.yml build

# run the ZMK Studio variant (matches build.yaml's first entry)
docker compose -f docker/docker-compose.yml run --rm build ./docker/build.sh --studio
# UF2 lands in ./firmware/geulis-zmk-studio.uf2 — copy to the GEULIS bootloader drive

# other variants: --logging, --reset
# drop into a shell inside the container for ad-hoc west invocations
docker compose -f docker/docker-compose.yml run --rm build ./docker/build.sh --shell
```

The script does a `west init -l <ws>/config` + `west update` into a **named docker volume** (`zmk_workspace_cache`, mounted at `/zmk-workspace`) on first run. The user-config repo's `config/west.yml` is copied there so west's `zephyr/`, `modules/`, `bootloader/`, `zmk/` checkouts land in the volume instead of clobbering the bind-mounted repo (which would overwrite the tracked `zephyr/module.yml`). `west zephyr-export` registers the Zephyr CMake config — this requires `self.west-commands: zmk/app/scripts/west-commands.yml` in `config/west.yml`. Then `west build -s zmk/app -b geulis -S <snippet> -- -DZMK_CONFIG=<ws>/config -DZMK_EXTRA_MODULES=<repo>;<repo>/module` builds the firmware. The second `ZMK_EXTRA_MODULES` entry activates the local `zmk-indicator-leds` module (see below). UF2 lands in `./firmware/` (gitignored).

To flash: enter bootloader (double-tap reset, or the boot combo — see `COMBO_BOOTLOADER` in `geulis.keymap`), then copy the `.uf2` to the mounted `GEULIS` drive.

## ZMK v0.3 upgrade notes

This branch (`feature/zmk-v0.3-upgrade`) pins ZMK to v0.3 (Zephyr 3.5) via `config/west.yml` (`revision: v0.3`) and `.github/workflows/build.yml` (`build-user-config.yml@v0.3`). Per the official `2024-02-09-zephyr-3-5.md` release notes, the only **required edits** to this repo for v0.3 were:

- Pin ZMK in `config/west.yml` and the CI workflow to `v0.3`.
- Add `self.west-commands: zmk/app/scripts/west-commands.yml` to `config/west.yml` so `west zephyr-export` is available (otherwise the ZMK CMake module can't find ZephyrConfig.cmake).

No source-code edits in `boards/`, `keymap-drawer/`, or the keymap were needed because:

- Battery sensing uses `zmk,battery-voltage-divider` (not MAX17048), so no `zmk,maxim-max17048` rename is needed.
- `boards/arm/geulis/board.cmake` already includes `uf2.board.cmake` for `west flash`.
- No display means the LVGL changes (`LV_Z_DPI` → `LV_DPI_DEF`, SSD1306 inversion) don't apply.
- The keymap already uses `&sys_reset`, `&studio_unlock`, `behavior-mod-morph`, `behavior-sensor-rotate(-var)`, and `behavior-macro` with `wait-ms`/`tap-ms` — all valid in v0.3.

The `CONFIG_WS2812_STRIP=y` and `CONFIG_SOC_NRF52840_QIAA=y` lines in `geulis_defconfig` look like future removals but are **still required in v0.3** — they were removed only in ZMK 4.1 / Zephyr 4.1.

## The four firmware variants (`build.yaml`)

| Artifact | Snippet / Shield | Purpose |
| --- | --- | --- |
| `geulis-zmk-studio` | `studio-rpc-usb-uart` + `CONFIG_ZMK_STUDIO=y` | ZMK Studio over USB (live remapping) |
| `geulis-zmk-logging` | `zmk-usb-logging` | USB CDC logging for debugging |
| `geulis-zmk-reset-settings` | shield `settings_reset` | Wipes persisted settings (bonding, RGB, etc.) — flash this to factory-reset |

All three target the single `geulis` board.

## Keyboard hardware (Geulis specifics)

- **MCU:** nRF52840 (QIAA, `SOC_NRF52840_QIAA`).
- **Matrix:** 7 rows × 10 cols, GPIO-matrix scan with `diode-direction = "col2row"`, active-high rows with internal pull-down, active-high cols.
- **Three EC11 rotary encoders** wired to GPIOs but only `top_encoder` (`encoder_top`) is `status = "okay"`. Toggle which encoders are enabled via `boards/arm/geulis/geulis_options.h` (`GEULIS_ENCODER_TOP_ON` / `_MID_ON` / `_BOT_ON`). See "Feature toggles" below.
- **RGB underglow:** WS2812 strip of 18 LEDs driven via SPI3 (SPIM MOSI on P0.05). Toggle via `GEULIS_RGB_UNDERGLOW_ON` in `geulis_options.h`. Chain length, color mapping, and SPI frame patterns are in `geulis.dts` under `&spi3`. Configured via `CONFIG_ZMK_RGB_UNDERGLOW_*` in `geulis_defconfig` (auto-off on USB, hue start 160, effect 3, brightness 10–50).
- **Battery sensing:** `zmk,battery-voltage-divider` on ADC channel AIN2, divider 2 MΩ / 820 kΩ.
- **External power control (`EXT_POWER`):** `zmk,ext-power-generic` toggles via GPIO P1.09 active-low, 50 ms init delay. The node **must** keep the literal label `EXT_POWER` to preserve user settings across reflash.
- **LED indicators (custom `zmk-indicator-leds` module):** `boards/arm/geulis/geulis.dts` declares an `indicators` node. Blue LED (P1.10) tracks the macOS layer (index 0). LEDs default off when no indicator is active. Implementation is a backport of the v0.4 `zmk,indicator-leds` driver — see `module/`.
- **Sleep / PM:** `CONFIG_ZMK_PM_SOFT_OFF`, `CONFIG_ZMK_SLEEP`, `CONFIG_ZMK_EXT_POWER`, and a 10-minute idle timeout (`CONFIG_ZMK_IDLE_SLEEP_TIMEOUT = 600000`).
- **BLE tuning:** 2M PHY disabled, +8 dBm TX power commented out, no passkey entry — see the `# Connection issue` comment block in `geulis_defconfig`.

## Local module: `zmk-indicator-leds`

ZMK v0.3 does NOT include the `zmk,indicator-leds` GPIO driver that
ships with ZMK 4.x. The local module under `module/` backports that
driver so the Geulis can drive an indicator LED from layer state.

**How it works:**

- Subscribes to `zmk_layer_state_changed`,
  `zmk_activity_state_changed`, `zmk_usb_conn_state_changed`,
  `zmk_endpoint_changed`, and (when `CONFIG_ZMK_HID_INDICATORS=y`)
  `zmk_hid_indicators_changed`.
- Coalesces events into a single work item, then walks a static
  table built at compile time from the `zmk,indicator-leds` node's
  children and toggles each indicator's GPIO directly via
  `gpio_pin_set_dt()` (no `led_on`/`led_off` indirection).
- The GPIO spec for each `leds` phandle is resolved via
  `GPIO_DT_SPEC_GET_BY_IDX` against the LED's `gpios` property.

**DT usage:**

```dts
indicators {
    compatible = "zmk,indicator-leds";

    caps_lock_indicator {
        compatible = "zmk,indicator-leds-entry";
        indicator = <1>;            /* HID_INDICATOR_CAPS_LOCK */
        leds = <&green_led>;
    };

    macos_layer_indicator {
        compatible = "zmk,indicator-leds-entry";
        layer = <0>;
        leds = <&blue_led>;
    };
};
```

Each child must have either `indicator = <N>` (HID indicator bit number)
or `layer = <N>` (zero-based keymap layer index), but not both. `leds`
is a phandle-array referencing existing `gpio-leds` children.

**Build wiring:**

- `module/zephyr/module.yml` is named `zmk-indicator-leds` (NOT `module` —
  ZMK's own `app/module` collides on the default name and would silently
  shadow us).
- `docker/build.sh` passes the local module via
  `-DZMK_EXTRA_MODULES=${ROOT};${ROOT}/module`. The `dts_root: .` setting
  exposes `module/dts/bindings/` so the binding resolves before the board
  DTS is compiled.
- The module's `CMakeLists.txt` uses `find_path` to locate ZMK's
  `app/include` (where `<zmk/event_manager.h>` etc. live) and adds it
  to the global `zephyr_interface` include path. Keep the path in sync
  if ZMK ever relocates its include directory.

**Known limitation — CI build is broken:**

- The GitHub Actions workflow (`.github/workflows/build.yml`) uses the
  upstream `zmkfirmware/zmk/build-user-config.yml@v0.3`, which does NOT
  pass `-DZMK_EXTRA_MODULES=...` for the local `module/`. As a result,
  `boards/arm/geulis/geulis.dts`'s `indicators { compatible =
  "zmk,indicator-leds"; … }` node will fail devicetree validation on
  CI, and the build will fail.
- Local Docker builds work because `docker/build.sh` injects the module
  path. CI is intentionally left broken until either (a) the indicators
  node is moved to an overlay file that only local builds include, or
  (b) the workflow is patched to forward the module path.

**Limitations vs upstream ZMK 4.x driver:**

- The upstream `on-while-idle` / `binding-behavior` properties are not
  implemented. LEDs simply follow the indicator / layer state.
- The upstream DPI / brightness / pulse controls are not relevant here
  (the Geulis uses plain GPIO LEDs, not PWM or smart LEDs).
- **Caps Lock LED is not supported on ZMK v0.3.** The host's HID
  indicator report is unreliable on Windows, and the upstream
  `zmk,indicator-leds` driver needs it to track Caps Lock state. The
  main ZMK branch adds reliability enhancements upstream that the
  v0.3 backport can't replicate. The Geulis on v0.3 gets layer
  indicator only (blue LED on macOS layer). To add Caps Lock LED,
  switch to main-branch ZMK — see the migration plan below.

**Why a module and not a board-local overlay:**

- The ZMK v0.3 devicetree has no `&ind_leds` style helper for arbitrary
  GPIO pins, and the upstream `zmk,indicator-leds` driver doesn't exist
  in this ZMK version. A local module is the only way to drive
  arbitrary GPIOs from indicator events without forking ZMK.
- The module is **only** registered when building locally — see
  `docker/build.sh`. CI (`.github/workflows/build.yml`) does not pass
  the local module, so a CI build will still compile (the `indicators`
  node will fail `device_is_ready()` checks and the Kconfig will be
  disabled — but since the binding comes from the same module, the
  compile-time `indicators` node would still match).

## Feature toggles — `geulis_options.h` + `geulis_defconfig`

The Geulis supports optional hardware (extra encoders, RGB underglow) that
can be enabled/disabled at compile time. Two layers must agree:

### Layer 1: `boards/arm/geulis/geulis_options.h` (DTS-visible)

This is the user-facing toggle. Set `#define GEULIS_*_ON` to `0` to
remove the matching node from the devicetree. The header is `#include`d
by `geulis.dts` and is processed by the DTS preprocessor (plain C
preprocessor). Available toggles:

- `GEULIS_ENCODER_TOP_ON` — set to `0` to disable the top encoder.
- `GEULIS_ENCODER_MID_ON` — set to `1` to enable the middle encoder.
- `GEULIS_ENCODER_BOT_ON` — set to `1` to enable the bottom encoder.
- `GEULIS_RGB_UNDERGLOW_ON` — set to `0` to disable the WS2812 strip.

At least one encoder must be enabled (a `#error` enforces this).

### Layer 2: `boards/arm/geulis/geulis_defconfig` (Kconfig)

This selects the matching upstream driver symbols so the driver source
isn't compiled when unused. The `GEULIS_DRIVER_*` Kconfig entries are
defined in `boards/arm/geulis/Kconfig` and pull in their `select`s:

- `CONFIG_GEULIS_DRIVER_ENCODER=y` selects `EC11`.
- `CONFIG_GEULIS_DRIVER_RGB_UNDERGLOW=y` selects `WS2812_STRIP` + `ZMK_RGB_UNDERGLOW`.

To disable a feature entirely, do **both**:

1. Set `GEULIS_*_ON` to `0` in `geulis_options.h`.
2. Set `CONFIG_GEULIS_DRIVER_*` to `n` in `geulis_defconfig` (or remove.

If you only flip the DTS, the driver source is still compiled and you
get a `#error "A zmk,underglow chosen node must be declared"` from
ZMK's `rgb_underglow.c`. If you only flip Kconfig, the driver is
disabled but the devicetree still references it — also a build error.

The Kconfig layer also exposes tuning knobs that don't affect DTS:

- `CONFIG_GEULIS_RGB_UNDERGLOW_AUTO_OFF_USB` — turn off RGB on USB.
- `CONFIG_GEULIS_RGB_UNDERGLOW_HUE_START` / `_EFF_START` / `_BRT_MIN` / `_BRT_MAX`.

### Why two layers?

Zephyr's DTS preprocessor does NOT see `autoconf.h`, so Kconfig values
are not directly usable in DTS. The `geulis_options.h` header is the
single source the DTS preprocessor sees. The Kconfig layer is needed
because the driver source itself is Kconfig-controlled (it lives in
upstream ZMK/Zephyr modules, not in this repo).

## Physical layout (Alice) and layout variants

The Geulis is a **single-piece Alice-style keyboard**: two slanted halves
(±12° key rotation) merged into one PCB with a thumb cluster on row 4.
There is no split-peripheral — everything runs off a single nRF52840.
Note that the term **"split"** elsewhere in this repo (e.g. in
`geulis.dts`, `geulis-layout.dtsi`, `geulis.json`) refers only to the
optional split-backspace / split-right-shift **key variants** below,
never to a split keyboard.

The Geulis supports **four backspace/right-shift variants** (split × one
for each of backspace and right-shift). All four are defined and the
user picks by setting `zmk,physical-layout` to one of `&layout0`–`&layout3`:

| Label | Backspace | Right shift |
| --- | --- | --- |
| `layout0` (default — bound to `zmk,physical-layout` in `geulis.dts`) | Split | Split |
| `layout1` | Split | One |
| `layout2` | One | Split |
| `layout3` | One | One |

Each layout has a matching `transform0`–`transform3` in `geulis-transform.dtsi` (same `map`, only the last entry of the bottom row differs by 1 column), and `geulis-layout.dtsi`'s `position_map` ties them together. **If you change the matrix wiring, you must edit all four transforms consistently**, and the active one is whichever `&layoutN` is selected in `geulis.dts`'s `chosen { zmk,physical-layout = ... }`.

The matrix is 7×10 = 70 slots but only ~62 keys are mapped (Alice
layout with a split thumb cluster and intentional gaps in the inner
columns). Several `RC(r,c)` slots in transforms are unused — that's
intentional.

## Keymap structure (`boards/arm/geulis/geulis.keymap`)

- **Layers:** 4 — `macos`, `windows`, `functions` (layer 2), `settings` (layer 3).
- **`behaviors`** block defines many custom behaviors via two macros at the top of the file:
  - `MORPH(name, primary, secondary)` — `behavior-mod-morph`; secondary activates on Shift/GUI held.
  - `ENCODER(name, prev, next)` — `behavior-sensor-rotate`; binds to one sensor.
  - `ENCODER_VAR(name, prev, next)` — `behavior-sensor-rotate-var`; binds a specific sensor by id.
- **Notable behaviors used:** `bspc_del` (Backspace / DEL morph), `caps_word_caps` (caps-word / Caps Lock morph), `vol_next`, `vol_prev`, `media_encoder` (rotates vol on the top encoder), `rgb_encoder`, `bt_encoder`, `win_sleep`, `win_shutdown` (macros).
- **Combos** unlock studio (`<14 32>`, `<24 32>`), enter bootloader (`<50 32>`, `<51 32>`), `sys_reset` (`<21 32>`), soft-off (`<34 32>`), ext-power toggle/on/off (`<27 32>`, `<2 32>`, `<11 32>`), Insert, PrintScreen, Pause/Break, Windows shutdown (`<61 63 27>`) and Windows sleep (`<61 63 34>`).
- **Macros:** `win_sleep` and `win_shutdown` use `&macro_press`/`&macro_tap`/`&macro_release` with `wait-ms = <40>` and `tap-ms = <40>`. When chaining many `&kp` taps in a macro, separate them with `<&macro_tap>` and consider adding `<&macro_tap>` + a small `<&macro_pause_for_release>` style delay if a host misses keystrokes.
- **Caps-word** continues on `_` and `-` (`continue-list = <UNDERSCORE MINUS>` in the `&caps_word` overlay).
- The keymap also rebinds layer-3 hold (`&mo 3`) and a `&lt 2 SPACE` (layer-tap-to-space on right thumb).

When editing the keymap:
- The visual ASCII layout block above each layer is a comment and the source of truth for the matrix position numbers — keep it in sync if you reorder.
- New `MORPH`/`ENCODER` macros are defined at the top — reuse them rather than inlining `behavior-mod-morph`/`behavior-sensor-rotate` nodes.
- A line `&foo_binding &lt 1 N` becomes two columns visually but the matrix still only advances one slot — `&lt` and `&mo` do **not** consume two positions.

## Generated artifacts (`keymap-drawer/`)

- `geulis.svg` and `geulis.yaml` are **generated** by the `draw-keymaps.yml` workflow. Do not hand-edit them — the workflow amends them into the same commit (or run a local `keymap-drawer parse` / `keymap-drawer draw` for preview).
- The renderer reads `keymap-drawer/config.yaml` for layout/styling and parses the `.keymap` + `boards/arm/geulis/*.json` (Info.json layout positions).
- ZMK Studio binding positions referenced in the keymap (e.g. `<14 32>`) must align with `geulis.json`'s physical layout positions for combos/macros to render in the visualizer.

## VS Code settings (`.vscode/settings.json`)

- Treats `*.keymap` as C++ for highlighting (`"*.keymap": "cpp"`) and disables `C_Cpp.errorSquiggles` because devicetree-includes (`<behaviors.dtsi>` etc.) are not resolvable without a Zephyr workspace. Do **not** "fix" this by enabling an include path — it's intentional.

## Conventions / gotchas

- **`zephyr,code-partition` must be `&code_partition`** — flash partitions are explicitly defined in `geulis.dts`; the layout is `mbr` (4 KB) → `code_partition` (~836 KB) → `storage` (128 KB) → `adafruit_boot` (48 KB). If you ever change `code_partition` size, also update `partition@1000`'s `reg` length.
- **`EXT_POWER` node label is load-bearing** — see the comment in `geulis.dts`. Renaming it silently breaks user settings persistence.
- **RGB uses SPI3, not PWM** — keep `CONFIG_WS2812_STRIP=y` and the `&spi3` `status = "okay"` in sync. Don't try to switch to `pwm-leds` without checking the schematic.
- **`pinctrl-0 = <&spi3_default>` and `&spi3_sleep`** are referenced from `&spi3` — both must be defined in `geulis-pinctrl.dtsi` (note: labels inside the `.dtsi` say `spi1_*` but are referenced as `spi3_*` from `geulis.dts`; this naming mismatch is intentional/upstream-style, don't rename).
- **`i2c0` is declared but not `status = "okay"`** — keep it that way unless you actually add an I2C peripheral.
- **`studio_unlock` combo uses fixed positions** (`<14 32>`, `<24 32>`) — if you rewire the matrix or change which physical layout is default, double-check those numbers still resolve to a real key.
- The `draw-keymaps.yml` workflow **amends the triggering commit** — the rendered keymap shows up in the same commit that changed the `.keymap`/`.dtsi`. Don't be surprised when `git log` shows keymap-drawer changes inside your own commit.
- Scheduled CI runs weekly + has a `purge-workflow` step (only fires on schedule) that prunes old workflow runs.
- `pre_dt_board.cmake` adds `-Wno-unique_unit_address_if_enabled` to silence the nRF52840 DTS unit-address warnings for power/clock/acl/flash-controller — keep it.
- The board supports `nrfjprog`, `openocd-nrf5`, and **UF2** flashing (UF2 builder is included via `uf2.board.cmake`). UF2 is the expected end-user method (double-tap reset → copy `.uf2`).

## Key external references (already wired in `config/west.yml`)

- ZMK: `zmkfirmware/zmk` @ `main` (via `import: app/west.yml`)
- ZMK Studio: enabled in build matrix, used via `studio_unlock` combos
- keymap-drawer: `caksoylar/keymap-drawer` workflow

Don't add new modules to `config/west.yml` unless you really need them — the upstream ZMK repo already pulls in everything ZMK-Studio / RGB / battery / ext-power / etc. need.

## USB power budget and WS2812 brightness

The WS2812 strip draws ~60 mA per LED at full white (20 mA per R/G/B
channel). With 18 LEDs, the theoretical peak is ~1.1 A — far above the
USB 2.0 budget of 500 mA. As brightness rises, the strip's instantaneous
current draw during refresh causes VBUS to sag, which can brown out the
USB data lines (host sees the device as disconnected until brightness
drops back down).

The brightness values in `geulis_defconfig` (`ZMK_RGB_UNDERGLOW_BRT_MIN=10`,
`BRT_MAX=70`, in **percent**) keep the strip under ~300 mA average on
USB, leaving headroom for BLE (~10 mA) and the nRF52840 itself.

| `BRT_MAX` | Per-LED duty | Total avg current (18 LEDs) | USB-safe? |
|-----------|--------------|------------------------------|-----------|
| 50  | ~20% | ~216 mA | yes |
| **70** (default) | **~27%** | **~300 mA** | **yes — recommended cap** |
| 80  | ~31% | ~340 mA | yes |
| 90  | ~35% | ~380 mA | borderline |
| 100 | ~39% | ~420 mA | risky on some hosts |

If the user reports USB dropouts on a particular host, lower `BRT_MAX`.
The Kconfig symbol is **percent (0–100)**, not 0–255 — multiplying by
2.55 gives the 8-bit PWM equivalent.

`CONFIG_GEULIS_RGB_UNDERGLOW_AUTO_OFF_USB` is named misleadingly: it
turns off the strip when USB is **disconnected** (i.e., on battery).
Leaving it on saves battery at the cost of LED glow when plugged in.

## Quick checklist for common changes

- **Add a new layer:** add a `display-name = "..."` block to `keymap { ... }` in `geulis.keymap`, keep its matrix-row counts (5 rows, total ~62 positions) consistent with the ASCII diagram comment.
- **Add a new behavior:** use the `MORPH(...)` / `ENCODER(...)` macros at the top of `geulis.keymap`; reference it as `&your_name` in a binding.
- **Add a new combo:** append to `combos { ... }` — note that `<key-positions = <...>>` are matrix positions, not key labels.
- **Add a new indicator:** append a child to the `indicators` node in `boards/arm/geulis/geulis.dts` with `compatible = "zmk,indicator-leds-entry"` and either `indicator = <N>` or `layer = <N>`. Reuse existing `gpio-leds` children for the `leds` array.
- **Disable an unused encoder:** flip `GEULIS_ENCODER_MID_ON` or `GEULIS_ENCODER_BOT_ON` to `0` in `boards/arm/geulis/geulis_options.h` (and set `CONFIG_GEULIS_DRIVER_ENCODER` to `n` if disabling all three). Default is `1` for all three so users can solder an encoder in without re-flashing.
- **Disable RGB underglow:** flip `GEULIS_RGB_UNDERGLOW_ON` to `0` in `geulis_options.h` AND `CONFIG_GEULIS_DRIVER_RGB_UNDERGLOW` to `n` in `geulis_defconfig`. Also remove `&rgb_ug` bindings from `geulis.keymap`.
- **Change RGB defaults:** `geulis_defconfig` (`CONFIG_ZMK_RGB_UNDERGLOW_*`).
- **Change sleep timeout:** `geulis.conf` (`CONFIG_ZMK_IDLE_SLEEP_TIMEOUT`).
- **Update the rendered keymap image:** push to main; CI commits `keymap-drawer/geulis.svg` into your commit.
- **Reset user settings on the device:** flash `geulis-zmk-reset-settings` from the latest release.