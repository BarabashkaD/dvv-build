# Regression test for test_presets_consistency.cmake: an edited copy of DvvAppPresets.json in
# WORK_DIR must make the consistency check fail and name the differing line.
#   cmake -DWORK_DIR=<dir> -P test_presets_consistency_drift.cmake
cmake_minimum_required(VERSION 4.2)

if(NOT DEFINED WORK_DIR OR WORK_DIR STREQUAL "")
    message(FATAL_ERROR "presets drift: -DWORK_DIR=... is required")
endif()
set(app_presets "${CMAKE_CURRENT_LIST_DIR}/../../cmake/DvvAppPresets.json")
set(copy "${WORK_DIR}/DvvAppPresets.json")

file(READ "${app_presets}" text)
set(from [=["generator": "Visual Studio 18 2026"]=])
set(to [=["generator": "Visual Studio 17 2022"]=])
string(FIND "${text}" "${from}" pos)
if(pos EQUAL -1)
    message(FATAL_ERROR "presets drift: ${app_presets} has no ${from}; update this test")
endif()
string(REPLACE "${from}" "${to}" text "${text}")
file(MAKE_DIRECTORY "${WORK_DIR}")
file(WRITE "${copy}" "${text}")

execute_process(COMMAND "${CMAKE_COMMAND}" "-DAPP_PRESETS=${copy}"
                        -P "${CMAKE_CURRENT_LIST_DIR}/test_presets_consistency.cmake"
                RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE out)
string(REGEX REPLACE "\n +" " " flat "${out}")
if(rc EQUAL 0)
    message(FATAL_ERROR "presets drift: the check passed on an edited copy:\n${out}")
endif()
if(NOT flat MATCHES "presets consistency: line [0-9]+ differs"
   OR NOT flat MATCHES "Visual Studio 17 2022")
    message(FATAL_ERROR "presets drift: the check failed without naming the differing line:\n${out}")
endif()
message(STATUS "presets drift: the edited copy is rejected as expected")
