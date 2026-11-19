# Tests for tools/ci-image-inputs.cmake on a throw-away git repository.
# Run: cmake -DWORK_DIR=<scratch dir> -P tests/ci/test_ci_image_inputs.cmake
cmake_minimum_required(VERSION 4.2)
if(NOT DEFINED WORK_DIR)
    message(FATAL_ERROR "pass -DWORK_DIR=<scratch directory>")
endif()
find_program(GIT git REQUIRED)
set(real_root "${CMAKE_CURRENT_LIST_DIR}/../..")
cmake_path(NORMAL_PATH real_root)
file(REMOVE_RECURSE "${WORK_DIR}")
file(MAKE_DIRECTORY "${WORK_DIR}")
file(REAL_PATH "${WORK_DIR}" WORK_DIR)
# A plain folder under WORK_DIR must not find a repository above the scratch directory.
set(ENV{GIT_CEILING_DIRECTORIES} "${WORK_DIR}")
set(fx "${WORK_DIR}/fx")
set(script "${fx}/tools/ci-image-inputs.cmake")
# CMake regular expressions have no {n}.
string(REPEAT "[0-9a-f]" 64 hex64)
set(hash_line "^hash=${hex64}\n$")
set(inputs ci-image/Dockerfile ci-image/packages.txt ci-image/build.sh
           tools/requirements.txt tools/ci-image-inputs.cmake .github/workflows/ci-image.yml)

function(git)
    execute_process(COMMAND "${GIT}" -C "${fx}" ${ARGN} RESULT_VARIABLE status
                    OUTPUT_VARIABLE out ERROR_VARIABLE err)
    if(NOT status EQUAL 0)
        message(FATAL_ERROR "FAIL: git ${ARGN}: ${out}${err}")
    endif()
endfunction()

# restore(): the fixture in its committed state.
function(restore)
    file(REMOVE_RECURSE "${fx}")
    file(MAKE_DIRECTORY "${fx}/ci-image" "${fx}/tools" "${fx}/.github/workflows")
    file(WRITE "${fx}/ci-image/Dockerfile" "FROM ubuntu\n")
    file(WRITE "${fx}/ci-image/packages.txt" "cmake\nninja-build\n")
    file(WRITE "${fx}/ci-image/build.sh" "#!/bin/sh\necho build\n")
    file(WRITE "${fx}/tools/requirements.txt" "pip==1\n")
    file(COPY_FILE "${real_root}/tools/ci-image-inputs.cmake" "${script}")
    file(WRITE "${fx}/.github/workflows/ci-image.yml" "name: ci-image\n")
    file(WRITE "${fx}/tools/check-ci-image.cmake" "# check\n")
    file(WRITE "${fx}/README.md" "readme\n")
    git(init -q -b main)
    git(config user.name "dvv test")
    git(config user.email "test@users.noreply.github.com")
    git(add .)
endfunction()

# run([-D...]): sets out (stdout), err, status for the script of the fixture.
macro(run)
    execute_process(COMMAND "${CMAKE_COMMAND}" ${ARGN} -P "${script}" RESULT_VARIABLE status
                    OUTPUT_VARIABLE out ERROR_VARIABLE err)
endmacro()

function(hash_of result)
    run()
    if(NOT status EQUAL 0 OR NOT out MATCHES "${hash_line}")
        message(FATAL_ERROR "FAIL: no hash line (${status}):\n${out}${err}")
    endif()
    set(${result} "${out}" PARENT_SCOPE)
endfunction()

function(expect_failure text)
    run(${ARGN})
    string(REGEX REPLACE "[ \t\r\n]+" " " output "${out}${err}") # message() wraps
    if(status EQUAL 0 OR NOT output MATCHES "${text}")
        message(FATAL_ERROR "FAIL: expected failure '${text}' (${status}):\n${out}${err}")
    endif()
endfunction()

# 1. The output is the hash of the definition.
restore()
hash_of(first)
list(SORT inputs COMPARE STRING)
set(text "")
foreach(path IN LISTS inputs)
    file(SHA256 "${fx}/${path}" file_hash)
    string(APPEND text "${path}\n${file_hash}\n")
endforeach()
string(SHA256 expected "${text}")
if(NOT first STREQUAL "hash=${expected}\n")
    message(FATAL_ERROR "FAIL: ${first} is not hash=${expected}")
endif()

# 2. Stable.
hash_of(second)
if(NOT first STREQUAL second)
    message(FATAL_ERROR "FAIL: two runs differ: ${first} ${second}")
endif()

# 3. One changed byte in each input.
foreach(path IN LISTS inputs)
    restore()
    file(APPEND "${fx}/${path}" "\n#x\n") # stays a valid script
    hash_of(changed)
    if(changed STREQUAL first)
        message(FATAL_ERROR "FAIL: a change in ${path} keeps the hash")
    endif()
endforeach()

# 4. A new tracked file.
restore()
file(WRITE "${fx}/ci-image/extra.txt" "extra\n")
git(add ci-image/extra.txt)
hash_of(changed)
if(changed STREQUAL first)
    message(FATAL_ERROR "FAIL: a new tracked file keeps the hash")
endif()

# 5. An untracked file.
restore()
file(WRITE "${fx}/ci-image/.DS_Store" "junk")
hash_of(changed)
if(NOT changed STREQUAL first)
    message(FATAL_ERROR "FAIL: an untracked file changes the hash")
endif()

# 6. A file that is not an input.
restore()
file(APPEND "${fx}/README.md" "more\n")
hash_of(changed)
if(NOT changed STREQUAL first)
    message(FATAL_ERROR "FAIL: README.md changes the hash")
endif()

# 6b. tools/check-ci-image.cmake is not an input.
restore()
file(APPEND "${fx}/tools/check-ci-image.cmake" "# more\n")
hash_of(changed)
if(NOT changed STREQUAL first)
    message(FATAL_ERROR "FAIL: tools/check-ci-image.cmake changes the hash")
endif()

# 7. A rename.
restore()
git(mv ci-image/build.sh ci-image/build2.sh)
hash_of(changed)
if(changed STREQUAL first)
    message(FATAL_ERROR "FAIL: a rename keeps the hash")
endif()

# 8. Tracked but missing on disk.
restore()
file(REMOVE "${fx}/ci-image/build.sh")
expect_failure("ci-image/build.sh is tracked but missing")

# 9. Not a git work tree.
restore()
file(MAKE_DIRECTORY "${WORK_DIR}/plain")
expect_failure("not a git work tree" "-DDVV_BUILD=${WORK_DIR}/plain")

# 10. A folder inside a work tree.
expect_failure("not the top of a git work tree" "-DDVV_BUILD=${fx}/ci-image")

# 11. A required input that is not tracked.
foreach(path tools/requirements.txt .github/workflows/ci-image.yml)
    restore()
    git(rm -q --cached ${path})
    expect_failure("${path} is not tracked")
endforeach()

# 12. The real dvv-build.
unset(ENV{GIT_CEILING_DIRECTORIES})
execute_process(COMMAND "${CMAKE_COMMAND}" "-DDVV_BUILD=${real_root}"
                        -P "${real_root}/tools/ci-image-inputs.cmake"
                RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT status EQUAL 0 OR NOT out MATCHES "${hash_line}")
    message(FATAL_ERROR "FAIL: the real dvv-build gives no hash line (${status}):\n${out}${err}")
endif()

message(STATUS "ci-image-inputs tests passed")
