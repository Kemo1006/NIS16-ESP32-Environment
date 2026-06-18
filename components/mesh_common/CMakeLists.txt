idf_component_register(
    SRCS
        "src/mesh_setup.c"
        "src/phase_listener.c"
        "src/csv_logger.c"
    INCLUDE_DIRS
        "include"
    REQUIRES
        nvs_flash
        esp_wifi
        esp_netif
        esp_event
        spiffs
        driver
        freertos
        esp_timer
        log
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)