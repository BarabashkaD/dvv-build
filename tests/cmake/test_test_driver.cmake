# Tests the macOS test driver of cmake/DvvCompilerOptions.cmake: every test runs on one Vulkan
# driver, the prefix's KosmicKrisp unless DVV_TEST_VK_DRIVER_FILES names another manifest (the CI
# jobs pass lavapipe's). Apple hosts only (DvvCompilerOptions accepts only AppleClang there).
# Run: cmake -DWORK_DIR=<empty scratch dir> [-DGENERATOR=<generator>] -P tests/cmake/test_test_driver.cmake
cmake_minimum_required(VERSION 4.2)
if(NOT DEFINED WORK_DIR)
    message(FATAL_ERROR "pass -DWORK_DIR=<scratch directory>")
endif()
if(NOT CMAKE_HOST_APPLE)
    message(STATUS "test-driver tests: skipped (macOS only)")
    return()
endif()
if(NOT DEFINED GENERATOR)
    set(GENERATOR Ninja)
endif()
file(REMOVE_RECURSE "${WORK_DIR}")
cmake_path(SET options NORMALIZE "${CMAKE_CURRENT_LIST_DIR}/../../cmake/DvvCompilerOptions.cmake")
set(prefix "${WORK_DIR}/prefix")
set(kosmickrisp "${prefix}/share/vulkan/icd.d/libkosmickrisp_icd.json")
file(WRITE "${kosmickrisp}" "{}\n")
set(lavapipe "${WORK_DIR}/homebrew/share/vulkan/icd.d/lvp_icd.aarch64.json")
file(WRITE "${lavapipe}" "{}\n")
file(WRITE "${WORK_DIR}/project/CMakeLists.txt" "cmake_minimum_required(VERSION 4.2)
project(test_driver CXX)
include(\"${options}\")
message(STATUS \"DVV_TEST_ENVIRONMENT=[\${DVV_TEST_ENVIRONMENT}]\")
")

# configure(<name> <0|1 expected failure> <expected output regex> [-D...]) configures the project in
# its own build tree.
function(configure name expect_failure expected)
    execute_process(COMMAND "${CMAKE_COMMAND}" -S "${WORK_DIR}/project" -B "${WORK_DIR}/build-${name}"
                            -G "${GENERATOR}" -DCMAKE_CXX_COMPILER=/usr/bin/clang++
                            "-DCMAKE_PREFIX_PATH=${prefix}" ${ARGN}
                    RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
    string(REGEX REPLACE "[ \t\r\n]+" " " output "${out}${err}")
    if(expect_failure AND status EQUAL 0)
        message(FATAL_ERROR "FAIL: ${name}: configure succeeded:\n${out}${err}")
    elseif(NOT expect_failure AND NOT status EQUAL 0)
        message(FATAL_ERROR "FAIL: ${name}: configure failed:\n${out}${err}")
    elseif(NOT output MATCHES "${expected}")
        message(FATAL_ERROR "FAIL: ${name}: output lacks '${expected}':\n${out}${err}")
    endif()
    set(output "${output}" PARENT_SCOPE)
endfunction()

configure(default 0 "DVV_TEST_ENVIRONMENT=\\[VK_DRIVER_FILES=set:${kosmickrisp}\\]")
configure(lavapipe 0 "DVV_TEST_ENVIRONMENT=\\[VK_DRIVER_FILES=set:${lavapipe}\\]"
          "-DDVV_TEST_VK_DRIVER_FILES=${lavapipe}")
if(output MATCHES "libkosmickrisp_icd")
    message(FATAL_ERROR "FAIL: lavapipe: KosmicKrisp's manifest is still in the test environment")
endif()
configure(missing 1 "DVV_TEST_VK_DRIVER_FILES names .*${WORK_DIR}/missing\\.json.*which does not exist"
          "-DDVV_TEST_VK_DRIVER_FILES=${WORK_DIR}/missing.json")
message(STATUS "test-driver tests passed")
