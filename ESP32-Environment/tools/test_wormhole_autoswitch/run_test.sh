#!/usr/bin/env bash
# Host test of the wormhole A/B auto-switch. Needs any gcc (MSYS2 mingw64 works).
#   bash tools/test_wormhole_autoswitch/run_test.sh       # summary
#   bash tools/test_wormhole_autoswitch/run_test.sh -v    # + the firmware's log lines
set -e
here="$(cd "$(dirname "$0")" && pwd)"
env_dir="$here/../.."
inc="-I$here/stubs -I$here -I$env_dir/components/mesh_common/include"
out="${TMPDIR:-/tmp}/wh_autoswitch_test"
mkdir -p "$out"
flags="-std=gnu11 -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-parameter -DACTIVE_ATTACK=2"
gcc $flags $inc -DBOARD=b1 -DWORMHOLE_END=1 -c "$here/board.c" -o "$out/b1.o"
gcc $flags $inc -DBOARD=b2 -DWORMHOLE_END=0 -c "$here/board.c" -o "$out/b2.o"
gcc $flags $inc -c "$here/test.c" -o "$out/test.o"
gcc "$out/b1.o" "$out/b2.o" "$out/test.o" -o "$out/wh_test"
"$out/wh_test" "$@"
