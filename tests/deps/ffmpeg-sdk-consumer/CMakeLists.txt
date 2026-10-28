# Consumer of dvv_ffmpeg_sdk, the FFmpeg package of the third-party prefix (M4 design §9). Built and
# run by run-ffmpeg-sdk-consumer.cmake.
cmake_minimum_required(VERSION 4.2)
project(dvv_ffmpeg_sdk_consumer LANGUAGES CXX)

find_package(dvv_ffmpeg_sdk REQUIRED CONFIG)
list(LENGTH DVV_FFMPEG_LIBRARY_FILES count)
if(NOT count EQUAL 6)
    message(FATAL_ERROR "DVV_FFMPEG_LIBRARY_FILES has ${count} entries, expected 6")
endif()
foreach(file IN LISTS DVV_FFMPEG_LIBRARY_FILES DVV_FFMPEG_SHIPPED_FILES
             ITEMS "${DVV_FFMPEG_PROGRAM}" "${DVV_FFPROBE_PROGRAM}" "${DVV_FFMPEG_BUILD_INFO}"
                   "${DVV_FFMPEG_LICENSE_DIR}" "${DVV_FFMPEG_INCLUDE_DIR}/libavutil/avutil.h")
    if(NOT EXISTS "${file}")
        message(FATAL_ERROR "${file} does not exist")
    endif()
endforeach()
if(NOT DVV_BUNDLE_FFMPEG MATCHES "^(ON|OFF)$")
    message(FATAL_ERROR "DVV_BUNDLE_FFMPEG is '${DVV_BUNDLE_FFMPEG}'")
endif()
foreach(hash IN ITEMS "${DVV_FFMPEG_RELEASE_SHA256}" "${DVV_LAME_SOURCE_SHA256}")
    if(NOT hash MATCHES "^[0-9a-f]+$")
        message(FATAL_ERROR "bad SHA256 '${hash}'")
    endif()
endforeach()
if(NOT DVV_FFMPEG_SOURCE_REPOSITORY STREQUAL "https://github.com/BarabashkaD/custom_ffmpeg" OR
   NOT DVV_FFMPEG_SOURCE_TAG STREQUAL "v${DVV_FFMPEG_RELEASE_VERSION}")
    message(FATAL_ERROR "source ${DVV_FFMPEG_SOURCE_REPOSITORY} ${DVV_FFMPEG_SOURCE_TAG}")
endif()
execute_process(COMMAND ${DVV_FFMPEG_COMMAND} -hide_banner -version
                RESULT_VARIABLE status OUTPUT_VARIABLE version ERROR_VARIABLE error)
if(NOT status EQUAL 0 OR NOT version MATCHES "configuration:" OR
   version MATCHES "--enable-(gpl|nonfree)")
    message(FATAL_ERROR "ffmpeg -version failed or is not an LGPL build:\n${version}${error}")
endif()
string(REGEX MATCH "^[^\n]*" first_line "${version}")
message(STATUS "ffmpeg-sdk: ${first_line}; DVV_BUNDLE_FFMPEG=${DVV_BUNDLE_FFMPEG}")

add_executable(consumer main.cpp)
target_link_libraries(consumer PRIVATE dvv::ffmpeg_headers)
target_compile_features(consumer PRIVATE cxx_std_23)
# No C++ modules: without this, Ninja on Clang needs clang-scan-deps (as DvvCompilerOptions.cmake).
set_target_properties(consumer PROPERTIES CXX_SCAN_FOR_MODULES OFF)
