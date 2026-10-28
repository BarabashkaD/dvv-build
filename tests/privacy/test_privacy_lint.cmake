# Tests for tools/privacy-lint.cmake.
# Run: cmake -DWORK_DIR=<empty scratch dir> -P tests/privacy/test_privacy_lint.cmake
# Offending strings are assembled from pieces so this file itself passes the lint.
cmake_minimum_required(VERSION 4.2)
if(NOT DEFINED WORK_DIR)
    message(FATAL_ERROR "pass -DWORK_DIR=<scratch directory>")
endif()
find_program(GIT_EXECUTABLE git REQUIRED)
set(lint "${CMAKE_CURRENT_LIST_DIR}/../../tools/privacy-lint.cmake")
set(failures 0)

set(drive "C")
set(other_drive "D")
set(home "home")
set(at "@")
set(octet "168")
set(bad_user_path "${drive}:\\Users\\alice\\clip.yuv")
set(bad_drive_path "${other_drive}:/media/clip.yuv")
set(bad_home "/${home}/alice/clip.yuv")
set(bad_email "alice${at}mail.test.org")
set(bad_ip "192.${octet}.1.7")
set(noreply "12345+someone${at}users.noreply.github.com")
set(second_ip "10.${octet}.2.3")
set(third_drive "E")
set(escaped_drive_path "${third_drive}:\\\\media\\\\clip.yuv")
set(wsl_letter "d")
set(bad_wsl_path "/mnt/${wsl_letter}/media/clip.yuv")
set(ssh_remote "git${at}github.com:org/repo.git")
set(zeros "0000000000000000000000000000000000000000")

function(make_repo name)
    set(dir "${WORK_DIR}/${name}")
    file(REMOVE_RECURSE "${dir}")
    file(MAKE_DIRECTORY "${dir}")
    execute_process(COMMAND "${GIT_EXECUTABLE}" init -q "${dir}" COMMAND_ERROR_IS_FATAL ANY)
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${dir}" config user.name someone)
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${dir}" config user.email "${noreply}")
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${dir}" config commit.gpgsign false)
    set(repo_dir "${dir}" PARENT_SCOPE)
endfunction()

function(commit_file dir file content message)
    file(WRITE "${dir}/${file}" "${content}")
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${dir}" add -A COMMAND_ERROR_IS_FATAL ANY)
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${dir}" commit -q -m "${message}"
                    COMMAND_ERROR_IS_FATAL ANY)
endfunction()

# expect_lint(<repo> <mode> <extra terms> <0|1 expected failure> <expected text or "">
#             [<PUSH_REFS value>])
function(expect_lint dir mode terms expect_failure expected_text)
    if(ARGC GREATER 5)
        execute_process(
            COMMAND "${CMAKE_COMMAND}" "-DREPO=${dir}" "-DMODE=${mode}" "-DEXTRA_TERMS=${terms}"
                    "-DPUSH_REFS=${ARGV5}" -P "${lint}"
            RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
    else()
        execute_process(
            COMMAND "${CMAKE_COMMAND}" "-DREPO=${dir}" "-DMODE=${mode}" "-DEXTRA_TERMS=${terms}"
                    -P "${lint}"
            RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
    endif()
    set(all "${out}${err}")
    if(expect_failure AND status EQUAL 0)
        message(SEND_ERROR "FAIL: expected lint failure for ${dir} (${mode})\n${all}")
        set(failures 1 PARENT_SCOPE)
    elseif(NOT expect_failure AND NOT status EQUAL 0)
        message(SEND_ERROR "FAIL: expected clean lint for ${dir} (${mode})\n${all}")
        set(failures 1 PARENT_SCOPE)
    elseif(expected_text AND NOT all MATCHES "${expected_text}")
        message(SEND_ERROR "FAIL: output lacks '${expected_text}' for ${dir}\n${all}")
        set(failures 1 PARENT_SCOPE)
    endif()
endfunction()

make_repo(clean)
commit_file("${repo_dir}" "notes.md"
    "Example paths: X:\\Users\\<name>\\clip.yuv and /home/<name>/clip.yuv\n\
localhost 127.0.0.1\n\
Co-Authored-By: Claude <noreply${at}anthropic.com>\n"
    "docs: add notes")
expect_lint("${repo_dir}" commits "" 0 "")

make_repo(user_path)
commit_file("${repo_dir}" "a.txt" "open ${bad_user_path}\n" "add a")
expect_lint("${repo_dir}" tree "" 1 "a.txt:1: Windows user profile path")

make_repo(drive_path)
commit_file("${repo_dir}" "a.txt" "line one\nopen ${bad_drive_path}\n" "add a")
expect_lint("${repo_dir}" tree "" 1 "a.txt:2: absolute drive path")

make_repo(home_path)
commit_file("${repo_dir}" "a.txt" "${bad_home}\n" "add a")
expect_lint("${repo_dir}" tree "" 1 "home directory path")

make_repo(email)
commit_file("${repo_dir}" "a.txt" "contact ${bad_email}\n" "add a")
expect_lint("${repo_dir}" tree "" 1 "not a noreply address")

make_repo(ip)
commit_file("${repo_dir}" "a.txt" "host ${bad_ip}\n" "add a")
expect_lint("${repo_dir}" tree "" 1 "IPv4 address")

make_repo(allowed)
commit_file("${repo_dir}" "a.txt" "host ${bad_ip} # privacy-lint: allow\n" "add a")
expect_lint("${repo_dir}" tree "" 0 "")

make_repo(message)
commit_file("${repo_dir}" "a.txt" "fine\n" "fix: build on ${bad_user_path}")
expect_lint("${repo_dir}" tree "" 0 "")
expect_lint("${repo_dir}" commits "" 1 "message:1: Windows user profile path")

make_repo(author)
execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${repo_dir}" config user.email "${bad_email}")
commit_file("${repo_dir}" "a.txt" "fine\n" "add a")
expect_lint("${repo_dir}" commits "" 1 "author or committer e-mail")

make_repo(terms)
commit_file("${repo_dir}" "a.txt" "built on Workstation-42\n" "add a")
expect_lint("${repo_dir}" tree "workstation-42" 1 "local user or host name")
expect_lint("${repo_dir}" tree "ab" 0 "")

make_repo(second_ip)
commit_file("${repo_dir}" "a.txt" "loopback 127.0.0.1 and ${second_ip}\n" "add a")
expect_lint("${repo_dir}" tree "" 1 "a.txt:1: IPv4 address")

make_repo(version)
commit_file("${repo_dir}" "a.txt" "SDK 10.0.26200.0 and 1.2.3.4.5\n" "add a")
expect_lint("${repo_dir}" tree "" 0 "")

make_repo(ssh_remote)
commit_file("${repo_dir}" "a.txt" "clone ${ssh_remote}\n" "add a")
expect_lint("${repo_dir}" tree "" 0 "")

make_repo(escaped_drive)
commit_file("${repo_dir}" "a.txt" "path ${escaped_drive_path}\n" "add a")
expect_lint("${repo_dir}" tree "" 1 "a.txt:1: absolute drive path")

make_repo(wsl_path)
commit_file("${repo_dir}" "a.txt" "path ${bad_wsl_path}\n" "add a")
expect_lint("${repo_dir}" tree "" 1 "a.txt:1: WSL mount path")

make_repo(deleted)
commit_file("${repo_dir}" "a.txt" "line\ncontact ${bad_email}\n" "add a")
commit_file("${repo_dir}" "b.txt" "other\n" "add b")
file(REMOVE "${repo_dir}/a.txt")
execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${repo_dir}" add -A COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${repo_dir}" commit -q -m "remove a"
                COMMAND_ERROR_IS_FATAL ANY)
expect_lint("${repo_dir}" tree "" 0 "")
expect_lint("${repo_dir}" commits "" 1 "commit [0-9a-f]+ a\\.txt:2: e-mail address")

make_repo(empty)
expect_lint("${repo_dir}" commits "" 0 "")
expect_lint("${repo_dir}" prepush "" 0 "")

# prepush with a bare remote: only the commits named by PUSH_REFS are checked.
set(remote_dir "${WORK_DIR}/remote.git")
file(REMOVE_RECURSE "${remote_dir}")
execute_process(COMMAND "${GIT_EXECUTABLE}" init -q --bare "${remote_dir}"
                COMMAND_ERROR_IS_FATAL ANY)
make_repo(pushing)
execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${repo_dir}" remote add origin "${remote_dir}"
                COMMAND_ERROR_IS_FATAL ANY)
commit_file("${repo_dir}" "a.txt" "fine\n" "add a")
execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${repo_dir}" push -q origin HEAD:refs/heads/main
                COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${repo_dir}" rev-parse HEAD
                OUTPUT_VARIABLE pushed_sha OUTPUT_STRIP_TRAILING_WHITESPACE
                COMMAND_ERROR_IS_FATAL ANY)
commit_file("${repo_dir}" "b.txt" "fine\n" "fix: build on ${bad_user_path}")
execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${repo_dir}" rev-parse HEAD
                OUTPUT_VARIABLE new_sha OUTPUT_STRIP_TRAILING_WHITESPACE
                COMMAND_ERROR_IS_FATAL ANY)
expect_lint("${repo_dir}" prepush "" 1 "message:1: Windows user profile path")
expect_lint("${repo_dir}" prepush "" 1 "message:1: Windows user profile path"
            "${new_sha}:${pushed_sha}")
expect_lint("${repo_dir}" prepush "" 1 "message:1: Windows user profile path"
            "${new_sha}:${zeros}")
expect_lint("${repo_dir}" prepush "" 0 "" "${pushed_sha}:${zeros}")
expect_lint("${repo_dir}" prepush "" 0 "" "${pushed_sha}:${pushed_sha}")
expect_lint("${repo_dir}" prepush "" 0 "" "${zeros}:${new_sha}")
expect_lint("${repo_dir}" prepush "" 1 "message:1: Windows user profile path"
            "${pushed_sha}:${zeros};${new_sha}:${pushed_sha}")

# Fail closed: an unknown remote sha or a malformed entry must fail, not pass silently.
set(unknown_sha "abcdefabcdefabcdefabcdefabcdefabcdefabcd")
expect_lint("${repo_dir}" prepush "" 1 "git log failed" "${new_sha}:${unknown_sha}")
expect_lint("${repo_dir}" prepush "" 1 "bad PUSH_REFS entry" "nonsense")

make_repo(mixed_case_noreply)
execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${repo_dir}" config user.email
                "12345+someone${at}Users.NoReply.GitHub.com")
commit_file("${repo_dir}" "a.txt" "fine\n" "add a")
expect_lint("${repo_dir}" commits "" 0 "")

# GitHub's own committer address passes; near misses must still fail.
make_repo(github_committer)
commit_file("${repo_dir}" "a.txt" "fine\n" "add a")
execute_process(COMMAND "${CMAKE_COMMAND}" -E env "GIT_COMMITTER_NAME=GitHub"
                        "GIT_COMMITTER_EMAIL=NoReply${at}GitHub.com"
                        "${GIT_EXECUTABLE}" -C "${repo_dir}" commit -q --amend --no-edit
                COMMAND_ERROR_IS_FATAL ANY)
expect_lint("${repo_dir}" commits "" 0 "")

set(github_near_misses "someone${at}github.com" "noreply${at}github.com.example.test"
    "xnoreply${at}github.com")
set(near_index 0)
foreach(near_miss IN LISTS github_near_misses)
    make_repo(github_near_${near_index})
    commit_file("${repo_dir}" "a.txt" "fine\n" "add a")
    execute_process(COMMAND "${CMAKE_COMMAND}" -E env "GIT_COMMITTER_NAME=GitHub"
                            "GIT_COMMITTER_EMAIL=${near_miss}"
                            "${GIT_EXECUTABLE}" -C "${repo_dir}" commit -q --amend --no-edit
                    COMMAND_ERROR_IS_FATAL ANY)
    expect_lint("${repo_dir}" commits "" 1 "author or committer e-mail")
    math(EXPR near_index "${near_index} + 1")
endforeach()

make_repo(loopback_only)
commit_file("${repo_dir}" "a.txt" "127.0.0.1\n999.1.1.1\n" "add a")
expect_lint("${repo_dir}" tree "" 0 "")

make_repo(git_plain_text)
commit_file("${repo_dir}" "a.txt" "write to git${at}company.com please\n" "add a")
expect_lint("${repo_dir}" tree "" 1 "a.txt:1: e-mail address")

make_repo(ssh_and_mail)
commit_file("${repo_dir}" "a.txt"
    "mail git${at}company.com or clone git${at}company.com:org/repo.git\n" "add a")
expect_lint("${repo_dir}" tree "" 1 "a.txt:1: e-mail address")

make_repo(ssh_then_mail)
commit_file("${repo_dir}" "a.txt"
    "clone ${ssh_remote}(${bad_email})\n" "add a")
expect_lint("${repo_dir}" tree "" 1 "a.txt:1: e-mail address")

make_repo(git_mail_colon)
commit_file("${repo_dir}" "a.txt" "contact git${at}company.com: thanks\n" "add a")
expect_lint("${repo_dir}" tree "" 1 "a.txt:1: e-mail address")

# An address glued to an SSH remote path is still found: only the "git@host:" prefix is dropped.
set(glued_cases
    "x git${at}github.com:${bad_email}"
    "git${at}h.com:a/b.git|bob${at}mail.test.org"
    "x git${at}h.com:[${bad_email}]"
    "git${at}h.com:a/b.git=bob${at}mail.test.org")
set(glued_index 0)
foreach(glued_text IN LISTS glued_cases)
    make_repo(ssh_glued_${glued_index})
    commit_file("${repo_dir}" "a.txt" "${glued_text}\n" "add a")
    expect_lint("${repo_dir}" tree "" 1 "a.txt:1: e-mail address")
    math(EXPR glued_index "${glued_index} + 1")
endforeach()

# A bad REPO must fail with the fixed message and without git's stderr or the path.
set(missing_dir "${WORK_DIR}/no-such-repo-dir")
file(REMOVE_RECURSE "${missing_dir}")
execute_process(COMMAND "${CMAKE_COMMAND}" "-DREPO=${missing_dir}" -P "${lint}"
                RESULT_VARIABLE missing_status OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(missing_status EQUAL 0)
    message(SEND_ERROR "FAIL: lint of a missing directory was expected to fail")
    set(failures 1)
endif()
string(FIND "${out}${err}" "${missing_dir}" position)
string(FIND "${out}${err}" "fatal:" fatal_position)
if(position GREATER_EQUAL 0 OR fatal_position GREATER_EQUAL 0)
    message(SEND_ERROR "FAIL: lint output repeats git's stderr or the path\n${out}${err}")
    set(failures 1)
endif()

make_repo(leak_in_output)
commit_file("${repo_dir}" "a.txt" "${bad_email}\n" "add a")
execute_process(COMMAND "${CMAKE_COMMAND}" "-DREPO=${repo_dir}" -P "${lint}"
                RESULT_VARIABLE leak_status OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(leak_status EQUAL 0)
    message(SEND_ERROR "FAIL: leak_in_output run was expected to fail")
    set(failures 1)
endif()
string(FIND "${out}${err}" "${bad_email}" position)
if(position GREATER_EQUAL 0)
    message(SEND_ERROR "FAIL: lint output repeats the private text")
    set(failures 1)
endif()

if(failures)
    message(FATAL_ERROR "privacy-lint tests failed")
endif()
message(STATUS "privacy-lint tests passed")
