cmake_minimum_required(VERSION 3.16)

set(EXTRA_COMPONENT_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/../components")

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(root_node)

# Milestone-2 attack selection. Passed as a -D flag so no source editing is
# needed per run: `idf.py -DACTIVE_ATTACK=1 build` announces the blackhole phase;
# a plain build stays baseline-only (ACTIVE_ATTACK is #ifndef-guarded in
# mesh_config.h). Build the victim board with the SAME flag.
#
# NOTE: the actual -DACTIVE_ATTACK define is applied ONLY to the `main`
# component (see root_node/main/CMakeLists.txt), NOT globally. Applying it
# globally here (idf_build_set_property COMPILE_OPTIONS) would put it on every
# object's command line, so toggling baseline<->blackhole rebuilt the ENTIRE
# tree every time. root_main.c is the sole consumer, so scoping it there keeps
# a mode switch to a ~1-file recompile.