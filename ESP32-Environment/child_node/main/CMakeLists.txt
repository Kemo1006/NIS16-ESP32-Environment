# Milestone-2 attack selection (matches root_node). Pick the victim firmware by
# the ACTIVE_ATTACK build flag; a plain build uses the normal M1 victim. Build
# all boards in a run with the SAME flag.
#   -DACTIVE_ATTACK=1  → blackhole_victim.c (drops probes during phase 1)
#   -DACTIVE_ATTACK=2  → wormhole_victim.c  (tunnels probes during phase 2);
#                        the two attacker boards ALSO pass -DWORMHOLE_END=0 (A,
#                        exit) / =1 (B, entry). Default end is A if unspecified.
if(DEFINED ACTIVE_ATTACK AND ACTIVE_ATTACK EQUAL 1)
    # Blackhole (relay model): role 0 = attacker relay (blackhole_victim.c),
    # role 1 = an ordinary victim (victim_main.c). Default role 0 if unspecified.
    #
    # Since C7 Option 1 (D-12) a blackhole VICTIM is byte-for-byte a normal
    # victim: it sends to its PARENT hop-by-hop like every other node and no
    # longer needs to know the attacker exists. BLACKHOLE_ROLE still matters
    # because it selects WHICH SOURCE FILE is built (attacker relay vs victim) -
    # it just no longer changes how the victim addresses its probes.
    if(NOT DEFINED BLACKHOLE_ROLE)
        set(BLACKHOLE_ROLE 0)
    endif()
    if(BLACKHOLE_ROLE EQUAL 1)
        set(VICTIM_SRC "victim_main.c")
        message(STATUS "child_node: building BLACKHOLE VICTIM "
                       "(ACTIVE_ATTACK=1, BLACKHOLE_ROLE=1)")
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

# BLACKHOLE_VICTIM_TARGET was removed by C7 Option 1 (D-12). It used to tell
# victim_main.c to address its probes to BLACKHOLE_ATTACKER_MAC instead of the
# root. Victims now send to their PARENT hop-by-hop and the attacker intercepts
# whatever transits it because of WHERE IT SITS, so nothing consumes that define
# any more. Deliberately not left defined-but-unused: a stale flag that still
# appears in the build output reads as if the old targeting were still active.

# Run scenario / traffic profile (run.ps1 -Scenario). Scoped to THIS component:
# the victim sources are the only consumers (mesh_config.h derives
# PROBE_INTERVAL_MS from it). 1 = burst (this board is the burst sender),
# 2 = highload (250 ms probes, whole run). Omitted = plain, unchanged firmware.
if(DEFINED TRAFFIC_PROFILE)
    target_compile_definitions(${COMPONENT_LIB} PRIVATE TRAFFIC_PROFILE=${TRAFFIC_PROFILE})
    message(STATUS "child_node: TRAFFIC_PROFILE=${TRAFFIC_PROFILE} (1=burst 2=highload)")
endif()
