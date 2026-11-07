# Checks that a Vulkan device for the GPU tests is present (spec §13.4): prints the output of
# `vulkaninfo --summary` (and its stderr, if any) and fails unless at least one device reports an
# apiVersion of MIN_VERSION or newer. CI runs it on Linux before the build, whose GPU tests then
# must not skip (DVV_REQUIRE_GPU=1).
#
# Usage: cmake [-DMIN_VERSION=<major>.<minor>] [-DVULKANINFO=<program>] [-DPREFIX=<prefix>]
#              -P tools/check-vulkan-device.cmake
#   MIN_VERSION  lowest accepted device API version (default 1.4)
#   VULKANINFO   the vulkaninfo program (default: vulkaninfo from PATH; Linux package vulkan-tools;
#                on macOS <PREFIX>/bin/vulkaninfo)
#   PREFIX       macOS only: the third-party prefix (default <dvv root>/_third_party/appleclang)
#   SUMMARY_FILE checks saved `vulkaninfo --summary` output instead of running vulkaninfo (tests)
# On macOS vulkaninfo runs on the prefix's loader and its KosmicKrisp driver only:
# DYLD_LIBRARY_PATH=<PREFIX>/lib (the SDK's vulkaninfo opens libvulkan.dylib by its bare name) and
# VK_DRIVER_FILES=<PREFIX>/share/vulkan/icd.d/libkosmickrisp_icd.json.
cmake_minimum_required(VERSION 4.2)

if(NOT DEFINED MIN_VERSION)
    set(MIN_VERSION 1.4)
endif()
if(NOT MIN_VERSION MATCHES "^[0-9]+\\.[0-9]+$")
    message(FATAL_ERROR
            "check-vulkan-device: MIN_VERSION must be <major>.<minor>, got '${MIN_VERSION}'")
endif()

if(DEFINED SUMMARY_FILE)
    file(READ "${SUMMARY_FILE}" summary)
else()
    set(run "")
    if(CMAKE_HOST_APPLE)
        if(NOT DEFINED PREFIX)
            cmake_path(SET PREFIX NORMALIZE
                       "${CMAKE_CURRENT_LIST_DIR}/../../_third_party/appleclang")
        endif()
        set(manifest "${PREFIX}/share/vulkan/icd.d/libkosmickrisp_icd.json")
        if(NOT EXISTS "${manifest}")
            message(FATAL_ERROR "check-vulkan-device: no KosmicKrisp manifest ${manifest}; run "
                                "bootstrap")
        endif()
        if(NOT DEFINED VULKANINFO)
            set(VULKANINFO "${PREFIX}/bin/vulkaninfo")
        endif()
        set(environment "VK_DRIVER_FILES=${manifest}" "DYLD_LIBRARY_PATH=${PREFIX}/lib")
        list(JOIN environment " " shown)
        message(STATUS "check-vulkan-device: ${shown}")
        set(run "${CMAKE_COMMAND}" -E env ${environment})
    elseif(NOT DEFINED VULKANINFO)
        find_program(VULKANINFO vulkaninfo)
        if(NOT VULKANINFO)
            message(FATAL_ERROR
                    "check-vulkan-device: vulkaninfo not found (Linux: install vulkan-tools)")
        endif()
    endif()
    execute_process(COMMAND ${run} "${VULKANINFO}" --summary
                    RESULT_VARIABLE status OUTPUT_VARIABLE summary ERROR_VARIABLE errors)
    message("${summary}")
    if(NOT status EQUAL 0)
        message(FATAL_ERROR "check-vulkan-device: '${VULKANINFO} --summary' failed (${status}):\n"
                            "${errors}")
    endif()
    # Loader and driver warnings help to diagnose a runner even when the check passes.
    string(STRIP "${errors}" errors)
    if(NOT errors STREQUAL "")
        message(STATUS "check-vulkan-device: vulkaninfo wrote to stderr:\n${errors}")
    endif()
endif()

# Each device block lists "apiVersion = 1.4.318"; older vulkaninfo versions print
# "apiVersion = 4206847 (1.3.255)". The instance and layer versions above "Devices:" do not count.
string(REPLACE "\r\n" "\n" summary "${summary}")
string(FIND "${summary}" "\nDevices:" devices_at)
set(versions "")
set(found FALSE)
if(NOT devices_at EQUAL -1)
    string(SUBSTRING "${summary}" ${devices_at} -1 devices)
    string(REGEX MATCHALL "apiVersion[ \t]*=[^\n]*" lines "${devices}")
    foreach(line IN LISTS lines)
        if(line MATCHES "([0-9]+)\\.([0-9]+)\\.([0-9]+)")
            set(version "${CMAKE_MATCH_1}.${CMAKE_MATCH_2}.${CMAKE_MATCH_3}")
            list(APPEND versions ${version})
            if(version VERSION_GREATER_EQUAL MIN_VERSION)
                set(found TRUE)
            endif()
        endif()
    endforeach()
endif()

if(NOT versions)
    message(FATAL_ERROR "check-vulkan-device: vulkaninfo lists no Vulkan device")
endif()
list(JOIN versions ", " version_list)
if(NOT found)
    message(FATAL_ERROR "check-vulkan-device: no Vulkan device reports apiVersion ${MIN_VERSION} or "
                        "newer (found: ${version_list})")
endif()
message(STATUS "Vulkan device check passed: apiVersion ${version_list} (${MIN_VERSION} required)")
