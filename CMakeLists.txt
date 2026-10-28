# dvv-build's own tests: the superbuild scripts and licence gate, the tools, the preset files and the
# consumers of the third-party prefix. The dvv repositories build in their own trees (presets).
cmake_minimum_required(VERSION 4.2)
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" dvv_build_version LIMIT_COUNT 1)
if(NOT dvv_build_version MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$")
    message(FATAL_ERROR "dvv-build: VERSION must hold <major>.<minor>.<patch>, found '${dvv_build_version}'")
endif()
project(dvv_build VERSION ${dvv_build_version} LANGUAGES CXX)
# A changed VERSION re-runs the configure.
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION")

# The shared dvv presets set these for every repository. dvv-build has no dependencies, finds its
# cmake folder itself and compiles nothing itself, so only DVV_BUILD_TESTS applies here. Naming the
# others once keeps CMake's "Manually-specified variables were not used" warning away (DVV_SANITIZE
# is read by the tests below, so it is named here for DVV_BUILD_TESTS=OFF).
option(DVV_BUILD_TESTS "Build the dvv-build tests" ON)
message(VERBOSE "dvv-build: not used here: DVV_BUILD_CMAKE_DIR='${DVV_BUILD_CMAKE_DIR}', "
                "DVV_TEST_DEPENDENCIES='${DVV_TEST_DEPENDENCIES}', "
                "CMAKE_EXPORT_COMPILE_COMMANDS='${CMAKE_EXPORT_COMPILE_COMMANDS}', "
                "DVV_SANITIZE='${DVV_SANITIZE}'")
if(NOT DVV_BUILD_TESTS)
    return()
endif()

enable_testing()
# The compiler rules (DvvCompilerOptions.cmake, run-compile-fail.cmake) live in this repository.
set(DVV_CMAKE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

add_test(NAME dvv_build.presets_consistency
         COMMAND ${CMAKE_COMMAND} -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/cmake/test_presets_consistency.cmake)
add_test(NAME dvv_build.presets_consistency_drift
         COMMAND ${CMAKE_COMMAND} -DWORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/presets-drift-test
                 -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/cmake/test_presets_consistency_drift.cmake)
add_test(NAME dvv_build.dvv_deps
         COMMAND ${CMAKE_COMMAND} -DWORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/dvv-deps-test
                 -DGENERATOR=${CMAKE_GENERATOR}
                 -DPLATFORM=${CMAKE_GENERATOR_PLATFORM}
                 -DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}
                 -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/cmake/test_dvv_deps.cmake)
set_tests_properties(dvv_build.dvv_deps PROPERTIES TIMEOUT 300)
add_test(NAME dvv_build.spdx
         COMMAND ${CMAKE_COMMAND} -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/spdx/test_spdx.cmake)
add_test(NAME dvv_build.third_party_gate
         COMMAND ${CMAKE_COMMAND} -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/spdx/test_third_party_gate.cmake)
add_test(NAME dvv_build.third_party_versions
         COMMAND ${CMAKE_COMMAND} -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/deps/test_versions.cmake)
add_test(NAME dvv_build.superbuild_scripts
         COMMAND ${CMAKE_COMMAND} -DWORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/superbuild-scripts-test
                 -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/deps/test_superbuild_scripts.cmake)
add_test(NAME dvv_build.check_vulkan_device
         COMMAND ${CMAKE_COMMAND} -DWORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/check-vulkan-device-test
                 -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/ci/test_check_vulkan_device.cmake)
add_test(NAME dvv_build.privacy_lint
         COMMAND ${CMAKE_COMMAND} -DWORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/privacy-lint-test
                 -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/privacy/test_privacy_lint.cmake)
add_test(NAME dvv_build.fetch_deps
         COMMAND ${CMAKE_COMMAND} -DWORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/fetch-deps-test
                 -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/tools/test_fetch_deps.cmake)
add_test(NAME dvv_build.check_pins
         COMMAND ${CMAKE_COMMAND} -DWORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/check-pins-test
                 -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/tools/test_check_pins.cmake)
# Cycle labels: `sanity` marks the fast inner-loop subset (ctest --preset vs2026-sanity); `package`
# marks install and consumer tests, which only the full cycle runs (vs2026-small excludes them).
set_property(TEST dvv_build.presets_consistency dvv_build.spdx dvv_build.third_party_gate
             dvv_build.third_party_versions APPEND PROPERTY LABELS sanity)

# wxWidgets consumer (M1b design §8.3): Debug and Release consumers on MSVC and a Debug consumer on
# Clang (against the Release-only wx) build, link and run against the prefix. Not under sanitizers.
find_file(DVV_WX_CONFIG wxWidgetsConfig.cmake PATHS ${CMAKE_PREFIX_PATH}
          PATH_SUFFIXES lib/cmake/wxWidgets-3.3 NO_DEFAULT_PATH NO_CACHE)
if(DVV_WX_CONFIG AND NOT DVV_SANITIZE)
    if(MSVC)
        set(wx_consumer_configs "Debug,Release")
    else()
        set(wx_consumer_configs "Debug")
    endif()
    string(REPLACE ";" "," wx_prefix_path "${CMAKE_PREFIX_PATH}")
    add_test(NAME dvv_build.wx_consumer CONFIGURATIONS Debug
             COMMAND ${CMAKE_COMMAND}
                     -DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/tests/deps/wx-consumer
                     -DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}/wx-consumer
                     -DGENERATOR=${CMAKE_GENERATOR}
                     -DPLATFORM=${CMAKE_GENERATOR_PLATFORM}
                     -DCXX_COMPILER=${CMAKE_CXX_COMPILER}
                     -DPREFIX_PATH=${wx_prefix_path}
                     -DDVV_CMAKE_DIR=${DVV_CMAKE_DIR}
                     -DCONFIGS=${wx_consumer_configs}
                     -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/deps/run-wx-consumer.cmake)
    set_tests_properties(dvv_build.wx_consumer PROPERTIES
        TIMEOUT 900
        LABELS package)
endif()

# custom_ffmpeg in the prefix (M4 design §9): the dvv_ffmpeg_sdk package finds FFmpeg's headers,
# libraries and programs, the ffmpeg program is an LGPL build, and FFmpeg's headers compile as C++.
# A consumer test, so label `package`. Not under sanitizers.
if(NOT DVV_SANITIZE)
    string(REPLACE ";" "," ffmpeg_prefix_path "${CMAKE_PREFIX_PATH}")
    add_test(NAME dvv_build.ffmpeg_sdk CONFIGURATIONS Debug
             COMMAND ${CMAKE_COMMAND}
                     -DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/tests/deps/ffmpeg-sdk-consumer
                     -DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}/ffmpeg-sdk-consumer
                     -DGENERATOR=${CMAKE_GENERATOR}
                     -DPLATFORM=${CMAKE_GENERATOR_PLATFORM}
                     -DCXX_COMPILER=${CMAKE_CXX_COMPILER}
                     -DPREFIX_PATH=${ffmpeg_prefix_path}
                     -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/deps/run-ffmpeg-sdk-consumer.cmake)
    set_tests_properties(dvv_build.ffmpeg_sdk PROPERTIES
        TIMEOUT 600
        LABELS package)
endif()
