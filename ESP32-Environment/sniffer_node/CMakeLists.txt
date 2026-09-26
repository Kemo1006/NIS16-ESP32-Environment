cmake_minimum_required(VERSION 3.16)

# Passive Wi-Fi sniffer for Wireshark: a spare ESP32 that NEVER joins the mesh.
# It listens on MESH_CHANNEL in promiscuous mode and streams every frame it
# hears over the USB cable to tools/sniff.py, which writes a .pcap. No SD card,
# no extra wiring - see main/sniffer_main.c and docs/WIRESHARK-GUIDE.md.
#
# Deliberately NOT built against components/mesh_common: that component pulls
# in the SD/CSV/mesh stack this board must not run. Only mesh_config.h is used
# (for MESH_CHANNEL), added as a bare include path in main/CMakeLists.txt.

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(sniffer_node)
