cmake_minimum_required(VERSION 3.22)
project(transport_native LANGUAGES CXX)

# Flutter/Gradle passes TRANSPORT_NATIVE_LIB_DIR to the ABI-specific build.
# No host package manager lookup is used for Android release artifacts.
set(TRANSPORT_NATIVE_LIB_DIR "${CMAKE_CURRENT_LIST_DIR}/src/main/jniLibs" CACHE PATH "Directory containing bundled libtorrent ABI libraries")
if (NOT TRANSPORT_NATIVE_LIB_DIR)
  message(FATAL_ERROR "TRANSPORT_NATIVE_LIB_DIR must point to the pinned Android native bundle")
endif()
add_library(transport_lt_shim SHARED IMPORTED GLOBAL)
set_target_properties(transport_lt_shim PROPERTIES
  IMPORTED_LOCATION "${TRANSPORT_NATIVE_LIB_DIR}/${ANDROID_ABI}/libtransport_lt_shim.so"
  INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_LIST_DIR}/../src/lt_shim")
