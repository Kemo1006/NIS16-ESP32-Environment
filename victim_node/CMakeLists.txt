cmake_minimum_required(VERSION 3.16)

set(EXTRA_COMPONENT_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/../components")

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(victim_node)

# Optional per-run overrides for the M4 experiment-matrix runner:
#   idf.py -DMESH_TOPOLOGY=2 build
# The mesh_config.h macros are #ifndef-guarded, so these only take effect when
# passed; a plain `idf.py build` uses the header defaults (unchanged behaviour).
if(DEFINED ACTIVE_ATTACK)
  idf_build_set_property(COMPILE_OPTIONS "-DACTIVE_ATTACK=${ACTIVE_ATTACK}" APPEND)
endif()
if(DEFINED MESH_TOPOLOGY)
  idf_build_set_property(COMPILE_OPTIONS "-DMESH_TOPOLOGY=${MESH_TOPOLOGY}" APPEND)
endif()