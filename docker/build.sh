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
#   4. `west build -s zmk/app -b geulis … -- -DZMK_CONFIG=<ws>/config
#      -DZMK_EXTRA_MODULES=<repo>;<repo>/module` so the build finds our
#      `boards/arm/geulis/` AND the local `zmk-indicator-leds` module.
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

action=studio
want_shell=false
want_init=false
want_clean=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --studio)    action=studio ;;
        --logging)   action=logging ;;
        --reset)     action=reset ;;
        --clean)     want_clean=true ;;
        --init)      want_init=true ;;
        --shell)     want_shell=true ;;
        -h|--help)
            cat <<'USAGE'
Usage:
  build.sh                  Build the default ZMK Studio variant
  build.sh --studio         Build with ZMK Studio USB RPC
  build.sh --logging        Build with USB CDC logging
  build.sh --reset          Build settings-reset firmware
  build.sh --init           Run only west init + west update
  build.sh --clean          Wipe build artefacts
  build.sh --shell          Drop into a shell (env already configured)
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
board="geulis"
snippet=""
shield=""
artifact_prefix="geulis-zmk"
cmake_extra=""

case "$action" in
    studio)
        snippet="studio-rpc-usb-uart"
        cmake_extra="-DCONFIG_ZMK_STUDIO=y"
        artifact="${artifact_prefix}-studio" ;;
    logging)
        snippet="zmk-usb-logging"
        artifact="${artifact_prefix}-logging" ;;
    reset)
        shield="settings_reset"
        artifact="${artifact_prefix}-reset-settings" ;;
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
    # The local zmk-indicator-leds sibling module is appended so its driver
    # registers and its bindings resolve before the board DTS is compiled.
    "-DZMK_EXTRA_MODULES=${ROOT};${ROOT}/module"
    ${cmake_extra}
)
[[ -n "${shield}"  ]] && cmake_args+=("-DSHIELD=${shield}")

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