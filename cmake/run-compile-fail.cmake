# Builds one compile-fail target and requires it to fail for the expected reason (spec §9.4).
# Part of dvv-build and installed with dvv_base, so every dvv repository runs it as
#   ${CMAKE_COMMAND} -DBUILD_DIR=<top-level build tree> -DCONFIG=<config> -DTARGET=<target>
#                    -DPATTERN=<regex> -P ${DVV_CMAKE_DIR}/run-compile-fail.cmake
# PATTERN is a regular expression the compiler diagnostics must match. White space in the output is
# folded to single spaces before the match, because MSBuild wraps long diagnostics (static_assert
# messages) between words.
cmake_minimum_required(VERSION 4.2)

foreach(variable IN ITEMS BUILD_DIR CONFIG TARGET PATTERN)
    # An empty PATTERN would match any output, so every argument must have a value.
    if(NOT DEFINED ${variable} OR "${${variable}}" STREQUAL "")
        message(FATAL_ERROR "run-compile-fail.cmake needs -D${variable}=<non-empty value>")
    endif()
endforeach()

execute_process(
    COMMAND "${CMAKE_COMMAND}" --build "${BUILD_DIR}" --target "${TARGET}" --config "${CONFIG}"
    RESULT_VARIABLE status
    OUTPUT_VARIABLE output
    ERROR_VARIABLE output)

if(status EQUAL 0)
    message(FATAL_ERROR "${TARGET} built successfully, but it must fail to compile")
endif()
string(REGEX REPLACE "[ \t\r\n]+" " " folded "${output}")
if(NOT folded MATCHES "${PATTERN}")
    message(FATAL_ERROR
            "${TARGET} failed (${status}) but not for the expected reason: the output does not "
            "match '${PATTERN}'.\n${output}")
endif()
