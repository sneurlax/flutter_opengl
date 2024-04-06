cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "flutter_opengl")
project(${PROJECT_NAME} LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(PLUGIN_NAME "flutter_opengl_plugin")

# Option to enable OpenCV support (off by default)
option(WITH_OPENCV "Build with OpenCV support" OFF)

# Core plugin sources
set(PLUGIN_SOURCES
  flutter_opengl_plugin.cc
  fl_my_texture_gl.cc
  ../src/common.h
  ../src/ffi.cpp
  ../src/Renderer.cpp
  ../src/Shader.cpp
  ../src/uniformQueue.cpp
  ../src/Sampler2D.cpp
)

if(WITH_OPENCV)
  list(APPEND PLUGIN_SOURCES ../src/opencv_capture.cpp)
endif()

add_library(${PLUGIN_NAME} SHARED ${PLUGIN_SOURCES})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_compile_options(${PLUGIN_NAME} PRIVATE -Wall -Wno-error)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../src"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

# OpenGL + EGL (the EGL link was missing, causing "undefined reference to eglGetError")
find_package(OpenGL REQUIRED COMPONENTS OpenGL EGL)
target_link_libraries(${PLUGIN_NAME} PRIVATE
  OpenGL::OpenGL
  OpenGL::EGL
  GLEW
)

# Optional OpenCV support
if(WITH_OPENCV)
  find_package(OpenCV REQUIRED COMPONENTS core highgui)
  include_directories(${OpenCV_INCLUDE_DIRS})
  target_link_libraries(${PLUGIN_NAME} PRIVATE opencv_core opencv_highgui)
  target_compile_definitions(${PLUGIN_NAME} PRIVATE WITH_OPENCV)
  message(STATUS "OpenCV enabled: ${OpenCV_DIR}")
endif()

set(flutter_opengl_bundled_libraries
  ""
)
