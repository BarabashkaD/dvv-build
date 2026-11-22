# Tests dvv_add_header_check() of cmake/DvvHeaderCheck.cmake against fixture projects in WORK_DIR.
# A build fixture is configured once and built after each header change, with no re-configure: a
# header that does not compile on its own, a header of this OS, a warning, a deleted header. Each
# configure-error fixture checks one error and its message.
#   cmake -DWORK_DIR=<dir> -DGENERATOR=<generator> [-DPLATFORM=<platform>] [-DMAKE_PROGRAM=<path>]
#         [-DCXX=<compiler>] [-DPREFIX_PATH=<comma-separated>] [-DVK_DRIVER_FILES=<manifest>]
#         -P test_header_check.cmake
cmake_minimum_required(VERSION 4.2)

foreach(var IN ITEMS WORK_DIR GENERATOR)
    if(NOT DEFINED ${var} OR "${${var}}" STREQUAL "")
        message(FATAL_ERROR "test_header_check: -D${var}=... is required")
    endif()
endforeach()
file(TO_CMAKE_PATH "${WORK_DIR}" WORK_DIR)
set(CMAKE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../cmake")
cmake_path(NORMAL_PATH CMAKE_DIR)
set(MODULE "${CMAKE_DIR}/DvvHeaderCheck.cmake")
set(OPTIONS "${CMAKE_DIR}/DvvCompilerOptions.cmake")

if(CMAKE_HOST_WIN32)
    set(host_suffix win32)
    set(other_suffix posix)
elseif(CMAKE_HOST_APPLE)
    set(host_suffix macos)
    set(other_suffix win32)
else()
    set(host_suffix linux)
    set(other_suffix win32)
endif()
set(config_args "")
if(GENERATOR MATCHES "Multi-Config|Visual Studio|Xcode")
    set(config_args --config Debug)
endif()

set(failures FALSE)
file(REMOVE_RECURSE "${WORK_DIR}")

# Configures <dir> with the test's generator settings; sets rc and flat (flattened output) and raw in
# the caller. The prefix path and the Vulkan driver go in through an initial cache file.
function(configure dir)
    string(REPLACE "," ";" prefix_path "${PREFIX_PATH}")
    set(cache "${dir}/initial-cache.cmake")
    file(WRITE "${cache}" "set(CMAKE_PREFIX_PATH [==[${prefix_path}]==] CACHE STRING \"\")\n")
    if(VK_DRIVER_FILES)
        file(APPEND "${cache}"
             "set(DVV_TEST_VK_DRIVER_FILES [==[${VK_DRIVER_FILES}]==] CACHE FILEPATH \"\")\n")
    endif()
    set(args -C "${cache}" -S "${dir}" -B "${dir}/build" -G "${GENERATOR}")
    if(PLATFORM)
        list(APPEND args -A "${PLATFORM}")
    endif()
    if(MAKE_PROGRAM)
        list(APPEND args "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}")
    endif()
    if(CXX)
        list(APPEND args "-DCMAKE_CXX_COMPILER=${CXX}")
    endif()
    execute_process(COMMAND "${CMAKE_COMMAND}" ${args}
        RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE out)
    string(REGEX REPLACE "[ \t\r\n]+" " " flattened "${out}")
    set(rc "${result}" PARENT_SCOPE)
    set(flat "${flattened}" PARENT_SCOPE)
    set(raw "${out}" PARENT_SCOPE)
endfunction()

# Builds fx_header_check in <dir>/build; sets rc and raw in the caller.
function(build dir)
    execute_process(COMMAND "${CMAKE_COMMAND}" --build "${dir}/build" --target fx_header_check
                            ${config_args}
        RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE out)
    set(rc "${result}" PARENT_SCOPE)
    set(raw "${out}" PARENT_SCOPE)
endfunction()

# Reports a failure of <name> with <text> and the last output.
macro(fail name text)
    message(SEND_ERROR "${name}: ${text}:\n${raw}")
    set(failures TRUE)
endmacro()

# --- The build fixture: configured once, then one build per header change.
set(fx "${WORK_DIR}/build_fixture")
set(inc "${fx}/include")
file(WRITE "${fx}/CMakeLists.txt" "cmake_minimum_required(VERSION 4.2)
project(fx LANGUAGES CXX)
include(\"${OPTIONS}\")
include(\"${MODULE}\")
add_library(fx STATIC fx.cpp)
target_include_directories(fx PUBLIC \"\${CMAKE_CURRENT_SOURCE_DIR}/include\")
add_library(fx::fx ALIAS fx)
dvv_add_header_check(fx::fx \"\${CMAKE_CURRENT_SOURCE_DIR}/include\")
")
file(WRITE "${fx}/fx.cpp" "#include \"fx/a.h\"\n")
file(WRITE "${inc}/fx/a.h" "#pragma once\nstruct A {};\n")
file(WRITE "${inc}/x.h" "#pragma once\n")
file(WRITE "${inc}/sub/x.h" "#pragma once\n")
file(WRITE "${inc}/fx/io_${other_suffix}.h" "#pragma once\n#error other\n")

configure("${fx}")
if(NOT rc EQUAL 0)
    fail(build_fixture "configure failed (${rc})")
else()
    # 1. As is: passes; x.h and sub/x.h have their own units; the other OS's header has none.
    build("${fx}")
    if(NOT rc EQUAL 0)
        fail(as_is "the build failed (${rc})")
    endif()
    set(units "${fx}/build/fx_header_check")
    foreach(header IN ITEMS x.h sub/x.h)
        if(NOT EXISTS "${units}/${header}.cpp")
            fail(as_is "no unit ${header}.cpp")
        else()
            file(READ "${units}/${header}.cpp" content)
            if(NOT content STREQUAL "#include \"${header}\"\n")
                fail(as_is "${header}.cpp holds [${content}]")
            endif()
        endif()
    endforeach()
    if(EXISTS "${units}/fx/io_${other_suffix}.h.cpp")
        fail(as_is "a unit for fx/io_${other_suffix}.h exists")
    endif()

    # 2. A header that uses a name it does not include: the build fails and names it.
    file(WRITE "${inc}/fx/uses_a.h" "#pragma once\ninline A make() { return {}; }\n")
    build("${fx}")
    if(rc EQUAL 0)
        fail(uses_a "the build passed")
    elseif(NOT raw MATCHES "uses_a\\.h(:[0-9]+|\\([0-9]+)")
        fail(uses_a "the output does not name uses_a.h")
    endif()

    # 3. A header of this OS is checked.
    file(REMOVE "${inc}/fx/uses_a.h")
    file(WRITE "${inc}/fx/io_${host_suffix}.h" "#pragma once\n#error host\n")
    build("${fx}")
    if(rc EQUAL 0)
        fail(host_header "the build passed")
    elseif(NOT raw MATCHES "io_${host_suffix}\\.h(:[0-9]+|\\([0-9]+)")
        fail(host_header "the output does not name io_${host_suffix}.h")
    endif()

    # 4. A warning fails the build (the library's compiler options).
    file(REMOVE "${inc}/fx/io_${host_suffix}.h")
    file(WRITE "${inc}/fx/warn.h" "#pragma once\ninline int warn(int unused) { return 0; }\n")
    build("${fx}")
    if(rc EQUAL 0)
        fail(warning "the build passed")
    elseif(NOT raw MATCHES "warn\\.h(:[0-9]+|\\([0-9]+)")
        fail(warning "the output does not name warn.h")
    endif()

    # 5. A deleted header leaves the check; its stale unit is not built.
    file(REMOVE "${inc}/fx/warn.h")
    build("${fx}")
    if(NOT rc EQUAL 0)
        fail(deleted "the build failed (${rc})")
    endif()
endif()

# --- Configure errors. err(NAME <name> CALL <args> EXPECT <regex> [NO_OPTIONS] [EMPTY_ROOT]
#     [FILES <rel>...]): a project with an INTERFACE target e and a stub dvv_set_compiler_options
#     (none with NO_OPTIONS); FILES are written under the fixture folder.
function(err)
    cmake_parse_arguments(PARSE_ARGV 0 C "NO_OPTIONS;EMPTY_ROOT" "NAME;CALL;EXPECT" "FILES")
    set(dir "${WORK_DIR}/${C_NAME}")
    file(MAKE_DIRECTORY "${dir}")
    foreach(rel IN LISTS C_FILES)
        file(WRITE "${dir}/${rel}" "")
    endforeach()
    if(C_EMPTY_ROOT)
        file(MAKE_DIRECTORY "${dir}/include")
    endif()
    set(stub "function(dvv_set_compiler_options target)\nendfunction()\n")
    if(C_NO_OPTIONS)
        set(stub "")
    endif()
    file(WRITE "${dir}/CMakeLists.txt" "cmake_minimum_required(VERSION 4.2)
project(e LANGUAGES NONE)
${stub}include(\"${MODULE}\")
add_library(e INTERFACE)
dvv_add_header_check(${C_CALL})
")
    configure("${dir}")
    if(rc EQUAL 0)
        message(SEND_ERROR "${C_NAME}: expected a configure failure, it succeeded:\n${raw}")
        set(failures TRUE PARENT_SCOPE)
    elseif(NOT flat MATCHES "${C_EXPECT}")
        message(SEND_ERROR "${C_NAME}: output does not match [${C_EXPECT}]:\n${raw}")
        set(failures TRUE PARENT_SCOPE)
    endif()
endfunction()

set(root "\"\${CMAKE_CURRENT_SOURCE_DIR}/include\"")
err(NAME three_args CALL "e ${root} extra" FILES include/x.h
    EXPECT "dvv_add_header_check\\(<target> <include-root>\\) takes two arguments")
err(NAME no_options CALL "e ${root}" NO_OPTIONS FILES include/x.h
    EXPECT "dvv_set_compiler_options is not defined; include DvvCompilerOptions\\.cmake first")
err(NAME not_target CALL "nope ${root}" FILES include/x.h EXPECT "'nope' is not a target")
err(NAME relative_root CALL "e include" FILES include/x.h EXPECT "include is not an absolute path")
err(NAME missing_root CALL "e ${root}" EXPECT "does not exist")
err(NAME empty_root CALL "e ${root}" EMPTY_ROOT EXPECT "holds no \\.h file")
err(NAME other_os_only CALL "e ${root}" FILES include/dvv/io_${other_suffix}.h
    EXPECT "holds no \\.h file for this platform")
err(NAME hpp CALL "e ${root}" FILES include/dvv/x.hpp
    EXPECT "dvv/x\\.hpp under .* is not a \\.h file")
err(NAME ds_store CALL "e ${root}" FILES include/dvv/x.h include/dvv/.DS_Store
    EXPECT "dvv/\\.DS_Store under .* is not a \\.h file")

if(failures)
    message(FATAL_ERROR "test_header_check: failures")
endif()
message(STATUS "test_header_check: all cases passed")
