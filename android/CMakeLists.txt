cmake_minimum_required(VERSION 3.18)

set(PROJECT_NAME "flutter_opengl")
project(${PROJECT_NAME} LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(PLUGIN_NAME "flutter_opengl_plugin")

# -----------------------------------------------------------------------
# Rust shared library (pre-built by Gradle cargoNdkBuild task)
#
# The Rust .so for each ABI is placed under:
#   ../rust/target/<abi>/release/libflutter_opengl_rust.so
# by the cargo-ndk invocation in build.gradle.
# -----------------------------------------------------------------------
set(RUST_LIB_NAME "flutter_opengl_rust")
set(RUST_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../rust")

# Map ANDROID_ABI to the Rust target triple
if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(RUST_TARGET "aarch64-linux-android")
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
    set(RUST_TARGET "armv7-linux-androideabi")
elseif(ANDROID_ABI STREQUAL "x86")
    set(RUST_TARGET "i686-linux-android")
elseif(ANDROID_ABI STREQUAL "x86_64")
    set(RUST_TARGET "x86_64-linux-android")
else()
    message(FATAL_ERROR "Unsupported ANDROID_ABI: ${ANDROID_ABI}")
endif()

set(RUST_LIB_DIR "${RUST_DIR}/target/${RUST_TARGET}/release")
set(RUST_LIB_PATH "${RUST_LIB_DIR}/lib${RUST_LIB_NAME}.so")

# Import the pre-built Rust shared library
add_library(${RUST_LIB_NAME} SHARED IMPORTED)
set_target_properties(${RUST_LIB_NAME} PROPERTIES
    IMPORTED_LOCATION ${RUST_LIB_PATH}
)

# -----------------------------------------------------------------------
# Plugin sources (JNI bridge only -- no more C++ engine sources)
# -----------------------------------------------------------------------
set(PLUGIN_SOURCES
    src/main/cpp/android_bridge.cpp
)

add_library(${PLUGIN_NAME} SHARED ${PLUGIN_SOURCES})

find_library(log-lib log)

target_include_directories(${PLUGIN_NAME} PRIVATE
    src/main/cpp
)

target_link_libraries(${PLUGIN_NAME}
    ${log-lib}
    android
    EGL
    GLESv3
    ${RUST_LIB_NAME}
)
