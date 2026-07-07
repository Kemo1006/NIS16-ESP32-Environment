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

# M3 topology selection (idf.py -DMESH_TOPOLOGY=N build) — scoped to THIS
# component only, since mesh_setup.c (here) is the sole consumer. Scoping it
# here instead of as a global project-wide compile option means switching
# topology recompiles ~3 files, not the whole ESP-IDF tree (see esp32-issues.md
# I-009, which fixed the same class of problem for ACTIVE_ATTACK).
if(DEFINED MESH_TOPOLOGY)
    target_compile_definitions(${COMPONENT_LIB} PRIVATE MESH_TOPOLOGY=${MESH_TOPOLOGY})
endif()