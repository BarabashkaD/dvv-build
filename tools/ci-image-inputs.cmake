# Prints the hash of the inputs of the prebuilt Linux CI image (spec section 5.1): the tracked files
# of ci-image/, tools/requirements.txt, this script and the publish workflow
# .github/workflows/ci-image.yml (the workflow decides how the image is built, so an edit to it
# alone must not reuse a tag). tools/check-ci-image.cmake is not an input: it only checks the image.
# CI uses the hash as the tag of the image and as the key that decides whether the image is rebuilt.
#   cmake [-DDVV_BUILD=<dvv-build root>] -P tools/ci-image-inputs.cmake
# DVV_BUILD defaults to the parent of this script's folder, and must be the top of a git work tree.
# Output: one line "hash=<64 hex digits>" on standard output, as tools/separate-prefix-hash.cmake.
# Definition: the inputs are the output of
#   git ls-files -- ci-image tools/requirements.txt tools/ci-image-inputs.cmake \
#                   .github/workflows/ci-image.yml
# sorted as strings (an empty ci-image/ is valid; the three named files must be tracked). The hashed
# text is "<path>\n<SHA-256 of the file>\n" for each input. Untracked files do not count.
cmake_minimum_required(VERSION 4.2)
if(NOT DVV_BUILD)
    set(DVV_BUILD "${CMAKE_CURRENT_LIST_DIR}/..")
endif()
cmake_path(NORMAL_PATH DVV_BUILD OUTPUT_VARIABLE root)
find_program(GIT git REQUIRED)

execute_process(COMMAND "${GIT}" -C "${root}" rev-parse --show-toplevel
                RESULT_VARIABLE status OUTPUT_VARIABLE top ERROR_QUIET
                OUTPUT_STRIP_TRAILING_WHITESPACE ENCODING UTF-8)
if(NOT status EQUAL 0)
    message(FATAL_ERROR "ci-image-inputs: ${root} is not a git work tree")
endif()
file(REAL_PATH "${root}" real_root)
file(REAL_PATH "${top}" real_top)
if(NOT real_root STREQUAL real_top)
    message(FATAL_ERROR "ci-image-inputs: ${root} is not the top of a git work tree")
endif()

set(required tools/requirements.txt tools/ci-image-inputs.cmake .github/workflows/ci-image.yml)
execute_process(COMMAND "${GIT}" -C "${root}" ls-files -- ci-image ${required}
                RESULT_VARIABLE status OUTPUT_VARIABLE listing ERROR_VARIABLE err
                OUTPUT_STRIP_TRAILING_WHITESPACE ENCODING UTF-8)
if(NOT status EQUAL 0)
    message(FATAL_ERROR "ci-image-inputs: git ls-files failed: ${err}")
endif()
string(REPLACE "\n" ";" inputs "${listing}")
list(SORT inputs COMPARE STRING)

set(text "")
foreach(path IN LISTS inputs)
    if(path MATCHES "^\"")
        message(FATAL_ERROR "ci-image-inputs: git quotes the path ${path}; rename it")
    endif()
    if(NOT EXISTS "${root}/${path}")
        message(FATAL_ERROR "ci-image-inputs: ${path} is tracked but missing")
    endif()
    file(SHA256 "${root}/${path}" file_hash)
    string(APPEND text "${path}\n${file_hash}\n")
endforeach()
foreach(path IN LISTS required)
    if(NOT path IN_LIST inputs)
        message(FATAL_ERROR "ci-image-inputs: ${path} is not tracked")
    endif()
endforeach()

string(SHA256 hash "${text}")
execute_process(COMMAND "${CMAKE_COMMAND}" -E echo "hash=${hash}")
