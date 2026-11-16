# Tests the Linux AddressSanitizer test environment of cmake/DvvCompilerOptions.cmake: the tests
# preload a helper that keeps the Vulkan driver and layers (here a fake validation layer of the
# prefix) loaded until exit, and only under AddressSanitizer. Linux hosts only.
# Run: cmake -DWORK_DIR=<empty scratch dir> -DCXX=<Clang 19 or newer> [-DGENERATOR=<generator>]
#            -P tests/cmake/test_keep_loaded.cmake
cmake_minimum_required(VERSION 4.2)
if(NOT DEFINED WORK_DIR OR NOT DEFINED CXX)
    message(FATAL_ERROR "pass -DWORK_DIR=<scratch directory> -DCXX=<C++ compiler>")
endif()
if(NOT CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
    message(STATUS "keep-loaded tests: skipped (Linux only)")
    return()
endif()
if(NOT DEFINED GENERATOR)
    set(GENERATOR Ninja)
endif()
file(REMOVE_RECURSE "${WORK_DIR}")
cmake_path(SET options NORMALIZE "${CMAKE_CURRENT_LIST_DIR}/../../cmake/DvvCompilerOptions.cmake")

# A prefix whose validation layer manifest names its library relative to itself, as the SDK's does.
set(prefix "${WORK_DIR}/prefix")
set(layer "${prefix}/lib/libVkLayer_khronos_validation.so")
file(WRITE "${prefix}/share/vulkan/explicit_layer.d/VkLayer_khronos_validation.json"
     [[{"file_format_version": "1.2.0", "layer": {"name": "VK_LAYER_KHRONOS_validation",
        "library_path": "../../../lib/libVkLayer_khronos_validation.so"}}]])
# The fake layer: a library that the host below loads and unloads.
file(WRITE "${WORK_DIR}/layer.c" "int fake_layer_marker(void) { return 1; }\n")
file(MAKE_DIRECTORY "${prefix}/lib")
execute_process(COMMAND "${CXX}" -x c -fPIC -shared "${WORK_DIR}/layer.c" -o "${layer}"
                RESULT_VARIABLE status)
if(NOT status EQUAL 0)
    message(FATAL_ERROR "FAIL: building the fake layer")
endif()

file(WRITE "${WORK_DIR}/project/CMakeLists.txt" "cmake_minimum_required(VERSION 4.2)
project(keep_loaded CXX)
include(\"${options}\")
message(STATUS \"DVV_TEST_ENVIRONMENT=[\${DVV_TEST_ENVIRONMENT}]\")
")

# configure(<name> <expected output regex> [-D...]) configures the project in its own build tree.
function(configure name expected)
    execute_process(COMMAND "${CMAKE_COMMAND}" -S "${WORK_DIR}/project" -B "${WORK_DIR}/build-${name}"
                            -G "${GENERATOR}" "-DCMAKE_CXX_COMPILER=${CXX}"
                            "-DCMAKE_PREFIX_PATH=${prefix}" ${ARGN}
                    RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
    string(REGEX REPLACE "[ \t\r\n]+" " " output "${out}${err}")
    if(NOT status EQUAL 0)
        message(FATAL_ERROR "FAIL: ${name}: configure failed:\n${out}${err}")
    elseif(NOT output MATCHES "${expected}")
        message(FATAL_ERROR "FAIL: ${name}: output lacks '${expected}':\n${out}${err}")
    endif()
    set(output "${output}" PARENT_SCOPE)
endfunction()

set(helper "${WORK_DIR}/build-address/dvv-keep-loaded/libdvv_keep_loaded.so")
configure(address "LD_PRELOAD=set:${helper};DVV_KEEP_LOADED=set:[^;]*${layer}\\]"
          "-DDVV_SANITIZE=address")
if(NOT EXISTS "${helper}")
    message(FATAL_ERROR "FAIL: address: ${helper} was not built")
endif()
foreach(name IN ITEMS none thread)
    if(name STREQUAL "none")
        configure(${name} "DVV_TEST_ENVIRONMENT=\\[\\]")
    else()
        configure(${name} "DVV_TEST_ENVIRONMENT=\\[\\]" "-DDVV_SANITIZE=${name}")
    endif()
endforeach()

# The helper keeps a library loaded after its last dlclose, so its memory stays reachable.
file(WRITE "${WORK_DIR}/host.c" [[
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    void *handle = dlopen(argv[1], RTLD_NOW);
    if (handle == NULL || dlclose(handle) != 0) return 2;
    FILE *maps = fopen("/proc/self/maps", "r");
    char line[4096];
    int loaded = 0;
    while (fgets(line, sizeof line, maps) != NULL) loaded |= strstr(line, argv[1]) != NULL;
    fclose(maps);
    puts(loaded ? "loaded" : "unloaded");
    return 0;
}
]])
execute_process(COMMAND "${CXX}" -x c "${WORK_DIR}/host.c" -o "${WORK_DIR}/host" -ldl
                RESULT_VARIABLE status)
if(NOT status EQUAL 0)
    message(FATAL_ERROR "FAIL: building the host")
endif()
# run(<expected> [env...]) runs the host on the fake layer with the environment.
function(run expected)
    execute_process(COMMAND "${CMAKE_COMMAND}" -E env ${ARGN} "${WORK_DIR}/host" "${layer}"
                    RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
    string(STRIP "${out}" out)
    if(NOT status EQUAL 0 OR NOT out STREQUAL expected OR NOT err STREQUAL "")
        message(FATAL_ERROR "FAIL: host with [${ARGN}]: '${out}' (exit ${status}, expected "
                            "'${expected}'):\n${err}")
    endif()
endfunction()
run(unloaded)
run(loaded "LD_PRELOAD=${helper}" "DVV_KEEP_LOADED=${layer}")
# A library that cannot be opened is reported and changes nothing else.
execute_process(COMMAND "${CMAKE_COMMAND}" -E env "LD_PRELOAD=${helper}"
                        "DVV_KEEP_LOADED=${WORK_DIR}/missing.so" "${WORK_DIR}/host" "${layer}"
                RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT status EQUAL 0 OR NOT out MATCHES "^unloaded" OR NOT err MATCHES "dvv_keep_loaded: .*missing\\.so")
    message(FATAL_ERROR "FAIL: missing library: '${out}' (exit ${status}):\n${err}")
endif()
message(STATUS "keep-loaded tests passed")
