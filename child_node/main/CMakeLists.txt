# Milestone-2 attack selection (matches root_node). Pick the victim firmware by
# the ACTIVE_ATTACK build flag; a plain build uses the normal M1 victim. Build
# all boards in a run with the SAME flag.
#   -DACTIVE_ATTACK=1  → blackhole_victim.c (drops probes during phase 1)
#   -DACTIVE_ATTACK=2  → wormhole_victim.c  (tunnels probes during phase 2);
#                        the two attacker boards ALSO pass -DWORMHOLE_END=0 (A,
#                        exit) / =1 (B, entry). Default end is A if unspecified.
if(DEFINED ACTIVE_ATTACK AND ACTIVE_ATTACK EQUAL 1)
    # Blackhole (relay model): role 0 = attacker relay (blackhole_victim.c),
    # role 1 = a victim that addresses the attacker's MAC (victim_main.c built
    # with BLACKHOLE_VICTIM_TARGET). Default role 0 if unspecified.
    if(NOT DEFINED BLACKHOLE_ROLE)
        set(BLACKHOLE_ROLE 0)
    endif()
    if(BLACKHOLE_ROLE EQUAL 1)
        set(VICTIM_SRC "victim_main.c")
        message(STATUS "child_node: building BLACKHOLE VICTIM "
                       "(ACTIVE_ATTACK=1, BLACKHOLE_ROLE=1, targets attacker MAC)")
    else()
        set(VICTIM_SRC "blackhole_victim.c")
        message(STATUS "child_node: building BLACKHOLE ATTACKER relay "
                       "(ACTIVE_ATTACK=1, BLACKHOLE_ROLE=0)")
    endif()
elseif(DEFINED ACTIVE_ATTACK AND ACTIVE_ATTACK EQUAL 2)
    set(VICTIM_SRC "wormhole_victim.c")
    if(NOT DEFINED WORMHOLE_END)
        set(WORMHOLE_END 0)
    endif()
    message(STATUS "child_node: building WORMHOLE firmware "
                   "(ACTIVE_ATTACK=2, WORMHOLE_END=${WORMHOLE_END})")
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

# Wormhole endpoint selection (Milestone 2, ACTIVE_ATTACK=2). Scope the define to
# THIS component — wormhole_victim.c is the only consumer, so switching A<->B
# recompiles just that file. Node A = 0 (exit), Node B = 1 (entry).
if(DEFINED WORMHOLE_END)
    target_compile_definitions(${COMPONENT_LIB} PRIVATE WORMHOLE_END=${WORMHOLE_END})
endif()

# Blackhole VICTIM (ACTIVE_ATTACK=1, BLACKHOLE_ROLE=1): tell victim_main.c to
# address its probes to the attacker's MAC (BLACKHOLE_ATTACKER_MAC) instead of
# the root. The attacker relay build (role 0) and all other builds omit this.
if(DEFINED ACTIVE_ATTACK AND ACTIVE_ATTACK EQUAL 1
   AND DEFINED BLACKHOLE_ROLE AND BLACKHOLE_ROLE EQUAL 1)
    target_compile_definitions(${COMPONENT_LIB} PRIVATE BLACKHOLE_VICTIM_TARGET=1)
endif()