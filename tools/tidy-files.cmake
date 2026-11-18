# tidy-files.cmake: the list of files clang-tidy checks, taken from the compile database. Part of
# dvv-build.
# Usage: cmake -DDB=<compile_commands.json> -DREPO=<repository folder> -DOUT=<file> -P <dvv-build>/tools/tidy-files.cmake
# Writes to OUT, sorted and de-duplicated, one repo-relative path per line (each ending in a
# newline; an empty file for no candidates), the paths that are in the database, tracked, and match
# src/**/*.cpp, tests/*.cpp or tools/*.cpp (so tests/compile_fail, tests/package and tools/<sub>/
# stay out). REPO must be the top of a git work tree.
# The database is read the way CMake writes it, one member per line: a one-line database fails with
# "unexpected compile database layout" (parsing the whole document once per entry would be slow).
cmake_minimum_required(VERSION 4.2)
find_program(GIT_EXECUTABLE git REQUIRED)

foreach(arg DB REPO OUT)
    if(NOT DEFINED ${arg} OR "${${arg}}" STREQUAL "")
        message(FATAL_ERROR "pass -DDB=<compile_commands.json> -DREPO=<repository folder> -DOUT=<file>")
    endif()
endforeach()

# REPO is the top of a git work tree (a plain folder inside another work tree, or a subfolder of a
# repository, would list the wrong files or none).
execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${REPO}" rev-parse --show-toplevel
                RESULT_VARIABLE rc OUTPUT_VARIABLE top ERROR_QUIET
                OUTPUT_STRIP_TRAILING_WHITESPACE ENCODING UTF-8)
set(repo "")
if(rc EQUAL 0 AND NOT top STREQUAL "")
    file(REAL_PATH "${REPO}" repo)
    file(REAL_PATH "${top}" top)
endif()
if(NOT rc EQUAL 0 OR repo STREQUAL "" OR NOT repo STREQUAL top)
    message(FATAL_ERROR "${REPO} is not the top of a git work tree")
endif()
if(NOT EXISTS "${DB}")
    message(FATAL_ERROR "compile database not found: ${DB}")
endif()

# Candidates: the tracked files that match today's globs.
execute_process(COMMAND "${GIT_EXECUTABLE}" -c core.quotePath=false -C "${repo}" ls-files
                        ":(glob)src/**/*.cpp" ":(glob)tests/*.cpp" ":(glob)tools/*.cpp"
                RESULT_VARIABLE rc OUTPUT_VARIABLE listed ERROR_VARIABLE err ENCODING UTF-8)
if(NOT rc EQUAL 0)
    message(FATAL_ERROR "git ls-files failed in ${repo}:\n${err}")
endif()
if(listed MATCHES ";")
    message(FATAL_ERROR "tidy-files: a tracked path contains ';', which CMake lists cannot hold; rename it")
endif()

# Text is split into CMake lists line by line. A list element cannot hold an unbalanced [ or ] (the
# elements after it would merge into it), so paths are kept with control characters in their place
# and restored for output.
string(ASCII 3 PH_LBR)
string(ASCII 4 PH_RBR)
# encode_lines(<text> <out-var>): the lines of <text> as a list; \r before \n dropped. A final
# newline adds no line.
function(encode_lines text out)
    string(REPLACE "\r\n" "\n" text "${text}")
    string(REPLACE "[" "${PH_LBR}" text "${text}")
    string(REPLACE "]" "${PH_RBR}" text "${text}")
    string(REGEX REPLACE "\n$" "" text "${text}")
    string(REPLACE "\n" ";" text "${text}")
    set(${out} "${text}" PARENT_SCOPE)
endfunction()
# decode(<var>): restores the replaced characters in the variable <var>.
function(decode var)
    string(REPLACE "${PH_LBR}" "[" text "${${var}}")
    string(REPLACE "${PH_RBR}" "]" text "${text}")
    set(${var} "${text}" PARENT_SCOPE)
endfunction()

encode_lines("${listed}" listed)
set(candidates "")
foreach(path IN LISTS listed)
    if(path MATCHES "^\"")
        decode(path)
        message(FATAL_ERROR "tidy-files: git quoted the path ${path}; rename it")
    endif()
    if(NOT path STREQUAL "")
        list(APPEND candidates "${path}")
    endif()
endforeach()

# The database: one parse for the entry count, then the "directory" and "file" member lines.
file(READ "${DB}" text)
if(text MATCHES "\n[ \t]*\"(file|directory)\"[ \t]*:[^\n]*;")
    message(FATAL_ERROR "tidy-files: a path in ${DB} contains ';', which CMake lists cannot hold; rename it")
endif()
string(JSON n LENGTH "${text}")
# The member lines, encoded; a ';' elsewhere (in a "command") stays out of them.
string(REPLACE "\r\n" "\n" text "\n${text}")
string(REPLACE "[" "${PH_LBR}" text "${text}")
string(REPLACE "]" "${PH_RBR}" text "${text}")
# member_values(<member> <out-var>): the values of the member's lines, in file order, encoded.
function(member_values member out)
    string(REGEX MATCHALL "\n[ \t]*\"${member}\"[ \t]*:[^\n]*" lines "${text}")
    set(values "")
    foreach(line IN LISTS lines)
        string(REGEX REPLACE ",[ \t]*$" "" line "${line}")
        decode(line)
        string(JSON value GET "{${line}}" "${member}")
        string(REPLACE "[" "${PH_LBR}" value "${value}")
        string(REPLACE "]" "${PH_RBR}" value "${value}")
        list(APPEND values "${value}")
    endforeach()
    set(${out} "${values}" PARENT_SCOPE)
endfunction()
member_values(file files)
member_values(directory directories)
unset(text)
list(LENGTH files n_files)
list(LENGTH directories n_directories)
if(NOT n_files EQUAL n OR NOT n_directories EQUAL n)
    message(FATAL_ERROR "unexpected compile database layout")
endif()

set(result "")
string(LENGTH "${repo}/" prefix_len)
math(EXPR last "${n} - 1")
if(n GREATER 0)
    foreach(i RANGE ${last})
        list(GET files ${i} file)
        list(GET directories ${i} directory)
        decode(file)
        decode(directory)
        cmake_path(ABSOLUTE_PATH file BASE_DIRECTORY "${directory}" NORMALIZE OUTPUT_VARIABLE path)
        if(EXISTS "${path}")
            file(REAL_PATH "${path}" path)
        endif()
        string(SUBSTRING "${path}" 0 ${prefix_len} prefix)
        if(NOT prefix STREQUAL "${repo}/")
            continue()
        endif()
        string(SUBSTRING "${path}" ${prefix_len} -1 rel)
        string(REPLACE "[" "${PH_LBR}" rel "${rel}")
        string(REPLACE "]" "${PH_RBR}" rel "${rel}")
        list(FIND candidates "${rel}" found)
        if(NOT found EQUAL -1)
            list(APPEND result "${rel}")
        endif()
    endforeach()
endif()
list(REMOVE_DUPLICATES result)
list(SORT result)

list(LENGTH candidates n_candidates)
list(LENGTH result n_result)
if(n_candidates GREATER 0 AND n_result EQUAL 0)
    message(FATAL_ERROR "the compile database paths matched none of the tracked sources")
endif()
set(content "")
foreach(path IN LISTS result)
    string(APPEND content "${path}\n")
endforeach()
decode(content)
file(WRITE "${OUT}" "${content}")
message(STATUS "tidy-files: ${n_result} files")
