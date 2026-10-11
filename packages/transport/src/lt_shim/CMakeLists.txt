cmake_minimum_required(VERSION 3.10)
project(transport_lt_shim LANGUAGES C CXX)
set(TRANSPORT_LT_LIBRARY_TYPE STATIC CACHE STRING "STATIC for app embedding, SHARED for host FFI tests")
add_library(transport_lt_shim ${TRANSPORT_LT_LIBRARY_TYPE} lt_shim.cpp fs_shim.c)
target_compile_features(transport_lt_shim PRIVATE cxx_std_17)
set(TRANSPORT_LIBTORRENT_VERSION 2.1.1 CACHE STRING "Pinned libtorrent ABI version")
set(TRANSPORT_LIBTORRENT_ROOT "" CACHE PATH "Bundled libtorrent prefix (required for production packaging)")
target_include_directories(transport_lt_shim PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
if (TRANSPORT_LIBTORRENT_ROOT)
  list(PREPEND CMAKE_PREFIX_PATH "${TRANSPORT_LIBTORRENT_ROOT}")
endif()
option(TRANSPORT_LT_BUILD_HARNESS "Build the standalone C ABI proof harness" OFF)
if (TRANSPORT_LT_BUILD_HARNESS)
  add_executable(lt_shim_harness ../../tool/lt_shim_harness/main.c)
  target_link_libraries(lt_shim_harness PRIVATE transport_lt_shim)
endif()
find_package(LibtorrentRasterbar ${TRANSPORT_LIBTORRENT_VERSION} EXACT CONFIG REQUIRED)
target_link_libraries(transport_lt_shim PRIVATE LibtorrentRasterbar::torrent-rasterbar)
set_target_properties(transport_lt_shim PROPERTIES
  # Never encode a build-machine or temporary prefix in the shipped dylib.
  # Packaging copies the sibling libtorrent image beside this shim.
  BUILD_RPATH "@loader_path"
  SKIP_BUILD_RPATH FALSE
  INSTALL_RPATH_USE_LINK_PATH FALSE
  INSTALL_RPATH "@loader_path")
get_target_property(TRANSPORT_LT_DEPENDENCY_TYPE LibtorrentRasterbar::torrent-rasterbar TYPE)
if (APPLE AND TRANSPORT_LIBTORRENT_ROOT AND TRANSPORT_LT_DEPENDENCY_TYPE STREQUAL "SHARED_LIBRARY")
  # Imported libtorrent targets add their prefix as a build rpath. Strip that
  # machine-local path from the produced artifact; the sibling image is found
  # solely through @loader_path in the package.
  add_custom_command(TARGET transport_lt_shim POST_BUILD
    COMMAND install_name_tool -delete_rpath "${TRANSPORT_LIBTORRENT_ROOT}/lib"
            "$<TARGET_FILE:transport_lt_shim>"
    VERBATIM)
endif()
