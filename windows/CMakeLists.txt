# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "flutter_opengl")
project(${PROJECT_NAME} LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Build GLEW from source (bundled in windows/glew)
set(GLEW_DIR "${CMAKE_CURRENT_LIST_DIR}/glew")
add_library(glew_s STATIC "${GLEW_DIR}/src/glew.c")
target_include_directories(glew_s PUBLIC "${GLEW_DIR}/include")
target_compile_definitions(glew_s PUBLIC GLEW_STATIC)
target_link_libraries(glew_s PRIVATE opengl32)

# -----------------------------------------------------------------------
# Build the Rust shared library via cargo
# -----------------------------------------------------------------------
set(RUST_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../rust")
set(RUST_LIB_NAME "flutter_opengl_rust")

# Determine Rust build profile and output directory
if(CMAKE_BUILD_TYPE STREQUAL "Release")
  set(RUST_PROFILE "release")
  set(CARGO_BUILD_FLAGS --release)
else()
  set(RUST_PROFILE "debug")
  set(CARGO_BUILD_FLAGS "")
endif()

set(RUST_LIB_DIR "${RUST_DIR}/target/${RUST_PROFILE}")
set(RUST_DLL_PATH "${RUST_LIB_DIR}/${RUST_LIB_NAME}.dll")
set(RUST_IMPLIB_PATH "${RUST_LIB_DIR}/${RUST_LIB_NAME}.dll.lib")

add_custom_command(
  OUTPUT ${RUST_DLL_PATH}
  COMMAND cargo build ${CARGO_BUILD_FLAGS}
  WORKING_DIRECTORY ${RUST_DIR}
  COMMENT "Building Rust library (${RUST_PROFILE})"
)
add_custom_target(rust_lib ALL DEPENDS ${RUST_DLL_PATH})

# Import the Rust shared library as a CMake target
add_library(${RUST_LIB_NAME} SHARED IMPORTED)
set_target_properties(${RUST_LIB_NAME} PROPERTIES
  IMPORTED_LOCATION ${RUST_DLL_PATH}
  IMPORTED_IMPLIB ${RUST_IMPLIB_PATH}
)
add_dependencies(${RUST_LIB_NAME} rust_lib)

# -----------------------------------------------------------------------
# Plugin sources (no more C++ engine sources)
# -----------------------------------------------------------------------

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "flutter_opengl_plugin")

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
  "flutter_opengl_plugin.cpp"
  "flutter_opengl_plugin.h"
  "fl_my_texture_gl.cc"
)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
  "include/flutter_opengl/flutter_opengl_plugin_c_api.h"
  "flutter_opengl_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Don't treat warnings as compile errors in this plugin.
target_compile_options(${PLUGIN_NAME} PRIVATE "/WX-")

# Source include directories and library dependencies. Add any plugin-specific
# dependencies here.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

find_package(OpenGL REQUIRED)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  OpenGL::GL
  glew_s
  ${RUST_LIB_NAME}
  )

# Bundle the Rust .dll with the Flutter application so it ends up next to
# the executable at runtime.
set(flutter_opengl_bundled_libraries
  "${RUST_DLL_PATH}"
  PARENT_SCOPE
)
