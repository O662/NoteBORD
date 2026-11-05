# Builds libendless_speech: Endless's bridge (endless_speech.cpp) with
# whisper.cpp and ggml (CPU only) linked in statically.
#
# whisper.cpp is vendored in ./whisper.cpp (v1.9.5, MIT; see
# ./whisper.cpp/README.endless.md). Nothing is downloaded at build time.

cmake_minimum_required(VERSION 3.14)
project(endless_speech_library VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if (NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# whisper.cpp and ggml: static, CPU only, no examples, tests, servers,
# downloaders or GPU backends.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(WHISPER_CURL OFF CACHE BOOL "" FORCE)
set(WHISPER_SDL2 OFF CACHE BOOL "" FORCE)
set(WHISPER_ALL_WARNINGS OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(GGML_CPU_KLEIDIAI OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)

if (ANDROID)
  if (ANDROID_ABI STREQUAL "arm64-v8a")
    # Every 64-bit Arm tablet since about 2018 (the Tab S9 FE's Cortex-A78
    # and A55 included) has dot product and half-float instructions.
    set(GGML_CPU_ARM_ARCH "armv8.2-a+dotprod+fp16" CACHE STRING "" FORCE)
  elseif (ANDROID_ABI STREQUAL "armeabi-v7a")
    set(GGML_CPU_ARM_ARCH "armv7-a" CACHE STRING "" FORCE)
  endif()
elseif (WIN32 OR UNIX)
  # Desktops: x86-64 with AVX2 (Intel since 2013, AMD since 2015).
  if (CMAKE_SYSTEM_PROCESSOR MATCHES "AMD64|x86_64")
    set(GGML_AVX ON CACHE BOOL "" FORCE)
    set(GGML_AVX2 ON CACHE BOOL "" FORCE)
    set(GGML_FMA ON CACHE BOOL "" FORCE)
    set(GGML_F16C ON CACHE BOOL "" FORCE)
  endif()
endif()

add_subdirectory(whisper.cpp whisper EXCLUDE_FROM_ALL)

add_library(endless_speech SHARED endless_speech.cpp)
target_link_libraries(endless_speech PRIVATE whisper)
target_compile_definitions(endless_speech PUBLIC DART_SHARED_LIB)
set_target_properties(endless_speech PROPERTIES
  PUBLIC_HEADER endless_speech.h
  OUTPUT_NAME "endless_speech"
)

if (ANDROID)
  target_compile_options(endless_speech PRIVATE -O3 -fvisibility=hidden)
  target_link_options(endless_speech PRIVATE "-Wl,-z,max-page-size=16384" "-Wl,--gc-sections")
  target_link_libraries(endless_speech PRIVATE log)
endif()
