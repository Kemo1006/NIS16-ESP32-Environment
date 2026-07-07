# Milestone-2 attack selection (matches root_node). `-DACTIVE_ATTACK=1` builds
# the combined victim + blackhole firmware, which drops probes during the
# blackhole phase; a plain build uses the normal M1 victim. Build both boards
# with the SAME flag for a given run.
if(DEFINED ACTIVE_ATTACK AND ACTIVE_ATTACK EQUAL 1)
    set(VICTIM_SRC "blackhole_victim.c")
    message(STATUS "victim_node: building BLACKHOLE firmware (ACTIVE_ATTACK=1)")
else()
    set(VICTIM_SRC "victim_main.c")
endif()

idf_component_register(
    SRCS "${VICTIM_SRC}"
    INCLUDE_DIRS "."
    REQUIRES
        mesh_common
        esp_wifi
        esp_timer
        freertos
        log
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)