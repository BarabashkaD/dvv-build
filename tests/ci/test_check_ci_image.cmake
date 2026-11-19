# Tests for tools/check-ci-image.cmake on saved facts and a throw-away dvv-build.
# Run: cmake -DWORK_DIR=<scratch dir> -P tests/ci/test_check_ci_image.cmake
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
# The fixture must not find a repository above the scratch directory.
set(ENV{GIT_CEILING_DIRECTORIES} "${WORK_DIR}")
set(fx "${WORK_DIR}/dvv-build")
set(facts "${WORK_DIR}/facts")
set(script "${fx}/tools/check-ci-image.cmake")
# CMake regular expressions have no {n}.
string(REPEAT "a" 64 a64)
set(reference "dvv-build-ci@sha256:${a64}")
file(STRINGS "${real_root}/tools/requirements.txt" real_requirements REGEX "==")
foreach(line IN LISTS real_requirements)
    if(line MATCHES "^([a-z-]+)==(.+)$")
        set(pin_${CMAKE_MATCH_1} "${CMAKE_MATCH_2}")
    endif()
endforeach()

# bump(<var> <version>): the version with its last number one higher.
function(bump var version)
    if(NOT version MATCHES "^(.*\\.)([0-9]+)$")
        message(FATAL_ERROR "FAIL: cannot bump ${version}")
    endif()
    math(EXPR next "${CMAKE_MATCH_2} + 1")
    set(${var} "${CMAKE_MATCH_1}${next}" PARENT_SCOPE)
endfunction()

function(git)
    execute_process(COMMAND "${GIT}" -C "${fx}" ${ARGN} RESULT_VARIABLE status
                    OUTPUT_VARIABLE out ERROR_VARIABLE err)
    if(NOT status EQUAL 0)
        message(FATAL_ERROR "FAIL: git ${ARGN}: ${out}${err}")
    endif()
endfunction()

# The fixture: a git repository with the real inputs script and requirements, and a small package list.
file(MAKE_DIRECTORY "${fx}/ci-image" "${fx}/tools" "${fx}/.github/workflows")
file(WRITE "${fx}/.github/workflows/ci-image.yml" "name: ci-image\n")
file(WRITE "${fx}/ci-image/Dockerfile" "FROM ubuntu\n")
file(WRITE "${fx}/ci-image/packages.txt"
     "# Packages.\n\n## base\n# Why git.\ngit\nzstd\n\n## compiler\nclang-19\n")
file(COPY_FILE "${real_root}/tools/requirements.txt" "${fx}/tools/requirements.txt")
file(COPY_FILE "${real_root}/tools/ci-image-inputs.cmake" "${fx}/tools/ci-image-inputs.cmake")
file(COPY_FILE "${real_root}/tools/check-ci-image.cmake" "${script}")
git(init -q -b main)
git(config user.name "dvv test")
git(config user.email "test@users.noreply.github.com")
git(add .)
execute_process(COMMAND "${CMAKE_COMMAND}" "-DDVV_BUILD=${fx}"
                        -P "${fx}/tools/ci-image-inputs.cmake"
                OUTPUT_VARIABLE hash_out RESULT_VARIABLE status)
if(NOT status EQUAL 0 OR NOT hash_out MATCHES "^hash=([0-9a-f]+)")
    message(FATAL_ERROR "FAIL: no hash for the fixture: ${hash_out}")
endif()
set(fx_hash "${CMAKE_MATCH_1}")
string(REPEAT "e" 64 env_hash)

# facts(): the facts of a matching image, as the live commands print them.
function(facts)
    file(REMOVE_RECURSE "${facts}")
    file(MAKE_DIRECTORY "${facts}/pip-show" "${facts}/dpkg" "${facts}/image")
    set(prefix /opt/hostedtoolcache/Python/3.13.18/x64)
    file(WRITE "${facts}/uid" "1001\n")
    file(WRITE "${facts}/gid" "1001\n")
    file(WRITE "${facts}/workspace-uid" "1001\n")
    file(WRITE "${facts}/cmake.txt"
         "cmake version ${pin_cmake}\n\nCMake suite maintained and supported by Kitware.\n")
    file(WRITE "${facts}/ninja.txt" "${pin_ninja}.git.kitware.jobserver-pipe-1\n")
    file(WRITE "${facts}/clang-format.txt" "clang-format version ${pin_clang-format}\n")
    file(WRITE "${facts}/clang-tidy.txt"
         "LLVM (http://llvm.org/):\n  LLVM version ${pin_clang-tidy}\n  Optimized build.\n")
    foreach(tool cmake ninja clang-format clang-tidy)
        file(WRITE "${facts}/pip-show/${tool}.txt"
             "Name: ${tool}\nVersion: ${pin_${tool}}\nSummary: a tool\n")
    endforeach()
    file(WRITE "${facts}/python.txt" "Python 3.13.18\n")
    file(WRITE "${facts}/python-prefix.txt" "${prefix}\n")
    file(WRITE "${facts}/env.txt"
         "Python3_ROOT_DIR=${prefix}\npythonLocation=${prefix}\nPKG_CONFIG_PATH=${prefix}/lib/pkgconfig\n")
    file(WRITE "${facts}/clang-19.txt"
         "Ubuntu clang version 19.1.1 (1ubuntu1~24.04.2)\nTarget: x86_64-pc-linux-gnu\n")
    foreach(pkg git zstd clang-19)
        file(WRITE "${facts}/dpkg/${pkg}.txt" "install ok installed")
    endforeach()
    file(WRITE "${facts}/image/inputs.sha256" "${fx_hash}\n")
    file(WRITE "${facts}/image/environment.sha256" "${env_hash}\n")
    file(WRITE "${facts}/image/packages.lock" "git\t1:2.43.0\nzstd\t1.5.5\n")
    file(WRITE "${facts}/image/pip.lock" "cmake==${pin_cmake}\n")
    # The bytes fx_hash was taken from: file(WRITE) would turn \n into \r\n on Windows.
    file(COPY_FILE "${real_root}/tools/requirements.txt" "${fx}/tools/requirements.txt")
endfunction()

# run([-D...]): out, err, status of the script of the fixture with the facts; DVV_CI_IMAGE is
# unset unless ENV_REF is.
macro(run)
    if(ENV_REF)
        set(env_args "DVV_CI_IMAGE=${ENV_REF}")
    else()
        set(env_args "--unset=DVV_CI_IMAGE")
    endif()
    execute_process(COMMAND "${CMAKE_COMMAND}" -E env "${env_args}" "${CMAKE_COMMAND}"
                            "-DDVV_BUILD=${fx}" "-DFACTS_DIR=${facts}" ${ARGN} -P "${script}"
                    RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
    string(REGEX REPLACE "[ \t\r\n]+" " " output "${out}${err}") # message() wraps
    string(REGEX MATCHALL "check-ci-image:" messages "${output}")
    list(LENGTH messages message_count)
endmacro()

function(expect_pass)
    run()
    if(NOT status EQUAL 0 OR NOT out MATCHES "check-ci-image: OK" OR NOT message_count EQUAL 1)
        message(FATAL_ERROR "FAIL: expected a pass (${status}):\n${out}${err}")
    endif()
    set(out "${out}" PARENT_SCOPE)
endfunction()

# expect_failure(<regex>): exactly one message, matching.
function(expect_failure text)
    run()
    if(status EQUAL 0 OR NOT output MATCHES "${text}" OR NOT message_count EQUAL 1
       OR out MATCHES "check-ci-image: OK")
        message(FATAL_ERROR
                "FAIL: expected one failure '${text}' (${status}, ${message_count} messages):\n${out}${err}")
    endif()
endfunction()

# 1. A matching set, with a reference.
facts()
set(ENV_REF "${reference}")
run()
if(NOT status EQUAL 0 OR NOT out MATCHES "check-ci-image: OK \\(inputs [0-9a-f]+, environment e+\\)"
   OR NOT out MATCHES "user 1001:1001 \\(workspace owner 1001\\)"
   OR NOT out MATCHES "\nimage [^\n]*${reference}\n"
   OR NOT out MATCHES "::group::CI image\n" OR NOT out MATCHES "::endgroup::\n"
   OR NOT out MATCHES "zstd\t1.5.5" OR NOT out MATCHES "cmake==${pin_cmake}")
    message(FATAL_ERROR "FAIL: no pass with a reference (${status}):\n${out}${err}")
endif()
string(SUBSTRING "${fx_hash}" 0 16 fx_hash16)
if(NOT out MATCHES "inputs ${fx_hash}\nenvironment ${env_hash}\n"
   OR NOT out MATCHES "OK \\(inputs ${fx_hash16},")
    message(FATAL_ERROR "FAIL: the hashes are not reported:\n${out}")
endif()

# 2. A matching set, without a reference.
set(ENV_REF "")
expect_pass()
if(out MATCHES "\nimage ")
    message(FATAL_ERROR "FAIL: an image line without DVV_CI_IMAGE:\n${out}")
endif()

# 3. One mismatch, one message.
facts()
file(WRITE "${facts}/image/inputs.sha256" "${a64}\n")
expect_failure("image built from inputs a+, this dvv-build has ${fx_hash}")

facts()
file(WRITE "${facts}/uid" "0\n")
expect_failure("running as root \\(uid 0\\); the job must run as the runner account")

facts()
file(WRITE "${facts}/uid" "1002\n")
expect_failure("uid 1002 is not the owner \\(1001\\) of GITHUB_WORKSPACE")

foreach(tool cmake ninja clang-format clang-tidy)
    bump(off "${pin_${tool}}")
    string(REPLACE "." "\\." pin_re "${pin_${tool}}")
    facts()
    file(READ "${facts}/${tool}.txt" text)
    string(REPLACE "${pin_${tool}}" "${off}" text "${text}")
    file(WRITE "${facts}/${tool}.txt" "${text}")
    expect_failure("${tool} ${off}[^ ]* installed, tools/requirements.txt pins ${pin_re}")

    facts() # pip show decides on its own
    file(WRITE "${facts}/pip-show/${tool}.txt" "Name: ${tool}\nVersion: ${off}\n")
    expect_failure("${tool} ${off}[^ ]* installed, tools/requirements.txt pins ${pin_re}")
endforeach()

facts()
file(WRITE "${facts}/python.txt" "Python 3.12.9\n")
expect_failure("Python 3\\.12\\.9 found, 3\\.13\\.x required")

facts()
file(WRITE "${facts}/env.txt"
     "Python3_ROOT_DIR=/usr\npythonLocation=/opt/hostedtoolcache/Python/3.13.18/x64\nPKG_CONFIG_PATH=/opt/hostedtoolcache/Python/3.13.18/x64/lib/pkgconfig\n")
expect_failure("Python3_ROOT_DIR=/usr is not the interpreter's install directory /opt/hostedtoolcache/Python/3\\.13\\.18/x64")

facts()
file(WRITE "${facts}/clang-19.txt" "Ubuntu clang version 18.1.8 (1ubuntu1)\n")
expect_failure("clang-19 reports major 18, 19 required")

facts()
file(WRITE "${facts}/dpkg/zstd.txt" "deinstall ok config-files")
expect_failure("package zstd is not installed \\(deinstall ok config-files\\)")

# use_requirements(<text>): the requirements of the fixture; the image hash follows the file.
function(use_requirements text)
    file(WRITE "${fx}/tools/requirements.txt" "${text}")
    execute_process(COMMAND "${CMAKE_COMMAND}" "-DDVV_BUILD=${fx}"
                            -P "${fx}/tools/ci-image-inputs.cmake" OUTPUT_VARIABLE hash_out)
    string(STRIP "${hash_out}" hash_out)
    string(REPLACE "hash=" "" edited_hash "${hash_out}")
    file(WRITE "${facts}/image/inputs.sha256" "${edited_hash}\n")
endfunction()
set(others "clang-format==${pin_clang-format}\nclang-tidy==${pin_clang-tidy}\n")

facts()
use_requirements("cmake>=4.3.2\nninja==${pin_ninja}\n${others}")
expect_failure("tools/requirements.txt line 'cmake>=4\\.3\\.2' is not <name>==<version>")

# A tool without a pin line is a message, not a skipped check.
facts()
use_requirements("cmake==${pin_cmake}\nninja==${pin_ninja}\nclang-format==${pin_clang-format}\n")
expect_failure("tools/requirements.txt has no pin for clang-tidy")

# Empty facts: the ids must be numbers; nothing passes on empty text.
facts()
file(WRITE "${facts}/uid" "")
file(WRITE "${facts}/workspace-uid" "")
run()
if(status EQUAL 0 OR NOT message_count EQUAL 2 OR NOT output MATCHES "uid '' is not a number"
   OR NOT output MATCHES "owner '' is not a number" OR out MATCHES "check-ci-image: OK")
    message(FATAL_ERROR "FAIL: empty uid and owner (${status}, ${message_count}):\n${out}${err}")
endif()

facts()
file(WRITE "${facts}/gid" "x\n")
expect_failure("gid 'x' is not a number")


# 4. Whole-token comparison.
facts()
file(WRITE "${facts}/clang-tidy.txt" "LLVM version ${pin_clang-tidy}.1\n")
expect_failure("clang-tidy ${pin_clang-tidy}\\.1 installed")

facts()
file(WRITE "${facts}/cmake.txt" "cmake version ${pin_cmake}0\n")
expect_failure("cmake ${pin_cmake}0 installed")

facts() # pip show decides on its own
file(WRITE "${facts}/pip-show/cmake.txt" "Name: cmake\nVersion: ${pin_cmake}0\n")
expect_failure("cmake ${pin_cmake}0 installed, tools/requirements.txt pins")

facts()
file(WRITE "${facts}/ninja.txt" "${pin_ninja}.dev1\n")
expect_failure("ninja ${pin_ninja}\\.dev1 installed")

facts()
file(WRITE "${facts}/ninja.txt" "${pin_ninja}0\n")
expect_failure("ninja ${pin_ninja}0 installed")

# The wheel's real output, and a plain version, pass.
facts()
file(WRITE "${facts}/ninja.txt" "${pin_ninja}.git.kitware.jobserver-pipe-1\n")
use_requirements("cmake==${pin_cmake}\nninja==${pin_ninja}\n${others}")
expect_pass()
file(WRITE "${facts}/ninja.txt" "${pin_ninja}\n")
expect_pass()

# 5. Two mismatches, two messages.
facts()
file(WRITE "${facts}/uid" "0\n")
file(WRITE "${facts}/python.txt" "Python 3.12.9\n")
run()
if(status EQUAL 0 OR NOT message_count EQUAL 2 OR NOT output MATCHES "running as root"
   OR NOT output MATCHES "Python 3\\.12\\.9 found")
    message(FATAL_ERROR "FAIL: expected two messages (${status}, ${message_count}):\n${out}${err}")
endif()

# 6. Live mode without the image: only the "not found" message, before any fact.
unset(ENV_REF)
execute_process(COMMAND "${CMAKE_COMMAND}" "-DDVV_BUILD=${fx}" "-DIMAGE_DIR=${WORK_DIR}/no-image"
                        -P "${script}"
                RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
string(REGEX REPLACE "[ \t\r\n]+" " " output "${out}${err}")
string(REGEX MATCHALL "check-ci-image:" messages "${output}")
list(LENGTH messages message_count)
if(status EQUAL 0 OR NOT message_count EQUAL 1
   OR NOT output MATCHES "check-ci-image: [^ ]*no-image/inputs\\.sha256 not found: this job does not run in the dvv CI image")
    message(FATAL_ERROR "FAIL: live mode without the image (${status}):\n${out}${err}")
endif()

# 7. Live mode with commands that cannot run (an empty PATH): each one is reported, none is dropped,
# and an unset GITHUB_WORKSPACE has its own message. The script itself is run by full path.
facts()
file(COPY "${facts}/image/" DESTINATION "${WORK_DIR}/live-image")
file(MAKE_DIRECTORY "${WORK_DIR}/empty-path" "${WORK_DIR}/workspace")
foreach(workspace "" "${WORK_DIR}/workspace")
    if(workspace STREQUAL "")
        set(workspace_arg "--unset=GITHUB_WORKSPACE")
    else()
        set(workspace_arg "GITHUB_WORKSPACE=${workspace}")
    endif()
    execute_process(COMMAND "${CMAKE_COMMAND}" -E env "${workspace_arg}" "PATH=${WORK_DIR}/empty-path"
                            --unset=DVV_CI_IMAGE "${CMAKE_COMMAND}" "-DDVV_BUILD=${fx}"
                            "-DIMAGE_DIR=${WORK_DIR}/live-image" -P "${script}"
                    RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
    string(REGEX REPLACE "[ \t\r\n]+" " " output "${out}${err}")
    if(status EQUAL 0 OR out MATCHES "check-ci-image: OK"
       OR NOT output MATCHES "could not run 'id -u'" OR NOT output MATCHES "could not run 'id -g'"
       OR NOT output MATCHES "could not run 'cmake --version'"
       OR NOT output MATCHES "could not run 'clang-19 --version'")
        message(FATAL_ERROR "FAIL: live mode, commands that cannot run (${status}):\n${out}${err}")
    endif()
    if(workspace STREQUAL "")
        if(NOT output MATCHES "GITHUB_WORKSPACE is not set")
            message(FATAL_ERROR "FAIL: no message for an unset GITHUB_WORKSPACE:\n${out}${err}")
        endif()
    elseif(NOT output MATCHES "could not run 'stat -c %u ")
        message(FATAL_ERROR "FAIL: no message for the failed stat:\n${out}${err}")
    endif()
endforeach()

message(STATUS "check-ci-image tests passed")
