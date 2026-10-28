# Tests for tools/check-vulkan-device.cmake, mostly on saved `vulkaninfo --summary` output.
# Run: cmake -DWORK_DIR=<empty scratch dir> -P tests/ci/test_check_vulkan_device.cmake
cmake_minimum_required(VERSION 4.2)
if(NOT DEFINED WORK_DIR)
    message(FATAL_ERROR "pass -DWORK_DIR=<scratch directory>")
endif()
set(script "${CMAKE_CURRENT_LIST_DIR}/../../tools/check-vulkan-device.cmake")
file(REMOVE_RECURSE "${WORK_DIR}")
file(MAKE_DIRECTORY "${WORK_DIR}")

# check(<0|1 expected failure> <expected output regex> [-D<name>=<value>...])
function(check expect_failure expected_text)
    execute_process(COMMAND "${CMAKE_COMMAND}" ${ARGN} -P "${script}"
                    RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
    string(REGEX REPLACE "[ \t\r\n]+" " " output "${out}${err}")
    if(expect_failure AND status EQUAL 0)
        message(FATAL_ERROR "FAIL: check-vulkan-device ${ARGN} succeeded:\n${out}${err}")
    elseif(NOT expect_failure AND NOT status EQUAL 0)
        message(FATAL_ERROR "FAIL: check-vulkan-device ${ARGN} failed:\n${out}${err}")
    elseif(NOT output MATCHES "${expected_text}")
        message(FATAL_ERROR "FAIL: output of check-vulkan-device ${ARGN} lacks '${expected_text}':\n"
                            "${out}${err}")
    endif()
endfunction()

# summary(<file name> <device block>...) writes a summary in vulkaninfo's layout: instance and layer
# versions first (never counted), then the devices.
function(summary name)
    string(CONCAT text "==========\nVULKANINFO\n==========\n\nVulkan Instance Version: 1.4.304\n\n"
                  "Instance Layers: count = 1\n--------------------------\n"
                  "VK_LAYER_MESA_device_select Linux device selection layer 1.4.303  version 1\n\n"
                  "Devices:\n========\n")
    set(index 0)
    foreach(block IN LISTS ARGN)
        string(APPEND text "GPU${index}:\n${block}")
        math(EXPR index "${index} + 1")
    endforeach()
    file(WRITE "${WORK_DIR}/${name}" "${text}")
endfunction()

string(CONCAT lavapipe "\tapiVersion         = 1.4.318\n\tdriverVersion      = 25.2.8\n"
              "\tdeviceType         = PHYSICAL_DEVICE_TYPE_CPU\n"
              "\tdeviceName         = llvmpipe (LLVM 20.1.2, 256 bits)\n")
string(CONCAT old_driver "\tapiVersion         = 1.3.289\n\tdriverVersion      = 24.2.8\n"
              "\tdeviceType         = PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU\n")

summary(lavapipe.txt "${lavapipe}")
check(0 "Vulkan device check passed: apiVersion 1.4.318 \\(1.4 required\\)"
      "-DSUMMARY_FILE=${WORK_DIR}/lavapipe.txt")
summary(two.txt "${old_driver}" "${lavapipe}")
check(0 "passed: apiVersion 1.3.289, 1.4.318" "-DSUMMARY_FILE=${WORK_DIR}/two.txt")
# CRLF line ends (vulkaninfo on Windows).
file(READ "${WORK_DIR}/lavapipe.txt" text)
string(REPLACE "\n" "\r\n" text "${text}")
file(WRITE "${WORK_DIR}/crlf.txt" "${text}")
check(0 "passed: apiVersion 1.4.318" "-DSUMMARY_FILE=${WORK_DIR}/crlf.txt")
# Older vulkaninfo versions print the packed number first.
summary(packed.txt "\tapiVersion     = 4210688 (1.4.0)\n")
check(0 "passed: apiVersion 1.4.0" "-DSUMMARY_FILE=${WORK_DIR}/packed.txt")

summary(old.txt "${old_driver}")
check(1 "no Vulkan device reports apiVersion 1.4 or newer \\(found: 1.3.289\\)"
      "-DSUMMARY_FILE=${WORK_DIR}/old.txt")
check(1 "no Vulkan device reports apiVersion 1.5 or newer \\(found: 1.4.318\\)"
      "-DSUMMARY_FILE=${WORK_DIR}/lavapipe.txt" -DMIN_VERSION=1.5)
check(0 "passed: apiVersion 1.3.289 \\(1.3 required\\)"
      "-DSUMMARY_FILE=${WORK_DIR}/old.txt" -DMIN_VERSION=1.3)
summary(none.txt)
check(1 "vulkaninfo lists no Vulkan device" "-DSUMMARY_FILE=${WORK_DIR}/none.txt")
# The instance version above "Devices:" is 1.4.304 but does not count.
file(WRITE "${WORK_DIR}/no-devices.txt"
     "Vulkan Instance Version: 1.4.304\n\nInstance Layers: count = 0\n")
check(1 "vulkaninfo lists no Vulkan device" "-DSUMMARY_FILE=${WORK_DIR}/no-devices.txt")
check(1 "MIN_VERSION must be <major>.<minor>, got '1.4.0'"
      "-DSUMMARY_FILE=${WORK_DIR}/lavapipe.txt" -DMIN_VERSION=1.4.0)

# A passing check also prints what vulkaninfo wrote to stderr (loader and driver warnings). The fake
# vulkaninfo is a batch file on Windows and a shell script elsewhere.
if(CMAKE_HOST_WIN32)
    set(fake "${WORK_DIR}/fake-vulkaninfo.cmd")
    file(TO_NATIVE_PATH "${WORK_DIR}/lavapipe.txt" native_summary)
    file(WRITE "${fake}" "@echo off\r\ntype \"${native_summary}\"\r\n"
                         "echo WARNING: fake loader message 1>&2\r\n")
else()
    set(fake "${WORK_DIR}/fake-vulkaninfo")
    file(WRITE "${fake}" "#!/bin/sh\ncat '${WORK_DIR}/lavapipe.txt'\n"
                         "echo 'WARNING: fake loader message' >&2\n")
    file(CHMOD "${fake}" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
endif()
check(0 "vulkaninfo wrote to stderr: WARNING: fake loader message .*passed: apiVersion 1.4.318"
      "-DVULKANINFO=${fake}")

# A failing vulkaninfo fails the check: cmake itself rejects --summary.
check(1 "--summary' failed" "-DVULKANINFO=${CMAKE_COMMAND}")
check(1 "--summary' failed" "-DVULKANINFO=${WORK_DIR}/no-such-program")

message(STATUS "check-vulkan-device tests passed")
