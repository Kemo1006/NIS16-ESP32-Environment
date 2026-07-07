cmake_minimum_required(VERSION 3.16)

set(EXTRA_COMPONENT_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/../components")

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(attacker_b_node)

# Optional per-run override for the M4 experiment-matrix runner:
#   idf.py -DMESH_TOPOLOGY=2 build   (macros are #ifndef-guarded in mesh_config.h)
if(DEFINED MESH_TOPOLOGY)
  idf_build_set_property(COMPILE_OPTIONS "-DMESH_TOPOLOGY=${MESH_TOPOLOGY}" APPEND)
endif()
