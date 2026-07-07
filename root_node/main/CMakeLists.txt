idf_component_register(
    SRCS "root_main.c"
    INCLUDE_DIRS "."
    REQUIRES
        mesh_common
        esp_wifi
        esp_timer
        freertos
        log
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)

# Attack selection (Milestone 2) — scope the define to THIS component only.
# root_main.c is the sole consumer of ACTIVE_ATTACK, so defining it here (rather
# than as a global COMPILE_OPTIONS in the project CMakeLists) means switching
# baseline<->blackhole recompiles just root_main.c, not the whole ESP-IDF tree.
if(DEFINED ACTIVE_ATTACK)
    target_compile_definitions(${COMPONENT_LIB} PRIVATE ACTIVE_ATTACK=${ACTIVE_ATTACK})
endif()