find_path(ZMK_INCLUDE_DIR zmk/event_manager.h
    PATHS /zmk-workspace/zmk/app/include
    NO_DEFAULT_PATH
    REQUIRED
)
zephyr_include_directories(${ZMK_INCLUDE_DIR})

zephyr_library()
zephyr_library_sources(src/indicator_leds.c)
