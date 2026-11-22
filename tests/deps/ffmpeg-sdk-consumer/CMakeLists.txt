# Consumer of dvv_ffmpeg_sdk, the FFmpeg package of the third-party prefix (M4 design §9). Built and
# run by run-ffmpeg-sdk-consumer.cmake.
cmake_minimum_required(VERSION 4.2)
project(dvv_ffmpeg_sdk_consumer LANGUAGES CXX)

find_package(dvv_ffmpeg_sdk REQUIRED CONFIG)
if(NOT EXISTS "${DVV_FFMPEG_PROGRAM}")
    message(FATAL_ERROR "DVV_FFMPEG_PROGRAM '${DVV_FFMPEG_PROGRAM}' does not exist")
endif()
if(NOT IS_DIRECTORY "${DVV_FFMPEG_RUNTIME_DIR}")
    message(FATAL_ERROR "DVV_FFMPEG_RUNTIME_DIR '${DVV_FFMPEG_RUNTIME_DIR}' is not a directory")
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" -E env "LD_LIBRARY_PATH=${DVV_FFMPEG_RUNTIME_DIR}"
                        "${DVV_FFMPEG_PROGRAM}" -hide_banner -version
                RESULT_VARIABLE status OUTPUT_VARIABLE version ERROR_VARIABLE error)
if(NOT status EQUAL 0 OR NOT version MATCHES "configuration:" OR
   version MATCHES "--enable-(gpl|nonfree)")
    message(FATAL_ERROR "DVV_FFMPEG_PROGRAM '${DVV_FFMPEG_PROGRAM}' -version failed or is not an "
                        "LGPL build:\n${version}${error}")
endif()
string(REGEX MATCH "^[^\n]*" first_line "${version}")

# The release data and DVV_BUNDLE_FFMPEG: <prefix>/dvv-third-party-state.cmake.
find_file(state dvv-third-party-state.cmake PATHS ${CMAKE_PREFIX_PATH} NO_DEFAULT_PATH NO_CACHE)
if(NOT state)
    message(FATAL_ERROR "dvv-third-party-state.cmake is not in CMAKE_PREFIX_PATH "
                        "'${CMAKE_PREFIX_PATH}'")
endif()
include("${state}")
if(NOT DVV_BUNDLE_FFMPEG MATCHES "^(ON|OFF)$")
    message(FATAL_ERROR "DVV_BUNDLE_FFMPEG is '${DVV_BUNDLE_FFMPEG}', expected ON or OFF")
endif()
foreach(variable IN ITEMS DVV_CUSTOM_FFMPEG_SHA256 DVV_LAME_SOURCE_SHA256)
    if(NOT ${variable} MATCHES "^[0-9a-f]+$")
        message(FATAL_ERROR "${variable} is '${${variable}}', expected lowercase hex")
    endif()
endforeach()
if(NOT DVV_CUSTOM_FFMPEG_URL MATCHES
   "^https://github\\.com/[^/]+/[^/]+/releases/download/v${DVV_CUSTOM_FFMPEG_VERSION}/")
    message(FATAL_ERROR "DVV_CUSTOM_FFMPEG_URL is '${DVV_CUSTOM_FFMPEG_URL}', expected a GitHub "
                        "release asset of v${DVV_CUSTOM_FFMPEG_VERSION} (DVV_CUSTOM_FFMPEG_VERSION)")
endif()
if(NOT IS_DIRECTORY "${DVV_CUSTOM_FFMPEG_DIR}")
    message(FATAL_ERROR "DVV_CUSTOM_FFMPEG_DIR '${DVV_CUSTOM_FFMPEG_DIR}' is not a directory")
endif()
message(STATUS "ffmpeg-sdk: ${first_line}; DVV_BUNDLE_FFMPEG=${DVV_BUNDLE_FFMPEG}")

add_executable(consumer main.cpp)
target_link_libraries(consumer PRIVATE dvv::ffmpeg_headers)
target_compile_features(consumer PRIVATE cxx_std_23)
# No C++ modules: without this, Ninja on Clang needs clang-scan-deps (as DvvCompilerOptions.cmake).
set_target_properties(consumer PROPERTIES CXX_SCAN_FOR_MODULES OFF)
