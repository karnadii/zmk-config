#!/usr/bin/env bash
# build.sh — local ZMK build helper for the Geulis keyboard.
#
# Usage (inside the container):
#   ./docker/build.sh                      # build the default studio variant
#   ./docker/build.sh --studio             # (default) build ZMK Studio
#   ./docker/build.sh --logging            # build with USB CDC logging
#   ./docker/build.sh --reset              # build settings-reset firmware
#   ./docker/build.sh --clean              # wipe build artefacts
#   ./docker/build.sh --init               # run only west init + west update
#   ./docker/build.sh --shell              # drop into a bash shell
#
# From the host:
#   docker compose -f docker/docker-compose.yml run --rm build ./docker/build.sh --studio
#
# How it works:
#   1. `west init -l <ws>/config` points west at our repo's config/west.yml. We
#      copy the config dir into a separate west workspace under $WORKSPACE_ROOT
#      so that west's `zephyr/`, `modules/`, `bootloader/` checkouts don't
#      clobber the repo's own `zephyr/module.yml` and `boards/` directory.
#   2. `west update` fetches Zephyr + ZMK + all modules into the workspace.
#   3. `west zephyr-export` registers Zephyr's CMake config (needs the
#      `zmk/app/scripts/west-commands.yml` extension — our config/west.yml
#      points `self.west-commands` at it).
#   4. `west build -s zmk/app -b <keyboard> … -- -DZMK_CONFIG=<ws>/config
#      -DZMK_EXTRA_MODULES=<repo>` so the build finds our
#      `boards/arm/<keyboard>/`. Pass `--board <name>` to target a specific
#      keyboard (defaults to geulis).
#   5. Copy the resulting UF2/BIN to ./firmware/ on the host (bind-mounted).
#
# The west workspace is kept in a named docker volume (zmk_workspace_cache)
# so subsequent builds reuse the Zephyr/ZMK checkout (~5 min saved per build).

set -euo pipefail

# /workspace is bind-mounted to the host repo (see docker-compose.yml).
# ZMK_CONFIG points at the *copy* in the west workspace (so west's module
# scanner stays inside it), and ZMK_EXTRA_MODULES points at the *real* repo
# (so the `boards/arm/geulis/` directory is found).
ROOT="${WORKSPACE:-/workspace}"          # bind-mounted repo root
WORKSPACE_ROOT="/zmk-workspace"          # scratch workspace for west (named volume)
FIRMWARE_DIR="${ROOT}/firmware"
BUILD_DIR="${WORKSPACE_ROOT}/build"
CONFIG_DIR="${WORKSPACE_ROOT}/config"

mkdir -p "${FIRMWARE_DIR}"

action=regular
want_shell=false
want_init=false
want_clean=false
target_board="geulis"
target_shield=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --regular)   action=regular ;;
        --studio)    action=studio ;;
        --logging)   action=logging ;;
        --reset)     action=reset ;;
        --clean)     want_clean=true ;;
        --init)      want_init=true ;;
        --shell)     want_shell=true ;;
        --board)
            shift
            target_board="$1"
            ;;
        --shield)
            shift
            target_shield="$1"
            ;;
        -h|--help)
            cat <<'USAGE'
Usage:
  build.sh                       Build the default (regular) firmware for geulis
  build.sh --regular             Build plain USB HID + BLE firmware -> <board>-zmk.uf2
  build.sh --studio              Build with ZMK Studio USB RPC -> <board>-zmk-studio.uf2
  build.sh --logging             Build with USB CDC logging -> <board>-zmk-logging.uf2
  build.sh --reset               Build settings-reset firmware -> <board>-zmk-reset.uf2
  build.sh --board <name>        Target a specific Kconfig board (default: geulis)
  build.sh --shield <name>       Target a specific shield (e.g. marvelous65_split_left)
  build.sh --init                Run only west init + west update
  build.sh --clean               Wipe build artefacts
  build.sh --shell               Drop into a shell (env already configured)

Note: --studio needs the board to declare a zmk,physical-layout. Marvelous65
will fail to compile --studio until the layout is added (it fails with a
clear C static_assert, not a wrapper-side block).

Split keyboards: use --board <name> --shield <half>. Default board is geulis;
split shields default to --board nrfmicro_13 since they're designed against
the Pro Micro pinout. Upstream Sofle automatically builds the right half as
central and the left half as peripheral.
USAGE
            exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1 ;;
    esac
    shift
done

if $want_clean; then
    echo ">> Cleaning previous build artefacts…"
    rm -rf "${BUILD_DIR:?}"/* "${FIRMWARE_DIR:?}"/*
    exit 0
fi

if $want_shell; then
    echo ">> Dropping you into a bash shell. West workspace at ${WORKSPACE_ROOT}."
    exec bash
fi

# --- sync the user-config dir into the west workspace --------------------------
mkdir -p "${WORKSPACE_ROOT}"
if [[ ! -L "${CONFIG_DIR}" ]]; then
    # First run (or after --clean): copy config/ into the workspace.
    rm -rf "${CONFIG_DIR}"
    cp -R "${ROOT}/config" "${CONFIG_DIR}"
fi

# --- initialise west workspace --------------------------------------------------
cd "${WORKSPACE_ROOT}"
if [[ ! -d "${WORKSPACE_ROOT}/.west" ]]; then
    echo ">> Initialising west workspace at ${WORKSPACE_ROOT}"
    west init -l "${CONFIG_DIR}"
fi

if $want_init; then
    echo ">> Running 'west update'…"
    west update --fetch-opt=--filter=tree:0
    exit 0
fi

# Fetch modules if not present.
if [[ ! -d "${WORKSPACE_ROOT}/zmk" ]]; then
    echo ">> Running 'west update' to fetch Zephyr + ZMK (≈5 min on first run)…"
    west update --fetch-opt=--filter=tree:0
fi

# `west zephyr-export` writes Zephyr's CMake package config into
# ~/.cmake/packages/Zephyr. We re-run it on every invocation because each
# `docker compose run` starts a fresh container with an empty home dir.
west zephyr-export >/dev/null

# --- pick snippet/shield/artifact based on the action ---------------------------
# When --shield is set, default the Kconfig board to nrfmicro_13
# (the Pro Micro pin-compatible board the split shields target).
if [[ -n "${target_shield}" && "${target_board}" == "geulis" ]]; then
    target_board="nrfmicro_13"
fi

board="${target_board}"
snippet=""
shield="${target_shield}"
# When a shield is set, embed its name in the artifact so left/right
# halves don't clobber each other (e.g. marvelous65_split_left-zmk.uf2).
if [[ -n "${shield}" ]]; then
    artifact_prefix="${target_board}-${shield}-zmk"
else
    artifact_prefix="${target_board}-zmk"
fi
cmake_extra=""

case "$action" in
    regular)
        artifact="${artifact_prefix}" ;;
    studio)
        snippet="studio-rpc-usb-uart"
        cmake_extra="-DCONFIG_ZMK_STUDIO=y"
        artifact="${artifact_prefix}-studio" ;;
    logging)
        snippet="zmk-usb-logging"
        artifact="${artifact_prefix}-logging" ;;
    reset)
        # The settings_reset shield resets the whole board's settings,
        # which includes the user's shield's settings. So we layer it
        # on top via -DSHIELD="settings_reset;marvelous65_split_left"-
        # style syntax (ZMK accepts a ';' separated shield list).
        if [[ -n "${shield}" ]]; then
            shield="settings_reset;${shield}"
        else
            shield="settings_reset"
        fi
        artifact="${artifact_prefix}-reset" ;;
    *)
        echo "Unknown action: ${action}" >&2
        exit 1 ;;
esac

target_build="${BUILD_DIR}/${artifact}"
echo ">> Building ${artifact} (board=${board}${shield:+ shield=${shield}}${snippet:+ snippet=${snippet}})"
echo "   CMake args: ${cmake_extra}"
echo "   Output will land in ${target_build} and ${FIRMWARE_DIR}/${artifact}.uf2"

extra_args=()
[[ -n "${snippet}" ]] && extra_args+=(-S "${snippet}")

# shields are passed as a CMake variable (see upstream CI's
# `extra_cmake_args=${shield:+-DSHIELD=...}`), not a west flag.
cmake_args=(
    "-DZMK_CONFIG=${CONFIG_DIR}"
    # The user-config repo (with boards/arm/geulis/) is registered as an
    # extra ZMK module. Mirrors the upstream CI:
    # https://github.com/zmkfirmware/zmk/blob/v0.3/.github/workflows/build-user-config.yml
    "-DZMK_EXTRA_MODULES=${ROOT}"
    ${cmake_extra}
)
[[ -n "${shield}"  ]] && cmake_args+=("-DSHIELD=${shield}")

# ZMK v0.3's upstream Sofle shield defaults sofle_left to central. This
# keyboard intentionally uses the right half as the central/master, so
# override the role per half for local builds too.
case "${shield}" in
    sofle_right|*";sofle_right")
        cmake_args+=("-DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=y")
        ;;
    sofle_left|*";sofle_left")
        cmake_args+=("-DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=n")
        ;;
esac

west build \
    -s zmk/app \
    -d "${target_build}" \
    -b "${board}" \
    "${extra_args[@]}" \
    -- "${cmake_args[@]}"

# --- copy artefacts to firmware/ ------------------------------------------------
mkdir -p "${FIRMWARE_DIR}"
if [[ -f "${target_build}/zephyr/zmk.uf2" ]]; then
    cp "${target_build}/zephyr/zmk.uf2" "${FIRMWARE_DIR}/${artifact}.uf2"
    echo ">> OK: wrote ${FIRMWARE_DIR}/${artifact}.uf2"
elif [[ -f "${target_build}/zephyr/zmk.bin" ]]; then
    cp "${target_build}/zephyr/zmk.bin" "${FIRMWARE_DIR}/${artifact}.bin"
    echo ">> OK: wrote ${FIRMWARE_DIR}/${artifact}.bin"
else
    echo "!! Build succeeded but no UF2/BIN found in ${target_build}/zephyr/ — check the log above." >&2
    exit 2
fi
