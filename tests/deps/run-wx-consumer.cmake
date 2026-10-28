# Builds tests/deps/wx-consumer against the third-party prefix in each configuration and runs it
# (M1b design §8.3, R1). A Debug link that reports LNK4099 (missing wx PDB) fails.
# Called by dvv_build.wx_consumer with -DSOURCE_DIR, -DBUILD_DIR, -DGENERATOR, -DPLATFORM,
# -DCXX_COMPILER, -DPREFIX_PATH (comma-separated), -DDVV_CMAKE_DIR and -DCONFIGS (comma-separated).
cmake_minimum_required(VERSION 4.2)
foreach(variable IN ITEMS SOURCE_DIR BUILD_DIR GENERATOR CXX_COMPILER PREFIX_PATH DVV_CMAKE_DIR
                          CONFIGS)
    if("${${variable}}" STREQUAL "")
        message(FATAL_ERROR "pass -D${variable}")
    endif()
endforeach()
string(REPLACE "," ";" prefix_path "${PREFIX_PATH}")
string(REPLACE "," ";" configs "${CONFIGS}")

file(REMOVE_RECURSE "${BUILD_DIR}")
file(MAKE_DIRECTORY "${BUILD_DIR}")
# A list value cannot pass through a command line intact; an initial-cache file keeps it whole. The
# bracket argument takes Windows backslashes literally.
set(initial_cache "${BUILD_DIR}/initial-cache.cmake")
file(WRITE "${initial_cache}" "set(CMAKE_PREFIX_PATH [==[${prefix_path}]==] CACHE STRING \"\")\n")
set(configure "${CMAKE_COMMAND}" -C "${initial_cache}" -S "${SOURCE_DIR}" -B "${BUILD_DIR}/tree"
    -G "${GENERATOR}" "-DCMAKE_CXX_COMPILER=${CXX_COMPILER}" "-DDVV_CMAKE_DIR=${DVV_CMAKE_DIR}")
if(PLATFORM)
    list(APPEND configure -A "${PLATFORM}")
endif()
execute_process(COMMAND ${configure} RESULT_VARIABLE status)
if(NOT status EQUAL 0)
    message(FATAL_ERROR "configuring the wx consumer failed (${status})")
endif()

foreach(config IN LISTS configs)
    execute_process(COMMAND "${CMAKE_COMMAND}" --build "${BUILD_DIR}/tree" --config ${config}
                    RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
    message("${out}${err}")
    if(NOT status EQUAL 0)
        message(FATAL_ERROR "building the wx consumer (${config}) failed (${status})")
    endif()
    if("${out}${err}" MATCHES "LNK4099")
        message(FATAL_ERROR "the ${config} link reports LNK4099: wx debug information is missing")
    endif()
    file(GLOB executable "${BUILD_DIR}/tree/${config}/wx_consumer"
                         "${BUILD_DIR}/tree/${config}/wx_consumer.exe")
    if(NOT executable)
        message(FATAL_ERROR "wx_consumer (${config}) not found")
    endif()
    execute_process(COMMAND ${executable} RESULT_VARIABLE status OUTPUT_VARIABLE out)
    if(NOT status EQUAL 0 OR NOT out MATCHES "wx consumer ok")
        message(FATAL_ERROR "wx_consumer (${config}) failed (${status}): ${out}")
    endif()
    message(STATUS "wx consumer ${config}: ok")
endforeach()
