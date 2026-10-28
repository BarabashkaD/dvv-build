# Third-party superbuild (spec §13.2): downloads, verifies, builds and installs every dependency
# from versions.cmake into DVV_THIRD_PARTY_PREFIX and writes there THIRD_PARTY_NOTICES.txt (the
# shipped entries), THIRD_PARTY_NOTICES-all.txt (every entry), the dvv_ffmpeg_sdk package and
# dvv-third-party-state.cmake. It builds Release, plus Debug where a declaration lists CONFIGS Debug
# Release (Visual Studio only).
#
#   cmake -S deps -B <build dir> -DDVV_THIRD_PARTY_PREFIX=<install dir> [-DDVV_BUNDLE_FFMPEG=OFF]
#         [-G Ninja -DCMAKE_C_COMPILER=clang-19 -DCMAKE_CXX_COMPILER=clang++-19]   (Linux)
#   cmake --build <build dir> --config Release --parallel
# bootstrap.ps1 and bootstrap.sh run these two commands.
cmake_minimum_required(VERSION 4.2)
project(dvv_third_party LANGUAGES C CXX)

include(ExternalProject)
include("${CMAKE_CURRENT_LIST_DIR}/../cmake/DvvThirdParty.cmake")
# User decision U4 (M4 design §2, D3, D27): ship custom_ffmpeg's LGPL libraries in the rawreel
# packages. OFF keeps FFmpeg for development and tests but leaves it out of the shipped notices and,
# through dvv_ffmpeg_sdk, out of the packages and the sources archive.
option(DVV_BUNDLE_FFMPEG "Ship custom_ffmpeg's LGPL libraries in the rawreel packages" ON)
include("${CMAKE_CURRENT_LIST_DIR}/versions.cmake")

if(NOT DVV_THIRD_PARTY_PREFIX)
    message(FATAL_ERROR "Set DVV_THIRD_PARTY_PREFIX to the install directory")
endif()
cmake_path(ABSOLUTE_PATH DVV_THIRD_PARTY_PREFIX BASE_DIRECTORY "${CMAKE_BINARY_DIR}"
           NORMALIZE OUTPUT_VARIABLE prefix)

# Every project finds the ones installed before it in the prefix. Every project gets both
# compilers, and a C++-only project need not report the unused C one.
set(common_args
    --no-warn-unused-cli
    "-DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>"
    "-DCMAKE_PREFIX_PATH=<INSTALL_DIR>"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}"
    "-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}")
if(CMAKE_GENERATOR MATCHES "^Visual Studio")
    # MSBuild otherwise compiles the files of one project one after another.
    list(APPEND common_args "-DCMAKE_VS_GLOBALS=UseMultiToolTask=true")
endif()

get_property(names GLOBAL PROPERTY DVV_THIRD_PARTY_NAMES)
get_property(multi_config GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
set(notice_entries "")
set(notice_supplements "")
set(shipped_entries "")
set(shipped_names "")
foreach(name IN LISTS names)
    foreach(key IN ITEMS VERSION URL SHA256 SPDX LICENSE_FILES DEPENDS PREBUILT CMAKE_ARGS
                         POST_INSTALL SHIPPED)
        get_property(${key} GLOBAL PROPERTY "DVV_THIRD_PARTY_${name}_${key}")
    endforeach()
    if(POST_INSTALL)
        set(post_install "${CMAKE_COMMAND}" -DSOURCE_DIR=<SOURCE_DIR> -DPREFIX=<INSTALL_DIR>
                         -P "${POST_INSTALL}")
    else()
        set(post_install "${CMAKE_COMMAND}" -E true)
    endif()
    if(PREBUILT)
        # The archive is extracted straight into <prefix>/<name>. The extract step replaces that
        # directory as a whole, so no file of an older version survives an update.
        ExternalProject_Add(${name}
            URL "${URL}"
            URL_HASH "SHA256=${SHA256}"
            DOWNLOAD_EXTRACT_TIMESTAMP TRUE
            SOURCE_DIR "${prefix}/${name}"
            INSTALL_DIR "${prefix}"
            DEPENDS ${DEPENDS}
            CONFIGURE_COMMAND ""
            BUILD_COMMAND ""
            INSTALL_COMMAND ${post_install})
    else()
        # One build and one install command per configuration, in the declared order.
        dvv_third_party_build_configs(${name} "${multi_config}" configs)
        set(build_command "")
        set(install_command "")
        foreach(config IN LISTS configs)
            if(NOT build_command STREQUAL "")
                list(APPEND build_command COMMAND)
                list(APPEND install_command COMMAND)
            endif()
            list(APPEND build_command "${CMAKE_COMMAND}" --build <BINARY_DIR> --config ${config}
                                      --parallel)
            list(APPEND install_command "${CMAKE_COMMAND}" --install <BINARY_DIR>
                                        --config ${config})
        endforeach()
        ExternalProject_Add(${name}
            URL "${URL}"
            URL_HASH "SHA256=${SHA256}"
            DOWNLOAD_EXTRACT_TIMESTAMP TRUE
            INSTALL_DIR "${prefix}"
            DEPENDS ${DEPENDS}
            CMAKE_ARGS ${common_args} ${CMAKE_ARGS}
            BUILD_COMMAND ${build_command}
            INSTALL_COMMAND ${install_command}
                    COMMAND ${post_install})
    endif()
    ExternalProject_Get_Property(${name} SOURCE_DIR)
    list(JOIN LICENSE_FILES "|" licence_files)
    set(entry "${name}|${VERSION}|${SPDX}|${URL}|${SOURCE_DIR}|${licence_files}")
    list(APPEND notice_entries "${entry}")
    get_property(supplements GLOBAL PROPERTY "DVV_THIRD_PARTY_${name}_SUPPLEMENTS")
    foreach(supplement IN LISTS supplements)
        list(APPEND notice_supplements "${name}|${supplement}")
    endforeach()
    if(SHIPPED)
        list(APPEND shipped_entries "${entry}")
        list(APPEND shipped_names "${name}")
    endif()
endforeach()

# THIRD_PARTY_NOTICES.txt holds what the packages ship (M4 design D19); THIRD_PARTY_NOTICES-all.txt
# every dependency, as a developer reference that is never shipped. Both copy an entry's licence
# supplements (dvv_licence_supplement) after its licence files. $<SEMICOLON> keeps each list
# (and the semicolon of the -all header) in one command-line argument.
string(REPLACE ";" "$<SEMICOLON>" notice_entries "${notice_entries}")
string(REPLACE ";" "$<SEMICOLON>" shipped_entries "${shipped_entries}")
string(REPLACE ";" "$<SEMICOLON>" notice_supplements "${notice_supplements}")
if(MSVC)
    set(msvc_runtime ON)
else()
    set(msvc_runtime OFF)
endif()
add_custom_target(third_party_notices ALL
    COMMAND "${CMAKE_COMMAND}" "-DOUTPUT=${prefix}/THIRD_PARTY_NOTICES-all.txt"
            "-DENTRIES=${notice_entries}" "-DSUPPLEMENTS=${notice_supplements}"
            "-DHEADER=Third-party software used to build and test rawreel and the dvv libraries \
(developer reference$<SEMICOLON> not shipped)"
            -P "${CMAKE_CURRENT_LIST_DIR}/write-notices.cmake"
    COMMAND "${CMAKE_COMMAND}" "-DOUTPUT=${prefix}/THIRD_PARTY_NOTICES.txt"
            "-DENTRIES=${shipped_entries}" "-DSUPPLEMENTS=${notice_supplements}"
            "-DHEADER=Third-party software in the rawreel packages"
            "-DMSVC_RUNTIME=${msvc_runtime}"
            -P "${CMAKE_CURRENT_LIST_DIR}/write-notices.cmake"
    DEPENDS ${names}
    VERBATIM)

# dvv_ffmpeg_sdk: the prefix's FFmpeg for dvv-components and rawreel (M4 design §9).
foreach(key IN ITEMS VERSION URL SHA256)
    get_property(ffmpeg_${key} GLOBAL PROPERTY "DVV_THIRD_PARTY_custom_ffmpeg_${key}")
    get_property(lame_${key} GLOBAL PROPERTY "DVV_SOURCE_PIN_lame_${key}")
endforeach()
if(NOT ffmpeg_URL MATCHES "^(https://github\\.com/[^/]+/[^/]+)/releases/download/([^/]+)/")
    message(FATAL_ERROR "custom_ffmpeg's URL is not a GitHub release asset: ${ffmpeg_URL}")
endif()
set(ffmpeg_repository "${CMAKE_MATCH_1}")
set(ffmpeg_tag "${CMAKE_MATCH_2}")
if(DVV_BUNDLE_FFMPEG)
    set(bundle_value ON)
else()
    set(bundle_value OFF)
endif()
configure_file("${CMAKE_CURRENT_LIST_DIR}/dvv_ffmpeg_sdkConfig.cmake.in"
               "${prefix}/lib/cmake/dvv_ffmpeg_sdk/dvv_ffmpeg_sdkConfig.cmake" @ONLY)

# What the prefix ships, for rawreel's packaging and its cmake -P scripts (M4 design D19, D27, §9),
# which cannot load dvv_ffmpeg_sdk (it creates a target). The same values as the package. Written at
# configure time; the PREBUILT extract steps replace only <prefix>/<name>, never this file.
list(SORT shipped_names)
# custom_ffmpeg's licence supplements (dvv_licence_supplement), copied unchanged into the prefix
# for rawreel's package (the shipped SHA256 equals the pin), each recorded as "<path>|<sha256>".
set(supplement_dir "${prefix}/share/dvv-licence-supplements/custom_ffmpeg")
file(REMOVE_RECURSE "${supplement_dir}")
get_property(supplements GLOBAL PROPERTY DVV_THIRD_PARTY_custom_ffmpeg_SUPPLEMENTS)
set(supplement_pins "")
foreach(supplement IN LISTS supplements)
    string(REPLACE "|" ";" parts "${supplement}")
    list(GET parts 0 supplement_file)
    list(GET parts 1 supplement_sha256)
    list(GET parts 2 supplement_path)
    configure_file("${supplement_file}" "${supplement_dir}/${supplement_path}" COPYONLY)
    list(APPEND supplement_pins "${supplement_path}|${supplement_sha256}")
endforeach()
file(WRITE "${prefix}/dvv-third-party-state.cmake"
"# Generated by the rawreel-workspace superbuild (deps/CMakeLists.txt); do not edit.
set(DVV_BUNDLE_FFMPEG ${bundle_value})
set(DVV_SHIPPED_THIRD_PARTY \"${shipped_names}\")
set(DVV_CUSTOM_FFMPEG_VERSION \"${ffmpeg_VERSION}\")
set(DVV_CUSTOM_FFMPEG_URL \"${ffmpeg_URL}\")
set(DVV_CUSTOM_FFMPEG_SHA256 \"${ffmpeg_SHA256}\")
set(DVV_CUSTOM_FFMPEG_DIR \"\${CMAKE_CURRENT_LIST_DIR}/custom_ffmpeg\")
set(DVV_LAME_SOURCE_URL \"${lame_URL}\")
set(DVV_LAME_SOURCE_SHA256 \"${lame_SHA256}\")
set(DVV_CUSTOM_FFMPEG_LICENCE_SUPPLEMENTS \"${supplement_pins}\")
set(DVV_CUSTOM_FFMPEG_LICENCE_SUPPLEMENTS_DIR
    \"\${CMAKE_CURRENT_LIST_DIR}/share/dvv-licence-supplements/custom_ffmpeg\")
")
