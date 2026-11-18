# Tests for tools/os-blocks.cmake with fixture git repositories in WORK_DIR (no network).
# Run: cmake -DWORK_DIR=<scratch dir> -P tests/tools/test_os_blocks.cmake
cmake_minimum_required(VERSION 4.2)
if(NOT DEFINED WORK_DIR)
    message(FATAL_ERROR "pass -DWORK_DIR=<scratch directory>")
endif()
find_program(GIT_EXECUTABLE git REQUIRED)
set(script "${CMAKE_CURRENT_LIST_DIR}/../../tools/os-blocks.cmake")
set(failures 0)
file(REMOVE_RECURSE "${WORK_DIR}")
file(MAKE_DIRECTORY "${WORK_DIR}")
set(header "# os-blocks baseline, written by dvv-build tools/os-blocks.cmake; it may only shrink")

function(run_git)
    execute_process(COMMAND "${GIT_EXECUTABLE}" ${ARGN} RESULT_VARIABLE rc OUTPUT_VARIABLE out
                    ERROR_VARIABLE err OUTPUT_STRIP_TRAILING_WHITESPACE ENCODING UTF-8)
    if(NOT rc EQUAL 0)
        message(FATAL_ERROR "git ${ARGN} failed:\n${out}${err}")
    endif()
endfunction()

# fixture(<name>): fresh git repository WORK_DIR/<name> (git init -q -b main, test identity); sets `repo`.
function(fixture name)
    set(dir "${WORK_DIR}/${name}")
    run_git(init -q -b main "${dir}")
    run_git(-C "${dir}" config user.name test-user)
    run_git(-C "${dir}" config user.email test@users.noreply.github.com)
    run_git(-C "${dir}" config commit.gpgsign false)
    run_git(-C "${dir}" config core.autocrlf false)
    set(repo "${dir}" PARENT_SCOPE)
endfunction()

# put(<rel path> <content>): writes the file (directories created) and `git add`s it.
function(put rel content)
    file(WRITE "${repo}/${rel}" "${content}")
    run_git(-C "${repo}" add -- "${rel}")
endfunction()

# baseline(<rows>): writes <repo>/os-blocks.txt as the header line followed by <rows>.
function(baseline rows)
    file(WRITE "${repo}/os-blocks.txt" "${header}\n${rows}")
endfunction()

# expect(<expect_failure 0|1> <regex> [-DMODE=...] [-DBASELINE=...]): runs the tool on `repo`,
# checks the exit status and the whitespace-flattened output, like check-pins' expect().
function(expect expect_failure expected_text)
    execute_process(COMMAND "${CMAKE_COMMAND}" "-DREPO=${repo}" ${ARGN} -P "${script}"
                    RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err ENCODING UTF-8)
    set(all "${out}${err}")
    string(REGEX REPLACE "[ \t\r\n]+" " " flat "${all}")
    set(last_out "${flat}" PARENT_SCOPE)
    if(expect_failure AND status EQUAL 0)
        message(SEND_ERROR "FAIL: expected os-blocks to fail for ${repo}\n${all}")
        set(failures 1 PARENT_SCOPE)
    elseif(NOT expect_failure AND NOT status EQUAL 0)
        message(SEND_ERROR "FAIL: expected os-blocks to pass for ${repo}\n${all}")
        set(failures 1 PARENT_SCOPE)
    elseif(NOT expected_text STREQUAL "" AND NOT flat MATCHES "${expected_text}")
        message(SEND_ERROR "FAIL: output for ${repo} lacks '${expected_text}'\n${all}")
        set(failures 1 PARENT_SCOPE)
    endif()
endfunction()

# expect_absent(<regex>): the output of the last expect() does not match <regex>.
function(expect_absent regex)
    if(last_out MATCHES "${regex}")
        message(SEND_ERROR "FAIL: output has '${regex}'\n${last_out}")
        set(failures 1 PARENT_SCOPE)
    endif()
endfunction()

set(WIN "#if defined(_WIN32)\n")
set(CODE6 "${WIN}int a1 = 1;\nint a2 = 2;\nint a3 = 3;\nint a4 = 4;\n#endif\n")
set(CODE5 "${WIN}int a1 = 1;\nint a2 = 2;\nint a3 = 3;\n#endif\n")
set(FREE6 "${WIN}#include <a.h>\n#pragma once\n#include <b.h>\n#include <c.h>\n#endif\n")
set(COMMENT6 "${WIN}/* one\ntwo\nthree */\n\n#endif\n")
set(DEFINE6 "${WIN}#define D1 1\n#define D2 2\n#define D3 3\n#define D4 4\n#endif\n")
set(over "OS blocks over 5 lines")

# 1: a 6-line _WIN32 block with code fails against an empty baseline.
fixture(c01)
put(a.cpp "${CODE6}")
expect(1 "a\\.cpp: 1 ${over} \\(baseline 0\\): move the code into a per-OS file")

# 2: the same block in a per-OS file passes.
fixture(c02)
put(a_win32.cpp "${CODE6}")
expect(0 "os-blocks: OK \\(0 files, 0 counted blocks, baseline 0 rows\\)")

# 3: a row for a file renamed to a per-OS file is stale.
fixture(c03)
put(a.cpp "${CODE6}")
baseline("1\ta.cpp\n")
expect(0 "os-blocks: OK \\(1 files, 1 counted blocks, baseline 1 rows\\)")
run_git(-C "${repo}" mv a.cpp a_win32.cpp)
expect(1 "stale row a\\.cpp")

# 4: an include-and-pragma block and a 5-line block with code pass.
fixture(c04)
put(a.cpp "${FREE6}")
put(b.cpp "${CODE5}")
expect(0 "os-blocks: OK \\(2 files, 0 counted blocks, baseline 0 rows\\)")

# 5: a block whose only other lines are a comment and a blank line passes.
fixture(c05)
put(a.cpp "${COMMENT6}")
expect(0 "os-blocks: OK")

# 6: a #define block counts.
fixture(c06)
put(a.cpp "${DEFINE6}")
expect(1 "a\\.cpp: 1 OS blocks")

# 7: an OS group nested in an OS group counts once.
fixture(c07)
put(a.cpp "#ifdef __APPLE__\n${CODE6}int b = 1;\n#endif\n")
expect(1 "a\\.cpp: 1 ${over}")

# 8: spaces after # and #ifdef __APPLE__ count, both in one run.
fixture(c08)
put(a.cpp "#  if defined(_WIN32)\nint a1 = 1;\nint a2 = 2;\nint a3 = 3;\nint a4 = 4;\n#  endif\n")
put(b.h "#ifdef __APPLE__\nint a1 = 1;\nint a2 = 2;\nint a3 = 3;\nint a4 = 4;\n#endif\n")
expect(1 "a\\.cpp: 1 ${over}.*b\\.h: 1 ${over}")

# 9: a compiler group with an OS #elif counts.
fixture(c09)
put(a.cpp "#if defined(__clang__)\nint a = 1;\n#elif defined(_WIN32)\nint b = 2;\nint c = 3;\n#else\n#endif\n")
expect(1 "a\\.cpp: 1 OS blocks")

# 10: a non-OS group holding an OS block counts once.
fixture(c10)
put(a.cpp "#if FOO\n${CODE6}#endif\n")
expect(1 "a\\.cpp: 1 OS blocks")

# 11: a continued condition counts.
fixture(c11)
put(a.cpp "#if defined(_WIN32) \\\n    || defined(__APPLE__)\nint a1 = 1;\nint a2 = 2;\nint a3 = 3;\n#endif\n")
expect(1 "a\\.cpp: 1 OS blocks")

# 12: .h and .mm files count.
fixture(c12)
put(x.h "${CODE6}")
put(x.mm "${CODE6}")
expect(1 "x\\.h: 1 ${over}.*x\\.mm: 1 ${over}")

# 13: tests/ is ignored, and a row for a file moved under tests/ is stale.
fixture(c13)
put(tests/x.cpp "${CODE6}")
expect(0 "os-blocks: OK \\(0 files, 0 counted blocks, baseline 0 rows\\)")
put(src/y.cpp "${CODE6}")
baseline("1\tsrc/y.cpp\n")
expect(0 "os-blocks: OK \\(1 files, 1 counted blocks, baseline 1 rows\\)")
run_git(-C "${repo}" mv src/y.cpp tests/y.cpp)
expect(1 "stale row src/y\\.cpp")

# 14: a count below its row asks to shrink the baseline; a row for a deleted file is stale.
fixture(c14)
put(a.cpp "${CODE6}")
baseline("2\ta.cpp\n")
expect(1 "a\\.cpp: 1 blocks, baseline 2: shrink the baseline \\(MODE=write\\)")
put(gone.cpp "${CODE6}")
baseline("1\ta.cpp\n1\tgone.cpp\n")
expect(0 "os-blocks: OK \\(2 files, 2 counted blocks, baseline 2 rows\\)")
run_git(-C "${repo}" rm -q -f gone.cpp)
expect(1 "stale row gone\\.cpp")

# 15: malformed lines, a count of 0 and a duplicate path fail at once.
fixture(c15)
put(a.cpp "${CODE6}")
foreach(row "x\ta.cpp" "1 a.cpp" "0\ta.cpp" "01\ta.cpp" "-1\ta.cpp" "\ta.cpp" "1\t" "")
    baseline("${row}\n1\ta.cpp\n")
    expect(1 "bad baseline line 2: ")
endforeach()
baseline("1\ta.cpp\n1\ta.cpp\n")
expect(1 "bad baseline line 3: ")
file(WRITE "${repo}/os-blocks.txt" "x\ta.cpp\n")
expect(1 "bad baseline line 1: ")

# 16: write then check passes, and write writes no 0 row.
fixture(c16)
put(a.cpp "${CODE6}")
put(b.cpp "${CODE5}")
expect(0 "" -DMODE=write)
file(READ "${repo}/os-blocks.txt" written)
if(NOT written STREQUAL "${header}\n1\ta.cpp\n")
    message(SEND_ERROR "FAIL: written baseline is\n${written}")
    set(failures 1)
endif()
expect(0 "os-blocks: OK \\(2 files, 1 counted blocks, baseline 1 rows\\)")
# BASELINE names another file.
expect(0 "" -DMODE=write "-DBASELINE=${WORK_DIR}/c16-baseline.txt")
file(READ "${WORK_DIR}/c16-baseline.txt" other)
if(NOT other STREQUAL "${header}\n1\ta.cpp\n")
    message(SEND_ERROR "FAIL: BASELINE file is\n${other}")
    set(failures 1)
endif()
expect(0 "os-blocks: OK" "-DBASELINE=${WORK_DIR}/c16-baseline.txt")
expect(1 "MODE must be check or write" -DMODE=fix)

# 17: write on a clean tree deletes the baseline; with no baseline file one block fails check.
fixture(c17)
put(b.cpp "${CODE5}")
baseline("1\told.cpp\n")
expect(0 "" -DMODE=write)
if(EXISTS "${repo}/os-blocks.txt")
    message(SEND_ERROR "FAIL: write on a clean tree kept the baseline file")
    set(failures 1)
endif()
put(a.cpp "${CODE6}")
expect(1 "a\\.cpp: 1 ${over} \\(baseline 0\\)")

# 18 (E2): a plain folder and a subfolder of a repository are not the top of a git work tree.
set(repo "${WORK_DIR}/plain")
file(WRITE "${repo}/a.cpp" "${CODE6}")
expect(1 "is not the top of a git work tree")
fixture(c18)
put(src/a.cpp "${CODE6}")
set(repo "${repo}/src")
expect(1 "is not the top of a git work tree")

# 19 (RF 1): an unclosed #if and a stray #endif are reported per file.
fixture(c19)
put(a.cpp "${WIN}int a = 1;\n")
put(b.cpp "#endif\n")
expect(1 "a\\.cpp: unbalanced #if/#endif at line 1.*b\\.cpp: unbalanced #if/#endif at line 1")
expect(1 "unbalanced" -DMODE=write)

# 20 (RF 1): a block inside a comment is no block.
fixture(c20)
put(a.cpp "/*\n${CODE6}*/\n")
expect(0 "os-blocks: OK \\(1 files, 0 counted blocks")

# 21 (RF 2): CRLF line endings and the characters ; [ ] in code and in the baseline.
fixture(c21)
set(code "int x[2] = {1, 2}; f(x[0]);\r\n")
put(a.cpp "#if defined(_WIN32)\r\n${code}${code}${code}${code}#endif\r\n")
file(WRITE "${repo}/os-blocks.txt" "${header}\r\n1\ta.cpp\r\n")
expect(0 "os-blocks: OK \\(1 files, 1 counted blocks, baseline 1 rows\\)")

# 22 (RF 3): a path with a space and a non-ASCII letter.
fixture(c22)
put("src/ü dir/x y.cpp" "${CODE6}")
expect(0 "" -DMODE=write)
file(READ "${repo}/os-blocks.txt" written)
if(NOT written STREQUAL "${header}\n1\tsrc/ü dir/x y.cpp\n")
    message(SEND_ERROR "FAIL: written baseline is\n${written}")
    set(failures 1)
endif()
expect(0 "os-blocks: OK \\(1 files, 1 counted blocks, baseline 1 rows\\)")

# Comments and string literals: a commented-out #if, a "/*" in a string, a // comment line.
fixture(c23)
put(a.cpp "// #if defined(_WIN32)\nconst char* s = \"/*\";\n${CODE6}int z = 0; // tail\n")
put(b.cpp "#if defined(_WIN32) /* a\nb */\nint a = 1;\n/* c */ #endif\n")
# Character literals: '"' does not open a string, so the "/*" after it stays a string; digit
# separators and escapes do not open a literal either.
put(c.cpp "int q = (c == '\"') ? f(\"/*\") : 0;\nint big = 1'000'000 + 1'0; char e = '\\'';\n${CODE6}int z; /* x */\n")
expect(1 "a\\.cpp: 1 ${over}.*c\\.cpp: 1 ${over}")

# Raw string literals: a /* or an #if inside one, across lines, with any prefix and delimiter.
fixture(c24)
put(a.cpp "const char* s = R\"x(\n/* not a comment\n#if defined(_WIN32)\n)\" still inside\n)x\";\n${CODE6}int z = 0; /* y */\n")
put(b.cpp "auto t = u8R\"--(/* #if )--\"; auto w = LR\"(\"/*)\";\n${CODE6}")
put(c.cpp "auto r = R\"(\n${CODE6})\";\n")
expect(1 "a\\.cpp: 1 ${over}.*b\\.cpp: 1 ${over}")
expect_absent("c\\.cpp|unbalanced")

# A path that git quotes even with core.quotePath=false fails loudly (such names cannot exist on
# Windows).
if(NOT CMAKE_HOST_WIN32)
    fixture(c25)
    put("a\"b.cpp" "${CODE6}")
    expect(1 "git quoted the path .*rename it")
endif()

if(failures)
    message(FATAL_ERROR "os-blocks tests failed")
endif()
message(STATUS "os-blocks tests passed")
