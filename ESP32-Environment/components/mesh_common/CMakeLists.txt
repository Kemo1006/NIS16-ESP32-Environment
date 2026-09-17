idf_component_register(
    SRCS
        "src/mesh_setup.c"
        "src/phase_listener.c"
        "src/csv_logger.c"
        "src/sd_status.c"
        "src/node_identity.c"
    INCLUDE_DIRS
        "include"
    REQUIRES
        nvs_flash
        esp_wifi
        esp_netif
        esp_event
        spiffs
        fatfs      # sd_status.c: esp_vfs_fat.h / sdmmc mount (SD card status report)
        esp_app_format  # sd_status.c: esp_app_desc.h (the image's own build date/time)
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

# ACTIVE_ATTACK is also defined in root_node/main and child_node/main, but those
# are PRIVATE to the main component — sd_status.c lives here, so without this it
# would read the #ifndef ATTACK_NONE fallback in mesh_config.h and file every run
# under baseline/ regardless of the actual build. Same scoping rationale as
# MESH_TOPOLOGY above: a mode switch recompiles this component, not the IDF tree.
if(DEFINED ACTIVE_ATTACK)
    target_compile_definitions(${COMPONENT_LIB} PRIVATE ACTIVE_ATTACK=${ACTIVE_ATTACK})
endif()