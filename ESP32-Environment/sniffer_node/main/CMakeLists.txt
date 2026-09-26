idf_component_register(
    SRCS "sniffer_main.c"
    INCLUDE_DIRS "."
    REQUIRES
        esp_wifi
        esp_event
        nvs_flash
        esp_driver_uart
        esp_timer
        esp_ringbuf
        log
)

# mesh_config.h only (MESH_CHANNEL / MESH_FORCE_HT20), so the sniffer can never
# listen on a different channel than the mesh it is meant to witness.
target_include_directories(${COMPONENT_LIB} PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../../components/mesh_common/include")

target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
