# Tests the suffix lists and queries of cmake/DvvOsSources.cmake: the four lists, dvv_os_all_suffixes,
# dvv_os_suffixes_for, and the two FATAL_ERRORs (dvv_os_suffixes in script mode, an unknown platform),
# which child runs of this script (-DCHILD=script_mode, -DCHILD=bad_platform) observe.
#   cmake -P test_os_suffixes.cmake
cmake_minimum_required(VERSION 4.2)

include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/DvvOsSources.cmake")

if(CHILD STREQUAL "script_mode")
    dvv_os_suffixes(x)
    return()
elseif(CHILD STREQUAL "bad_platform")
    dvv_os_suffixes_for(FOO x)
    return()
endif()

set(failures FALSE)
function(expect_eq actual expected)
    if(NOT "${actual}" STREQUAL "${expected}")
        message(SEND_ERROR "expected [${expected}], got [${actual}]")
        set(failures TRUE PARENT_SCOPE)
    endif()
endfunction()

expect_eq("${DVV_OS_SUFFIXES_WIN32}" "win32;msw")
expect_eq("${DVV_OS_SUFFIXES_APPLE}" "posix;macos;metal;cocoa")
expect_eq("${DVV_OS_SUFFIXES_OTHER}" "posix;linux;xlib;gtk")
expect_eq("${DVV_OS_SUFFIX_FALLBACK}" "stub")

dvv_os_all_suffixes(all)
list(SORT all)
expect_eq("${all}" "cocoa;gtk;linux;macos;metal;msw;posix;stub;win32;xlib")
dvv_os_suffixes_for(WIN32 w)
expect_eq("${w}" "win32;msw")
dvv_os_suffixes_for(APPLE a)
expect_eq("${a}" "posix;macos;metal;cocoa")
dvv_os_suffixes_for(OTHER o)
expect_eq("${o}" "posix;linux;xlib;gtk")

# Runs this script as a child with -DCHILD=<mode>; expects a non-zero exit and output matching <regex>.
function(expect_child_fails mode regex)
    execute_process(COMMAND ${CMAKE_COMMAND} -DCHILD=${mode} -P "${CMAKE_CURRENT_LIST_FILE}"
                    RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE out)
    if(result EQUAL 0)
        message(SEND_ERROR "child ${mode}: expected a non-zero exit")
        set(failures TRUE PARENT_SCOPE)
    endif()
    if(NOT out MATCHES "${regex}")
        message(SEND_ERROR "child ${mode}: output does not match [${regex}]: ${out}")
        set(failures TRUE PARENT_SCOPE)
    endif()
endfunction()
expect_child_fails(script_mode "dvv_os_suffixes needs a project \\(CMAKE_SYSTEM_NAME is not set\\)")
expect_child_fails(bad_platform "unknown platform 'FOO'")

if(failures)
    message(FATAL_ERROR "os-suffixes tests failed")
endif()
message(STATUS "os-suffixes tests passed")
