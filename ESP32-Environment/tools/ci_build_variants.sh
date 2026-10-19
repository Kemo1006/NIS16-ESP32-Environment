#!/usr/bin/env bash
# ci_build_variants.sh - compile every firmware variant on Linux, no board needed.
#
# WHY THIS EXISTS
#   build_all_variants.ps1 needs ESP-IDF installed on a Windows laptop. This is
#   the same check for GitHub Actions (.github/workflows/firmware-build.yml),
#   which runs it inside Espressif's official Docker image (espressif/idf:<ver>)
#   for BOTH IDF versions the team uses (v5.3.5 and v5.5.4 - see CLAUDE.md:
#   a build that is clean on one can fail -Werror on the other).
#
#   It also covers what build_all_variants.ps1 does not: every MESH_TOPOLOGY
#   (0 star, 1 tree, 2 linear, 3 partial). mesh_setup.c compiles different code
#   per topology x attack (D-26 tree, D-28 STAR_HUB_WORMHOLE, D-30 WH_B_NO_ROOT),
#   so a topology-0-only build never compiles most of it.
#
# FLAGS = what run.ps1 passes (run.ps1:439-540): EXPECTED_CHILDREN on every root,
#   BH_ATTACKER_MAC_HEX on every build (0 = none; a real MAC for blackhole victims
#   and star + wormhole children, where it is the hub = end A).
#
# "0 warnings": root_node/main, child_node/main and components/mesh_common build
#   with -Wall -Wextra -Werror, so any warning in OUR code fails the build. Warnings
#   inside ESP-IDF itself are not ours and are not counted.
#
# USAGE (inside an ESP-IDF shell or the espressif/idf container, from any dir):
#     bash ESP32-Environment/tools/ci_build_variants.sh [all|root|child|blackhole|wormhole|tools]
# Logs: $CI_LOG_DIR (default /tmp/ci_logs), one file per variant.

set -u
GROUP="${1:-all}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"          # .../ESP32-Environment
BUILD_ROOT="${CI_BUILD_ROOT:-/tmp/ci_builds}"
LOG_DIR="${CI_LOG_DIR:-/tmp/ci_logs}"
mkdir -p "$BUILD_ROOT" "$LOG_DIR"

if ! command -v idf.py >/dev/null 2>&1; then
    echo "idf.py not found - source \$IDF_PATH/export.sh first." >&2
    exit 2
fi

MAC='0x24DCC3A1B2C4ULL'   # any well-formed MAC; only its format matters for a compile check

# group | name | project | text CMake must print ('-' = none) | -D flags
VARIANTS=$(cat <<EOF
root|ROOT star|root_node|-|-DACTIVE_ATTACK=255 -DMESH_TOPOLOGY=0 -DEXPECTED_CHILDREN=7 -DBH_ATTACKER_MAC_HEX=0
root|ROOT tree|root_node|-|-DACTIVE_ATTACK=255 -DMESH_TOPOLOGY=1 -DEXPECTED_CHILDREN=7 -DBH_ATTACKER_MAC_HEX=0
root|ROOT linear|root_node|-|-DACTIVE_ATTACK=255 -DMESH_TOPOLOGY=2 -DEXPECTED_CHILDREN=7 -DBH_ATTACKER_MAC_HEX=0
root|ROOT partial|root_node|-|-DACTIVE_ATTACK=255 -DMESH_TOPOLOGY=3 -DEXPECTED_CHILDREN=7 -DBH_ATTACKER_MAC_HEX=0
root|ROOT blackhole star|root_node|-|-DACTIVE_ATTACK=1 -DMESH_TOPOLOGY=0 -DEXPECTED_CHILDREN=7 -DBH_ATTACKER_MAC_HEX=0
root|ROOT blackhole tree|root_node|-|-DACTIVE_ATTACK=1 -DMESH_TOPOLOGY=1 -DEXPECTED_CHILDREN=7 -DBH_ATTACKER_MAC_HEX=0
root|ROOT blackhole linear|root_node|-|-DACTIVE_ATTACK=1 -DMESH_TOPOLOGY=2 -DEXPECTED_CHILDREN=7 -DBH_ATTACKER_MAC_HEX=0
root|ROOT blackhole partial|root_node|-|-DACTIVE_ATTACK=1 -DMESH_TOPOLOGY=3 -DEXPECTED_CHILDREN=7 -DBH_ATTACKER_MAC_HEX=0
root|ROOT wormhole star|root_node|-|-DACTIVE_ATTACK=2 -DMESH_TOPOLOGY=0 -DEXPECTED_CHILDREN=7 -DBH_ATTACKER_MAC_HEX=0
root|ROOT wormhole tree|root_node|-|-DACTIVE_ATTACK=2 -DMESH_TOPOLOGY=1 -DEXPECTED_CHILDREN=7 -DBH_ATTACKER_MAC_HEX=0
root|ROOT wormhole linear|root_node|-|-DACTIVE_ATTACK=2 -DMESH_TOPOLOGY=2 -DEXPECTED_CHILDREN=7 -DBH_ATTACKER_MAC_HEX=0
root|ROOT wormhole partial|root_node|-|-DACTIVE_ATTACK=2 -DMESH_TOPOLOGY=3 -DEXPECTED_CHILDREN=7 -DBH_ATTACKER_MAC_HEX=0
root|ROOT burst|root_node|TRAFFIC_PROFILE=1|-DACTIVE_ATTACK=255 -DMESH_TOPOLOGY=1 -DTRAFFIC_PROFILE=1 -DEXPECTED_CHILDREN=7 -DBH_ATTACKER_MAC_HEX=0
root|ROOT highload|root_node|TRAFFIC_PROFILE=2|-DACTIVE_ATTACK=1 -DMESH_TOPOLOGY=1 -DTRAFFIC_PROFILE=2 -DEXPECTED_CHILDREN=7 -DBH_ATTACKER_MAC_HEX=0
root|ROOT jitter|root_node|TRAFFIC_PROFILE=3|-DACTIVE_ATTACK=255 -DMESH_TOPOLOGY=1 -DTRAFFIC_PROFILE=3 -DEXPECTED_CHILDREN=7 -DBH_ATTACKER_MAC_HEX=0
child|CHILD star|child_node|-|-DACTIVE_ATTACK=255 -DMESH_TOPOLOGY=0 -DBH_ATTACKER_MAC_HEX=0
child|CHILD tree|child_node|-|-DACTIVE_ATTACK=255 -DMESH_TOPOLOGY=1 -DBH_ATTACKER_MAC_HEX=0
child|CHILD linear|child_node|-|-DACTIVE_ATTACK=255 -DMESH_TOPOLOGY=2 -DBH_ATTACKER_MAC_HEX=0
child|CHILD partial|child_node|-|-DACTIVE_ATTACK=255 -DMESH_TOPOLOGY=3 -DBH_ATTACKER_MAC_HEX=0
child|CHILD burst target|child_node|TRAFFIC_PROFILE=1|-DACTIVE_ATTACK=255 -DMESH_TOPOLOGY=1 -DTRAFFIC_PROFILE=1 -DBH_ATTACKER_MAC_HEX=0
child|CHILD highload|child_node|TRAFFIC_PROFILE=2|-DACTIVE_ATTACK=255 -DMESH_TOPOLOGY=1 -DTRAFFIC_PROFILE=2 -DBH_ATTACKER_MAC_HEX=0
blackhole|BH attacker star|child_node|BLACKHOLE ATTACKER|-DACTIVE_ATTACK=1 -DBLACKHOLE_ROLE=0 -DMESH_TOPOLOGY=0 -DBH_ATTACKER_MAC_HEX=0
blackhole|BH attacker tree|child_node|BLACKHOLE ATTACKER|-DACTIVE_ATTACK=1 -DBLACKHOLE_ROLE=0 -DMESH_TOPOLOGY=1 -DBH_ATTACKER_MAC_HEX=0
blackhole|BH attacker linear|child_node|BLACKHOLE ATTACKER|-DACTIVE_ATTACK=1 -DBLACKHOLE_ROLE=0 -DMESH_TOPOLOGY=2 -DBH_ATTACKER_MAC_HEX=0
blackhole|BH attacker partial|child_node|BLACKHOLE ATTACKER|-DACTIVE_ATTACK=1 -DBLACKHOLE_ROLE=0 -DMESH_TOPOLOGY=3 -DBH_ATTACKER_MAC_HEX=0
blackhole|BH victim star|child_node|BLACKHOLE VICTIM|-DACTIVE_ATTACK=1 -DBLACKHOLE_ROLE=1 -DMESH_TOPOLOGY=0 -DBH_ATTACKER_MAC_HEX=$MAC
blackhole|BH victim tree|child_node|BLACKHOLE VICTIM|-DACTIVE_ATTACK=1 -DBLACKHOLE_ROLE=1 -DMESH_TOPOLOGY=1 -DBH_ATTACKER_MAC_HEX=$MAC
blackhole|BH victim linear|child_node|BLACKHOLE VICTIM|-DACTIVE_ATTACK=1 -DBLACKHOLE_ROLE=1 -DMESH_TOPOLOGY=2 -DBH_ATTACKER_MAC_HEX=$MAC
blackhole|BH victim partial|child_node|BLACKHOLE VICTIM|-DACTIVE_ATTACK=1 -DBLACKHOLE_ROLE=1 -DMESH_TOPOLOGY=3 -DBH_ATTACKER_MAC_HEX=$MAC
blackhole|BH attacker highload|child_node|BLACKHOLE ATTACKER|-DACTIVE_ATTACK=1 -DBLACKHOLE_ROLE=0 -DMESH_TOPOLOGY=1 -DTRAFFIC_PROFILE=2 -DBH_ATTACKER_MAC_HEX=0
blackhole|BH victim highload|child_node|BLACKHOLE VICTIM|-DACTIVE_ATTACK=1 -DBLACKHOLE_ROLE=1 -DMESH_TOPOLOGY=1 -DTRAFFIC_PROFILE=2 -DBH_ATTACKER_MAC_HEX=$MAC
blackhole|BH victim burst|child_node|BLACKHOLE VICTIM|-DACTIVE_ATTACK=1 -DBLACKHOLE_ROLE=1 -DMESH_TOPOLOGY=1 -DTRAFFIC_PROFILE=1 -DBH_ATTACKER_MAC_HEX=$MAC
wormhole|WH end A star (hub)|child_node|WORMHOLE_END=0|-DACTIVE_ATTACK=2 -DWORMHOLE_ROLE=0 -DWORMHOLE_END=0 -DMESH_TOPOLOGY=0 -DBH_ATTACKER_MAC_HEX=$MAC
wormhole|WH end A tree|child_node|WORMHOLE_END=0|-DACTIVE_ATTACK=2 -DWORMHOLE_ROLE=0 -DWORMHOLE_END=0 -DMESH_TOPOLOGY=1 -DBH_ATTACKER_MAC_HEX=0
wormhole|WH end A linear|child_node|WORMHOLE_END=0|-DACTIVE_ATTACK=2 -DWORMHOLE_ROLE=0 -DWORMHOLE_END=0 -DMESH_TOPOLOGY=2 -DBH_ATTACKER_MAC_HEX=0
wormhole|WH end A partial|child_node|WORMHOLE_END=0|-DACTIVE_ATTACK=2 -DWORMHOLE_ROLE=0 -DWORMHOLE_END=0 -DMESH_TOPOLOGY=3 -DBH_ATTACKER_MAC_HEX=0
wormhole|WH end B star|child_node|WORMHOLE_END=1|-DACTIVE_ATTACK=2 -DWORMHOLE_ROLE=0 -DWORMHOLE_END=1 -DMESH_TOPOLOGY=0 -DBH_ATTACKER_MAC_HEX=$MAC
wormhole|WH end B tree|child_node|WORMHOLE_END=1|-DACTIVE_ATTACK=2 -DWORMHOLE_ROLE=0 -DWORMHOLE_END=1 -DMESH_TOPOLOGY=1 -DBH_ATTACKER_MAC_HEX=0
wormhole|WH end B linear|child_node|WORMHOLE_END=1|-DACTIVE_ATTACK=2 -DWORMHOLE_ROLE=0 -DWORMHOLE_END=1 -DMESH_TOPOLOGY=2 -DBH_ATTACKER_MAC_HEX=0
wormhole|WH end B partial|child_node|WORMHOLE_END=1|-DACTIVE_ATTACK=2 -DWORMHOLE_ROLE=0 -DWORMHOLE_END=1 -DMESH_TOPOLOGY=3 -DBH_ATTACKER_MAC_HEX=0
wormhole|WH plain child star|child_node|WORMHOLE-RUN VICTIM|-DACTIVE_ATTACK=2 -DWORMHOLE_ROLE=1 -DMESH_TOPOLOGY=0 -DBH_ATTACKER_MAC_HEX=$MAC
wormhole|WH plain child tree|child_node|WORMHOLE-RUN VICTIM|-DACTIVE_ATTACK=2 -DWORMHOLE_ROLE=1 -DMESH_TOPOLOGY=1 -DBH_ATTACKER_MAC_HEX=0
wormhole|WH plain child linear|child_node|WORMHOLE-RUN VICTIM|-DACTIVE_ATTACK=2 -DWORMHOLE_ROLE=1 -DMESH_TOPOLOGY=2 -DBH_ATTACKER_MAC_HEX=0
wormhole|WH plain child partial|child_node|WORMHOLE-RUN VICTIM|-DACTIVE_ATTACK=2 -DWORMHOLE_ROLE=1 -DMESH_TOPOLOGY=3 -DBH_ATTACKER_MAC_HEX=0
wormhole|WH end A highload|child_node|WORMHOLE_END=0|-DACTIVE_ATTACK=2 -DWORMHOLE_ROLE=0 -DWORMHOLE_END=0 -DMESH_TOPOLOGY=1 -DTRAFFIC_PROFILE=2 -DBH_ATTACKER_MAC_HEX=0
wormhole|WH end B highload|child_node|WORMHOLE_END=1|-DACTIVE_ATTACK=2 -DWORMHOLE_ROLE=0 -DWORMHOLE_END=1 -DMESH_TOPOLOGY=1 -DTRAFFIC_PROFILE=2 -DBH_ATTACKER_MAC_HEX=0
tools|SNIFFER|sniffer_node|-|
tools|UART link test|uart_link_test|-|
tools|SD card test|sd_card_test|-|
EOF
)

summary="$LOG_DIR/summary.md"
printf '| Variant | Result | Our warnings | Selected source |\n|---|---|---|---|\n' > "$summary"
n=0; failed=0
while IFS='|' read -r grp name proj expect flags; do
    [ -z "$grp" ] && continue
    [ "$GROUP" != "all" ] && [ "$GROUP" != "$grp" ] && continue
    n=$((n + 1))
    slug=$(printf '%s' "$name" | tr -c 'A-Za-z0-9' '_')
    bld="$BUILD_ROOT/$slug"
    log="$LOG_DIR/$slug.log"
    echo "::group::[$n] $name ($proj) $flags"
    rm -rf "$bld"
    # shellcheck disable=SC2086  # $flags is a list of -D arguments on purpose
    # < /dev/null: the build must not eat the variant list this loop reads from stdin
    ( cd "$HERE/$proj" && idf.py -B "$bld" $flags build ) < /dev/null > "$log" 2>&1
    code=$?
    tail -n 25 "$log"
    echo "::endgroup::"

    # gcc diagnostics in OUR sources only (ESP-IDF's own files are not ours).
    ours=$(grep -E '^[^ ]*/(root_node|child_node|components/mesh_common|sniffer_node|uart_link_test|sd_card_test)/[^ ]*:[0-9]+:[0-9]+: warning:' "$log" | sort -u | wc -l)
    selected='-'
    result='OK'
    if [ "$expect" != "-" ]; then
        if grep -qF "$expect" "$log"; then selected="$expect"; else result='WRONG VARIANT'; fi
    fi
    [ "$code" -ne 0 ] && result='FAILED'
    [ "$ours" -gt 0 ] && [ "$result" = "OK" ] && result='WARNINGS'
    if [ "$result" != "OK" ]; then
        failed=$((failed + 1))
        echo "::error title=$name::$result (exit $code, $ours warning(s) in our code) - see $log"
        grep -E ': (error|warning):' "$log" | grep -v '/esp-idf/' | sort -u | head -20
    fi
    printf '| %s | %s | %s | %s |\n' "$name" "$result" "$ours" "$selected" >> "$summary"
    rm -rf "$bld"   # keep disk use flat; ccache keeps the next build fast
done <<< "$VARIANTS"

if [ "$n" -eq 0 ]; then
    echo "No variants in group '$GROUP' (use all|root|child|blackhole|wormhole|tools)." >&2
    exit 2
fi
printf '\n**%s: %d variant(s), %d not clean.** IDF %s\n' "$GROUP" "$n" "$failed" "$(idf.py --version 2>/dev/null)" >> "$summary"
cat "$summary"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && cat "$summary" >> "$GITHUB_STEP_SUMMARY"
[ "$failed" -eq 0 ]
