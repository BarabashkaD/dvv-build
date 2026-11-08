# Checks that the two preset files of dvv-build describe the same presets (M5 layout):
#   cmake/DvvPresets.json     lib layout, dvv root = ${sourceParentDir}
#   cmake/DvvAppPresets.json  app layout, dvv root = ${sourceDir}/libs
# After replacing the app root by the lib root, the files must be equal line by line. Fails with the
# first differing line.
#   cmake [-DLIB_PRESETS=<file>] [-DAPP_PRESETS=<file>] -P test_presets_consistency.cmake
cmake_minimum_required(VERSION 4.2)

if(NOT DEFINED LIB_PRESETS)
    set(LIB_PRESETS "${CMAKE_CURRENT_LIST_DIR}/../../cmake/DvvPresets.json")
endif()
if(NOT DEFINED APP_PRESETS)
    set(APP_PRESETS "${CMAKE_CURRENT_LIST_DIR}/../../cmake/DvvAppPresets.json")
endif()
set(lib_root [=[${sourceParentDir}]=])
set(app_root [=[${sourceDir}/libs]=])

foreach(file IN ITEMS "${LIB_PRESETS}" "${APP_PRESETS}")
    if(NOT EXISTS "${file}")
        message(FATAL_ERROR "presets consistency: ${file} does not exist")
    endif()
endforeach()
file(READ "${LIB_PRESETS}" lib_text)
file(READ "${APP_PRESETS}" app_text)
string(REPLACE "\r" "" lib_text "${lib_text}")
string(REPLACE "\r" "" app_text "${app_text}")

# Each file uses only its own root token, and neither uses ${fileDir} (it follows the including file).
foreach(check IN ITEMS "lib|${LIB_PRESETS}|lib_text" "app|${APP_PRESETS}|app_text")
    string(REPLACE "|" ";" check "${check}")
    list(GET check 0 kind)
    list(GET check 1 file)
    list(GET check 2 var)
    string(FIND "${${var}}" [=[${fileDir}]=] pos)
    if(NOT pos EQUAL -1)
        message(FATAL_ERROR "presets consistency: ${file} uses \${fileDir}")
    endif()
    if(kind STREQUAL "lib")
        set(own "${lib_root}")
        set(foreign [=[${sourceDir}]=])
    else()
        set(own "${app_root}")
        set(foreign "${lib_root}")
    endif()
    string(FIND "${${var}}" "${own}" pos)
    if(pos EQUAL -1)
        message(FATAL_ERROR "presets consistency: ${file} does not use its root ${own}")
    endif()
    string(REPLACE "${own}" "" rest "${${var}}")
    string(FIND "${rest}" "${foreign}" pos)
    if(NOT pos EQUAL -1)
        message(FATAL_ERROR "presets consistency: ${file} uses ${foreign} outside its root ${own}")
    endif()
endforeach()

# Every toolchain preset searches the prefix and, after it, the wxWidgets prefix next to it
# (_third_party/<toolchain>-wx, which CI caches on its own).
foreach(check IN ITEMS "${LIB_PRESETS}|lib_text|${lib_root}" "${APP_PRESETS}|app_text|${app_root}")
    string(REPLACE "|" ";" check "${check}")
    list(GET check 0 file)
    list(GET check 1 var)
    list(GET check 2 root)
    foreach(toolchain IN ITEMS msvc clang appleclang)
        set(item "\"CMAKE_PREFIX_PATH\": \"${root}/_third_party/${toolchain};\
${root}/_third_party/${toolchain}-wx\"")
        string(FIND "${${var}}" "${item}" pos)
        if(pos EQUAL -1)
            message(FATAL_ERROR "presets consistency: ${file} lacks the CMAKE_PREFIX_PATH of "
                                "${toolchain}: ${item}")
        endif()
    endforeach()
    string(REGEX MATCHALL "\"CMAKE_PREFIX_PATH\":" paths "${${var}}")
    list(LENGTH paths count)
    if(NOT count EQUAL 3)
        message(FATAL_ERROR "presets consistency: ${file} sets CMAKE_PREFIX_PATH ${count} times, "
                            "not once per toolchain")
    endif()
endforeach()

# The macOS presets (Apple Silicon) must exist in both files with their cache variables.
foreach(check IN ITEMS "${LIB_PRESETS}|lib_text|${lib_root}" "${APP_PRESETS}|app_text|${app_root}")
    string(REPLACE "|" ";" check "${check}")
    list(GET check 0 file)
    list(GET check 1 var)
    list(GET check 2 root)
    set(expected_macos
        [=["name": "ninja-macos",]=]
        [=["name": "ninja-macos-asan",]=]
        [=["name": "ninja-macos-release",]=]
        [=["name": "ninja-macos-sanity",]=]
        [=["name": "ninja-macos-small",]=]
        [=["rhs": "Darwin"]=]
        [=["generator": "Ninja Multi-Config"]=]
        "\"CMAKE_BUILD_RPATH\": \"${root}/_third_party/appleclang/lib\""
        [=["CMAKE_OSX_DEPLOYMENT_TARGET": "27.0"]=]
        [=["CMAKE_OSX_ARCHITECTURES": "arm64"]=]
        [=["CMAKE_EXPORT_COMPILE_COMMANDS": "ON"]=]
        [=["CMAKE_C_COMPILER": "/usr/bin/clang"]=]
        [=["CMAKE_CXX_COMPILER": "/usr/bin/clang++"]=]
        [=["CMAKE_OBJC_COMPILER": "/usr/bin/clang"]=]
        [=["CMAKE_OBJCXX_COMPILER": "/usr/bin/clang++"]=]
        [=["DVV_SANITIZE": "address;undefined"]=])
    foreach(item IN LISTS expected_macos)
        string(FIND "${${var}}" "${item}" pos)
        if(pos EQUAL -1)
            message(FATAL_ERROR "presets consistency: ${file} lacks the macOS preset text: ${item}")
        endif()
    endforeach()
    # Build, test and workflow presets (release is a configuration of ninja-macos, as on Linux).
    set(expected_kinds
        [=["configurePreset": "ninja-macos", "configuration": "Debug" }]=]
        [=["configurePreset": "ninja-macos", "configuration": "Release" }]=]
        [=["configurePreset": "ninja-macos-asan", "configuration": "Debug" }]=]
        [=[{ "type": "configure", "name": "ninja-macos" }]=]
        [=[{ "type": "test", "name": "ninja-macos-release" }]=]
        [=[{ "type": "configure", "name": "ninja-macos-asan" }]=]
        [=[{ "type": "test", "name": "ninja-macos-asan" }]=])
    foreach(item IN LISTS expected_kinds)
        string(FIND "${${var}}" "${item}" pos)
        if(pos EQUAL -1)
            message(FATAL_ERROR "presets consistency: ${file} lacks the macOS preset text: ${item}")
        endif()
    endforeach()
endforeach()

string(REPLACE "${app_root}" "${lib_root}" app_text "${app_text}")
if(lib_text STREQUAL app_text)
    message(STATUS "presets consistency: OK")
    return()
endif()

# Walk both texts line by line (no CMake lists: JSON holds ';' and brackets).
set(line_no 0)
while(TRUE)
    math(EXPR line_no "${line_no} + 1")
    foreach(var IN ITEMS lib_text app_text)
        string(FIND "${${var}}" "\n" pos)
        if(pos EQUAL -1)
            set(${var}_line "${${var}}")
            set(${var} "")
        else()
            string(SUBSTRING "${${var}}" 0 ${pos} ${var}_line)
            math(EXPR pos "${pos} + 1")
            string(SUBSTRING "${${var}}" ${pos} -1 ${var})
        endif()
    endforeach()
    if(NOT lib_text_line STREQUAL app_text_line)
        message(FATAL_ERROR "presets consistency: line ${line_no} differs (app root replaced by "
                            "${lib_root}):\n  ${LIB_PRESETS}: ${lib_text_line}\n"
                            "  ${APP_PRESETS}: ${app_text_line}")
    endif()
    if(lib_text STREQUAL "" AND app_text STREQUAL "")
        message(FATAL_ERROR "presets consistency: the files differ only in the final newline")
    endif()
endwhile()
