cmake_minimum_required(VERSION 3.14)
project(cast LANGUAGES C)
set(cast_bundled_libraries "${CMAKE_CURRENT_LIST_DIR}/native/cast_remux.dll" PARENT_SCOPE)
