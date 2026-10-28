# Shared compiler settings for every dvv repository (spec §2, §13.3). Part of dvv-build and
# installed with dvv_base; repositories include it as "${DVV_CMAKE_DIR}/DvvCompilerOptions.cmake",
# which dvv_base defines both in-tree (dvv-build's cmake folder) and from the installed package.
include_guard(DIRECTORY)

# CMake maps C++23 to /std:c++latest for MSVC, which follows C++26 drafts; use the C++23 switch.
if(MSVC)
    set(CMAKE_CXX23_STANDARD_COMPILE_OPTION "-std:c++23preview")
    set(CMAKE_CXX23_EXTENSION_COMPILE_OPTION "-std:c++23preview")
else()
    # Outside MSVC only Clang with libstdc++ 14 or newer is supported (spec §2, §17).
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
