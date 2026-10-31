cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "video_surface")
project(${PROJECT_NAME} LANGUAGES CXX)
cmake_policy(VERSION 3.14...3.25)

# Must not be changed: the Flutter tooling builds the plugin under this name.
set(PLUGIN_NAME "video_surface_plugin")

add_library(${PLUGIN_NAME} SHARED
  "include/video_surface/video_surface_plugin_c_api.h"
  "video_surface_plugin_c_api.cpp"
  "video_surface_plugin.cpp"
  "video_surface_plugin.h"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
# libmpv is resolved at run time from the process (media_kit ships libmpv-2.dll).
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin dxgi)

set(video_surface_bundled_libraries "" PARENT_SCOPE)
