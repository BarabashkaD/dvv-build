# Tests for tools/tidy-files.cmake with a fixture git repository in WORK_DIR (no network).
# Run: cmake -DWORK_DIR=<scratch dir> -P tests/tools/test_tidy_files.cmake
cmake_minimum_required(VERSION 4.2)
if(NOT DEFINED WORK_DIR)
    message(FATAL_ERROR "pass -DWORK_DIR=<scratch directory>")
endif()
# The fixture databases embed WORK_DIR in JSON strings: CI passes a Windows path with backslashes,
# which JSON would read as escapes.
file(TO_CMAKE_PATH "${WORK_DIR}" WORK_DIR)
find_program(GIT_EXECUTABLE git REQUIRED)
set(script "${CMAKE_CURRENT_LIST_DIR}/../../tools/tidy-files.cmake")
set(failures 0)
file(REMOVE_RECURSE "${WORK_DIR}")
file(MAKE_DIRECTORY "${WORK_DIR}")
# The relative database entry resolves through this folder; on POSIX a path through a missing
# folder neither EXISTS nor REAL_PATHs.
file(MAKE_DIRECTORY "${WORK_DIR}/build")

function(run_git)
    execute_process(COMMAND "${GIT_EXECUTABLE}" ${ARGN} RESULT_VARIABLE rc OUTPUT_VARIABLE out
                    ERROR_VARIABLE err OUTPUT_STRIP_TRAILING_WHITESPACE ENCODING UTF-8)
    if(NOT rc EQUAL 0)
        message(FATAL_ERROR "git ${ARGN} failed:\n${out}${err}")
    endif()
endfunction()

# Fixture repository.
set(repo "${WORK_DIR}/repo")
run_git(init -q -b main "${repo}")
run_git(-C "${repo}" config user.name test-user)
run_git(-C "${repo}" config user.email test@users.noreply.github.com)
run_git(-C "${repo}" config commit.gpgsign false)
run_git(-C "${repo}" config core.autocrlf false)
foreach(rel src/a.cpp src/sub/b.cpp src/ü.cpp tests/t.cpp tests/compile_fail/x.cpp tools/tool.cpp
            tools/sub/y.cpp src/c_win32.cpp)
    file(WRITE "${repo}/${rel}" "int f();\n")
    run_git(-C "${repo}" add -- "${rel}")
endforeach()
# CMake lists nest on [ and ]: an unbalanced bracket in a path must not merge the paths after it.
foreach(rel "src/x[1.cpp" "src/y]1.cpp")
    file(WRITE "${repo}/${rel}" "int f();\n")
    run_git(-C "${repo}" add -- ":(literal)${rel}")
endforeach()
file(WRITE "${repo}/build/gen/g.cpp" "int g();\n")    # untracked
file(WRITE "${repo}/src/gen.cpp" "int g();\n")        # untracked, matches the source globs
file(WRITE "${WORK_DIR}/dep/d.cpp" "int d();\n")      # outside the repository

# entries(<out-var> <file>...): a database in CMake's layout, one member per line.
function(entries out)
    set(text "[\n")
    set(first TRUE)
    foreach(file IN LISTS ARGN)
        if(NOT first)
            string(APPEND text ",\n")
        endif()
        set(first FALSE)
        string(APPEND text "{\n  \"directory\": \"${WORK_DIR}/build\",\n  \"command\": \"c++ -c ${file}\",\n  \"file\": \"${file}\",\n  \"output\": \"x.o\"\n}")
    endforeach()
    string(APPEND text "\n]\n")
    set(${out} "${text}" PARENT_SCOPE)
endfunction()

# A list argument cannot carry an unbalanced [ or ]: LBR and RBR stand in for them.
entries(db_text "${repo}/src/a.cpp" "${repo}/src/a.cpp" "${repo}/src/xLBR1.cpp" "${repo}/src/gen.cpp"
        "../repo/src/sub/b.cpp" "${repo}/src/yRBR1.cpp" "${repo}/src/ü.cpp"
        "${repo}/tests/t.cpp" "${repo}/tests/compile_fail/x.cpp" "${repo}/tools/tool.cpp"
        "${repo}/tools/sub/y.cpp" "${repo}/build/gen/g.cpp" "${WORK_DIR}/dep/d.cpp")
string(REPLACE "LBR" "[" db_text "${db_text}")
string(REPLACE "RBR" "]" db_text "${db_text}")
set(db "${WORK_DIR}/db.json")
file(WRITE "${db}" "${db_text}")

entries(db_other_text "${repo}/build/gen/g.cpp" "${WORK_DIR}/dep/d.cpp")
set(db_other "${WORK_DIR}/db_other.json")
file(WRITE "${db_other}" "${db_other_text}")

# The same entries on one line.
string(REPLACE "\n" "" minified "${db_text}")
set(db_minified "${WORK_DIR}/db_minified.json")
file(WRITE "${db_minified}" "${minified}\n")

# run(<expect_failure 0|1> <regex> <db> [<repo>]): runs the tool with REPO (default the fixture
# repository) and OUT=<WORK_DIR>/out.txt, and checks the status and the flattened output.
function(run expect_failure expected_text database)
    set(repo_arg "${repo}")
    if(ARGC GREATER 3)
        set(repo_arg "${ARGV3}")
    endif()
    file(REMOVE "${WORK_DIR}/out.txt")
    execute_process(COMMAND "${CMAKE_COMMAND}" "-DDB=${database}" "-DREPO=${repo_arg}"
                            "-DOUT=${WORK_DIR}/out.txt" -P "${script}"
                    RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err ENCODING UTF-8)
    set(all "${out}${err}")
    string(REGEX REPLACE "[ \t\r\n]+" " " flat "${all}")
    if(expect_failure AND status EQUAL 0)
        message(SEND_ERROR "FAIL: expected tidy-files to fail for ${database}\n${all}")
        set(failures 1 PARENT_SCOPE)
    elseif(NOT expect_failure AND NOT status EQUAL 0)
        message(SEND_ERROR "FAIL: expected tidy-files to pass for ${database}\n${all}")
        set(failures 1 PARENT_SCOPE)
    elseif(NOT expected_text STREQUAL "" AND NOT flat MATCHES "${expected_text}")
        message(SEND_ERROR "FAIL: output for ${database} lacks '${expected_text}'\n${all}")
        set(failures 1 PARENT_SCOPE)
    endif()
endfunction()

function(expect_eq got want)
    if(NOT got STREQUAL want)
        message(SEND_ERROR "FAIL: got\n[${got}]\nwant\n[${want}]")
        set(failures 1 PARENT_SCOPE)
    endif()
endfunction()

run(0 "" "${db}")
file(READ "${WORK_DIR}/out.txt" got)
expect_eq("${got}" "src/a.cpp\nsrc/sub/b.cpp\nsrc/x[1.cpp\nsrc/y]1.cpp\nsrc/ü.cpp\ntests/t.cpp\ntools/tool.cpp\n")
run(1 "compile database not found: .*missing\\.json" "${WORK_DIR}/missing.json")
run(1 "matched none of the tracked sources" "${db_other}")
run(1 "unexpected compile database layout" "${db_minified}")
run(1 "is not the top of a git work tree" "${db}" "${repo}/src")

# A path with a semicolon would be split by CMake lists: a database value and a tracked path each
# fail loudly (such a name cannot exist on Windows).
entries(db_semi_text "${repo}/src/aSEMIb.cpp")    # a list cannot carry the ; itself
string(REPLACE "SEMI" ";" db_semi_text "${db_semi_text}")
set(db_semi "${WORK_DIR}/db_semi.json")
file(WRITE "${db_semi}" "${db_semi_text}")
run(1 "contains ';'" "${db_semi}")
if(NOT CMAKE_HOST_WIN32)
    set(repo_semi "${WORK_DIR}/repo_semi")
    run_git(init -q -b main "${repo_semi}")
    file(WRITE "${repo_semi}/src/a;b.cpp" "int f();\n")
    run_git(-C "${repo_semi}" add -A)
    run(1 "contains ';'" "${db}" "${repo_semi}")
endif()

if(failures)
    message(FATAL_ERROR "tidy-files tests failed")
endif()
message(STATUS "tidy-files tests passed")
