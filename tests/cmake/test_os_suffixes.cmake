# Tests the suffix lists and queries of cmake/DvvOsSources.cmake: the four lists, dvv_os_all_suffixes,
# dvv_os_suffixes_for, dvv_os_headers_for, and the FATAL_ERRORs (dvv_os_suffixes and dvv_os_headers in
# script mode, an unknown platform, a header that is not a .h file), which child runs of this script
# (-DCHILD=script_mode, bad_platform, headers_script_mode, headers_bad_platform, headers_not_h) observe.
#   cmake -P test_os_suffixes.cmake
cmake_minimum_required(VERSION 4.2)

include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/DvvOsSources.cmake")

if(CHILD STREQUAL "script_mode")
    dvv_os_suffixes(x)
    return()
elseif(CHILD STREQUAL "bad_platform")
    dvv_os_suffixes_for(FOO x)
    return()
elseif(CHILD STREQUAL "headers_script_mode")
    dvv_os_headers(x a.h)
    return()
elseif(CHILD STREQUAL "headers_bad_platform")
    dvv_os_headers_for(FOO x a.h)
    return()
elseif(CHILD STREQUAL "headers_not_h")
    dvv_os_headers_for(OTHER x dvv/p/x.hpp)
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

set(list dvv/p/plain.h dvv/p/io_win32.h dvv/p/io_posix.h dvv/p/view_metal.h dvv/p/view_xlib.h
         dvv/p/menu_cocoa.h dvv/p/menu_stub.h dvv/p/frame_vulkan.h dvv/a/x_stub.h dvv/b/x_win32.h
         dvv/p/metal.h dvv/p/posix_clock.h)
dvv_os_headers_for(WIN32 h ${list})
expect_eq("${h}" "dvv/p/plain.h;dvv/p/io_win32.h;dvv/p/menu_stub.h;dvv/p/frame_vulkan.h;dvv/a/x_stub.h;dvv/b/x_win32.h;dvv/p/metal.h;dvv/p/posix_clock.h")
dvv_os_headers_for(APPLE h ${list})
expect_eq("${h}" "dvv/p/plain.h;dvv/p/io_posix.h;dvv/p/view_metal.h;dvv/p/menu_cocoa.h;dvv/p/frame_vulkan.h;dvv/a/x_stub.h;dvv/p/metal.h;dvv/p/posix_clock.h")
dvv_os_headers_for(OTHER h ${list})
expect_eq("${h}" "dvv/p/plain.h;dvv/p/io_posix.h;dvv/p/view_xlib.h;dvv/p/menu_stub.h;dvv/p/frame_vulkan.h;dvv/a/x_stub.h;dvv/p/metal.h;dvv/p/posix_clock.h")
dvv_os_headers_for(OTHER h)
expect_eq("${h}" "")
# Only the file name's suffix counts: a header in a folder named like a suffix is kept on every OS.
foreach(platform IN ITEMS WIN32 APPLE OTHER)
    dvv_os_headers_for(${platform} h dvv/win32/x.h dvv/posix/y.h)
    expect_eq("${h}" "dvv/win32/x.h;dvv/posix/y.h")
endforeach()

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
expect_child_fails(headers_script_mode "dvv_os_suffixes needs a project \\(CMAKE_SYSTEM_NAME is not set\\)")
expect_child_fails(headers_bad_platform "unknown platform 'FOO'")
expect_child_fails(headers_not_h "dvv_os_headers_for: 'dvv/p/x.hpp' is not a .h file")

if(failures)
    message(FATAL_ERROR "os-suffixes tests failed")
endif()
message(STATUS "os-suffixes tests passed")
