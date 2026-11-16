# Shared compiler settings for every dvv repository (spec §2, §13.3). Part of dvv-build and
# installed with dvv_base; repositories include it as "${DVV_CMAKE_DIR}/DvvCompilerOptions.cmake",
# which dvv_base defines both in-tree (dvv-build's cmake folder) and from the installed package.
include_guard(DIRECTORY)

# CMake maps C++23 to /std:c++latest for MSVC, which follows C++26 drafts; use the C++23 switch.
if(MSVC)
    set(CMAKE_CXX23_STANDARD_COMPILE_OPTION "-std:c++23preview")
    set(CMAKE_CXX23_EXTENSION_COMPILE_OPTION "-std:c++23preview")
elseif(APPLE)
    # On macOS only AppleClang 21 or newer (Xcode 27) with its libc++ is supported.
    if(NOT CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang" OR CMAKE_CXX_COMPILER_VERSION VERSION_LESS 21)
        message(FATAL_ERROR "${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION} is not "
                            "supported; use AppleClang 21 or newer (Xcode 27)")
    endif()
    include(CheckCXXSourceCompiles)
    check_cxx_source_compiles([[
#include <version>
#ifndef _LIBCPP_VERSION
#error "libc++ is required"
#endif
int main() {}
]] DVV_HAS_LIBCXX)
    if(NOT DVV_HAS_LIBCXX)
        # Forget the failure so the next configure checks again.
        unset(DVV_HAS_LIBCXX CACHE)
        message(FATAL_ERROR "AppleClang must use libc++")
    endif()
else()
    # Outside MSVC and macOS only Clang with libstdc++ 14 or newer is supported (spec §2, §17).
    if(NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang" OR CMAKE_CXX_COMPILER_VERSION VERSION_LESS 19)
        message(FATAL_ERROR "${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION} is not "
                            "supported; use Clang 19 or newer")
    endif()
    include(CheckCXXSourceCompiles)
    check_cxx_source_compiles([[
#include <version>
#if !defined(__GLIBCXX__) || _GLIBCXX_RELEASE < 14
#error "libstdc++ 14 or newer is required"
#endif
int main() {}
]] DVV_HAS_LIBSTDCXX_14)
    if(NOT DVV_HAS_LIBSTDCXX_14)
        # Forget the failure so the next configure checks again after the install.
        unset(DVV_HAS_LIBSTDCXX_14 CACHE)
        message(FATAL_ERROR "Clang must use libstdc++ 14 or newer; install libstdc++-14-dev")
    endif()
endif()

set(DVV_SANITIZE "" CACHE STRING "Sanitizers: empty, address, address;undefined or thread")
# Tests use it as ENVIRONMENT_MODIFICATION (the MSVC ASan runtime DLL lives next to cl.exe).
set(DVV_TEST_ENVIRONMENT "")
if(DVV_SANITIZE)
    if(MSVC)
        if(NOT DVV_SANITIZE STREQUAL "address")
            message(FATAL_ERROR "MSVC supports only DVV_SANITIZE=address")
        endif()
        add_compile_options(/fsanitize=address /Zi)
        add_link_options(/INCREMENTAL:NO)
        cmake_path(GET CMAKE_CXX_COMPILER PARENT_PATH msvc_bin_dir)
        set(DVV_TEST_ENVIRONMENT "PATH=path_list_prepend:${msvc_bin_dir}")
    else()
        list(JOIN DVV_SANITIZE "," sanitizers)
        add_compile_options(-fsanitize=${sanitizers} -fno-omit-frame-pointer
                            -fno-sanitize-recover=all)
        add_link_options(-fsanitize=${sanitizers})
    endif()
endif()
# On macOS every test runs on one Vulkan driver only, whatever other drivers (MoltenVK of an installed
# SDK) the machine has: the prefix's KosmicKrisp (spec U-MAC2), or the manifest that
# DVV_TEST_VK_DRIVER_FILES names. The CI jobs set it to lavapipe's when the runner's Metal device
# cannot run KosmicKrisp (a CI-only exception to U-MAC2; lavapipe is never shipped).
set(DVV_TEST_VK_DRIVER_FILES "" CACHE FILEPATH
    "macOS: the Vulkan driver manifest the tests run on (empty: the prefix's KosmicKrisp)")
if(APPLE)
    if(DVV_TEST_VK_DRIVER_FILES)
        if(NOT EXISTS "${DVV_TEST_VK_DRIVER_FILES}" OR IS_DIRECTORY "${DVV_TEST_VK_DRIVER_FILES}")
            message(FATAL_ERROR "DVV_TEST_VK_DRIVER_FILES names ${DVV_TEST_VK_DRIVER_FILES}, which does "
                                "not exist")
        endif()
        set(test_driver "${DVV_TEST_VK_DRIVER_FILES}")
    else()
        find_file(DVV_KOSMICKRISP_MANIFEST libkosmickrisp_icd.json PATHS ${CMAKE_PREFIX_PATH}
                  PATH_SUFFIXES share/vulkan/icd.d NO_DEFAULT_PATH NO_CACHE)
        if(NOT DVV_KOSMICKRISP_MANIFEST)
            message(FATAL_ERROR "No share/vulkan/icd.d/libkosmickrisp_icd.json in CMAKE_PREFIX_PATH "
                                "(${CMAKE_PREFIX_PATH}); run dvv-build's bootstrap.sh")
        endif()
        set(test_driver "${DVV_KOSMICKRISP_MANIFEST}")
    endif()
    list(APPEND DVV_TEST_ENVIRONMENT "VK_DRIVER_FILES=set:${test_driver}")
endif()
# Linux AddressSanitizer: the Vulkan loader unloads the layers when an instance is destroyed. Memory
# that a layer still references from its own globals then looks lost to LeakSanitizer, which runs at
# exit and scans only the modules still loaded: the CI runs reported it as intermittent direct and
# indirect leaks with "<unknown module>" frames, in no code of ours. So every test preloads a small
# helper (written and built here, without sanitizers) that opens lavapipe, Mesa's device_select
# layer and the prefix's validation layer with RTLD_NODELETE: they stay loaded until exit, their
# memory stays reachable, and leak checking stays complete with no suppressions. RTLD_LOCAL keeps
# their symbols out of the global scope (the validation layer exports vkGetInstanceProcAddr).
if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND "address" IN_LIST DVV_SANITIZE)
    set(keep_loaded "")
    foreach(name IN ITEMS vulkan_lvp VkLayer_MESA_device_select)
        find_library(DVV_KEEP_LOADED_${name} ${name} NO_CACHE)
        if(DVV_KEEP_LOADED_${name})
            list(APPEND keep_loaded "${DVV_KEEP_LOADED_${name}}")
        endif()
    endforeach()
    find_file(DVV_VALIDATION_LAYER_MANIFEST VkLayer_khronos_validation.json PATHS ${CMAKE_PREFIX_PATH}
              PATH_SUFFIXES share/vulkan/explicit_layer.d NO_DEFAULT_PATH NO_CACHE)
    if(DVV_VALIDATION_LAYER_MANIFEST)
        file(READ "${DVV_VALIDATION_LAYER_MANIFEST}" manifest)
        string(JSON library ERROR_VARIABLE json_error GET "${manifest}" layer library_path)
        # A library_path with a slash is relative to the manifest; a bare name is looked up by
        # dlopen, the same way as the loader does it.
        if(NOT json_error AND library MATCHES "/")
            cmake_path(GET DVV_VALIDATION_LAYER_MANIFEST PARENT_PATH manifest_dir)
            cmake_path(ABSOLUTE_PATH library BASE_DIRECTORY "${manifest_dir}" NORMALIZE)
        endif()
        if(NOT json_error)
            list(APPEND keep_loaded "${library}")
        endif()
    endif()
    if(keep_loaded)
        set(helper_dir "${CMAKE_BINARY_DIR}/dvv-keep-loaded")
        file(CONFIGURE OUTPUT "${helper_dir}/dvv_keep_loaded.c" @ONLY CONTENT [[
/* Written by dvv-build's DvvCompilerOptions.cmake; preloaded into the Linux ASan tests. Opens each
   library that DVV_KEEP_LOADED names (colon-separated) so that it stays loaded until exit. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

__attribute__((constructor)) static void dvv_keep_loaded(void) {
    const char *list = getenv("DVV_KEEP_LOADED");
    if (list == NULL) return;
    char *copy = strdup(list), *save = NULL;
    for (char *name = strtok_r(copy, ":", &save); name != NULL; name = strtok_r(NULL, ":", &save)) {
        if (dlopen(name, RTLD_NOW | RTLD_LOCAL | RTLD_NODELETE) == NULL)
            fprintf(stderr, "dvv_keep_loaded: %s\n", dlerror());
    }
    free(copy);
}
]])
        set(helper "${helper_dir}/libdvv_keep_loaded.so")
        if(NOT EXISTS "${helper}" OR "${helper_dir}/dvv_keep_loaded.c" IS_NEWER_THAN "${helper}")
            execute_process(COMMAND "${CMAKE_CXX_COMPILER}" -x c -O2 -fPIC -shared
                                    "${helper_dir}/dvv_keep_loaded.c" -o "${helper}" -ldl
                            RESULT_VARIABLE status ERROR_VARIABLE error)
            if(NOT status EQUAL 0)
                file(REMOVE "${helper}")
                message(FATAL_ERROR "Building ${helper} failed:\n${error}")
            endif()
        endif()
        list(JOIN keep_loaded ":" keep_loaded)
        list(APPEND DVV_TEST_ENVIRONMENT "LD_PRELOAD=set:${helper}"
                                         "DVV_KEEP_LOADED=set:${keep_loaded}")
    endif()
endif()

# Maps the parent of the top-level source tree (a library's dvv root, or the folder holding the app)
# out of __FILE__ and std::source_location so binaries carry no machine path.
cmake_path(GET CMAKE_SOURCE_DIR PARENT_PATH DVV_PATH_MAP_ROOT)

# dvv_set_compiler_options(<target>): C++23, no module scanning, warnings as errors for our code.
function(dvv_set_compiler_options target)
    target_compile_features(${target} PUBLIC cxx_std_23)
    set_target_properties(${target} PROPERTIES CXX_EXTENSIONS OFF CXX_SCAN_FOR_MODULES OFF)
    if(MSVC)
        target_compile_options(${target} PRIVATE
            /W4 /WX /permissive- /utf-8 /EHsc /Zc:__cplusplus /Zc:preprocessor
            /external:anglebrackets /external:W0)
        target_compile_definitions(${target} PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
    else()
        target_compile_options(${target} PRIVATE
            -Wall -Wextra -Wpedantic -Werror "-ffile-prefix-map=${DVV_PATH_MAP_ROOT}/=")
    endif()
endfunction()
