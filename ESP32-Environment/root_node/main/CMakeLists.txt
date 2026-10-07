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

# Run scenario / traffic profile (run.ps1 -Scenario). Burst (1): the root holds
# an attack-length baseline window so the target child's burst lands at the same
# offset as in an attack run. Highload (2, since oct. 7, 2026): root_main.c logs
# probe arrivals to the SD card only, batched (csv_logger_set_arrivals_sd_only)
# so the root keeps up with ~28 rows/s. Jitter (3): randomised windows.
# Roster gate (run.ps1 -ExpectedChildren): children that must be in the mesh
# before Phase 0. Always passed explicitly by run.ps1 (0 = off), so a value
# cached in this build dir from an earlier run can never leak into this one.
if(DEFINED EXPECTED_CHILDREN)
    target_compile_definitions(${COMPONENT_LIB} PRIVATE EXPECTED_CHILDREN=${EXPECTED_CHILDREN})
    message(STATUS "root_node: EXPECTED_CHILDREN=${EXPECTED_CHILDREN} (0 = roster gate off)")
endif()

if(DEFINED TRAFFIC_PROFILE)
    target_compile_definitions(${COMPONENT_LIB} PRIVATE TRAFFIC_PROFILE=${TRAFFIC_PROFILE})
    message(STATUS "root_node: TRAFFIC_PROFILE=${TRAFFIC_PROFILE} (1=burst 2=highload 3=jitter)")
endif()
