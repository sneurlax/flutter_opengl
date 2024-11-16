cmake_minimum_required(VERSION 3.18)

set(PROJECT_NAME "flutter_opengl")
project(${PROJECT_NAME} LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(PLUGIN_NAME "flutter_opengl_plugin")

set(SOURCES
    ../src/ndk/ndk.cpp
    ../src/ffi.cpp
    ../src/Renderer.cpp
    ../src/Shader.cpp
    ../src/uniformQueue.cpp
    ../src/Sampler2D.cpp
)

if(WITH_OPENCV)
    list(APPEND SOURCES ../src/opencv_capture.cpp)
endif()

add_library(${PLUGIN_NAME} SHARED ${SOURCES})

find_library(log-lib log)

target_include_directories(${PLUGIN_NAME} PRIVATE
    ../src
    src/glm
)

set(LINK_LIBS
    ${log-lib}
    android
    EGL
    GLESv3
    dl
    m
    jnigraphics
)

if(WITH_OPENCV)
    set(OPENCV_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src/opencv)
    target_include_directories(${PLUGIN_NAME} PRIVATE ${OPENCV_DIR}/include)
    list(APPEND LINK_LIBS ${OPENCV_DIR}/${ANDROID_ABI}/libopencv_java4.so)
endif()

target_link_libraries(${PLUGIN_NAME} ${LINK_LIBS})
