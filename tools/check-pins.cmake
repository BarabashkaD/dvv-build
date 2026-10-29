# check-pins.cmake: checks the dvv version references of a library or of the app. Part of dvv-build.
# Usage: cmake -DREPO=<path of the repository folder> [-DMODE=lib|app] -P <dvv-build>/tools/check-pins.cmake
# REPO is a path (absolute or relative to the current folder), e.g. dvv-gpu or rawreel; fetch-deps.cmake
# takes a folder name in the dvv root instead. MODE defaults to app when <REPO>/.gitmodules exists, else lib.
# Lib mode: every reference to dvv-build's reusable workflows in .github/workflows/*.yml|*.yaml
#   (a `uses: <owner>/dvv-build/.github/workflows/<file>@v<X>` line, not a comment) has X = the
#   dvv-build line of dvv-deps.txt (read with cmake/DvvDepsFile.cmake, as DvvDeps.cmake does); there
#   is at least one. A dvv-deps.txt line with a branch-only override (' @<commit>') is an error: main
#   depends on tags only, so a branch goes back on tags before merge.
# App mode: each submodule in .gitmodules has the path libs/dvv-<name> and the relative URL
#   ../dvv-<name> (no .git suffix); it is checked out at its committed pin; the pin is the commit of
#   tag v<its version> on its origin (`git ls-remote`, peeled for annotated tags; the version is read
#   at the pin: VERSION for dvv-build and project(dvv_<name> VERSION ...) for a library); libs/dvv-build
#   is one of them, and the workflows' dvv-build @v<X> has X = the VERSION of libs/dvv-build's pin.
#   A branch-only override is an error here too: in the app's own dvv-deps.txt (the app moves the
#   libs/<name> submodule instead), and in a library's dvv-deps.txt at its pin (a tag placed on a
#   branch commit that still carries ' @<commit>').
# All problems are reported together; the script fails if there is any. Git never asks for
# credentials (it fails instead), and credentials in a URL are not printed.
cmake_minimum_required(VERSION 4.2)
include("${CMAKE_CURRENT_LIST_DIR}/../cmake/DvvDepsFile.cmake")
find_program(GIT_EXECUTABLE git REQUIRED)
set(ENV{GIT_TERMINAL_PROMPT} 0)
set(ENV{GCM_INTERACTIVE} never)
if(NOT DEFINED REPO OR REPO STREQUAL "")
    message(FATAL_ERROR "pass -DREPO=<path of the repository folder>")
endif()
file(REAL_PATH "${REPO}" repo)
if(NOT IS_DIRECTORY "${repo}")
    message(FATAL_ERROR "${REPO} is not a folder (REPO is the path of the repository folder)")
endif()
if(NOT DEFINED MODE OR MODE STREQUAL "")
    if(EXISTS "${repo}/.gitmodules")
        set(MODE app)
    else()
        set(MODE lib)
    endif()
elseif(NOT MODE MATCHES "^(lib|app)$")
    message(FATAL_ERROR "MODE must be lib or app (default: app when .gitmodules exists), got '${MODE}'")
endif()
set(errors "")

# add_error(<text>...): collects the concatenated texts as one error (a ';' would split it into two
# list items, so it becomes ',').
function(add_error)
    set(text "")
    math(EXPR last "${ARGC} - 1")
    foreach(i RANGE ${last})
        string(APPEND text "${ARGV${i}}")
    endforeach()
    string(REPLACE ";" "," text "${text}")
    dvv_hide_credentials(text "${text}")
    set(errors "${errors};${text}")
    string(REGEX REPLACE "^;" "" errors "${errors}")
    set(errors "${errors}" PARENT_SCOPE)
endfunction()

# check_workflows(<version> <ok text> <mismatch text>): the @v<X> of every dvv-build workflow
# reference is v<version>; at least one reference exists.
function(check_workflows version ok_text mismatch_text)
    file(GLOB files "${repo}/.github/workflows/*.yml" "${repo}/.github/workflows/*.yaml")
    set(count 0)
    foreach(file IN LISTS files)
        cmake_path(GET file FILENAME name)
        file(STRINGS "${file}" lines REGEX "dvv-build/\\.github/workflows/")
        foreach(line IN LISTS lines)
            if(NOT line MATCHES "^[ \t]*(-[ \t]+)?uses:[ \t]*['\"]?[^ \t'\"]*/dvv-build/\\.github/workflows/[^@ \t\r'\"]+@([^ \t\r'\"#]+)")
                continue()
            endif()
            math(EXPR count "${count} + 1")
            if(CMAKE_MATCH_2 STREQUAL "v${version}")
                message(STATUS "check-pins: ${MODE} mode: ${name} @${CMAKE_MATCH_2} = ${ok_text}")
            else()
                add_error("${name}: dvv-build workflow @${CMAKE_MATCH_2}, but ${mismatch_text}: "
                          "move both together")
            endif()
        endforeach()
    endforeach()
    if(count EQUAL 0)
        add_error("no workflow in ${repo}/.github/workflows uses dvv-build's dvv-ci.yml (expected "
                  "`uses: <owner>/dvv-build/.github/workflows/dvv-ci.yml@v${version}`)")
    endif()
    set(errors "${errors}" PARENT_SCOPE)
endfunction()

if(MODE STREQUAL "lib")
    cmake_path(GET repo FILENAME who)
    dvv_read_deps_file("${who}" "${repo}/dvv-deps.txt" lib)
    foreach(dep IN LISTS lib_overrides)
        add_error("dvv-deps.txt: ${dep} ${lib_min_${dep}} @${lib_commit_${dep}} is a branch-only override: "
                  "back on tags before merge (tag that ${dep} commit, raise the minimum to its version "
                  "and remove ' @${lib_commit_${dep}}')")
    endforeach()
    check_workflows("${lib_build_min}" "dvv-build ${lib_build_min}"
                    "dvv-deps.txt has dvv-build ${lib_build_min}")
else()
    if(NOT EXISTS "${repo}/.gitmodules")
        message(FATAL_ERROR "app mode needs ${repo}/.gitmodules")
    endif()
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${repo}" config -f .gitmodules
                            --get-regexp "^submodule\\..*\\.(path|url)$"
                    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err
                    OUTPUT_STRIP_TRAILING_WHITESPACE)
    # Exit code 1 without output: no entry at all (an empty .gitmodules).
    if(NOT rc EQUAL 0 AND NOT (rc EQUAL 1 AND out STREQUAL "" AND err STREQUAL ""))
        message(FATAL_ERROR "cannot read ${repo}/.gitmodules: ${err}")
    endif()
    string(REPLACE "\n" ";" entries "${out}")
    set(subs "")
    foreach(entry IN LISTS entries)
        if(entry MATCHES "^submodule\\.(.+)\\.(path|url) (.*)$")
            string(MAKE_C_IDENTIFIER "${CMAKE_MATCH_1}" id)
            set(${CMAKE_MATCH_2}_${id} "${CMAKE_MATCH_3}")
            if(NOT id IN_LIST subs)
                list(APPEND subs "${id}")
            endif()
        endif()
    endforeach()

    if(EXISTS "${repo}/dvv-deps.txt")
        cmake_path(GET repo FILENAME who)
        dvv_read_deps_file("${who}" "${repo}/dvv-deps.txt" app ERROR_VARIABLE parse_error)
        if(NOT parse_error STREQUAL "")
            add_error("${parse_error}")
        endif()
        foreach(dep IN LISTS app_overrides)
            add_error("dvv-deps.txt: ${dep} ${app_min_${dep}} @${app_commit_${dep}} is a branch-only "
                      "override: in the app, move the libs/${dep} submodule instead and remove "
                      "' @${app_commit_${dep}}'")
        endforeach()
    endif()

    set(build_version "")
    set(has_build FALSE)
    foreach(id IN LISTS subs)
        set(path "${path_${id}}")
        set(url "${url_${id}}")
        if(NOT path MATCHES "^libs/(dvv-[a-z0-9-]+)$")
            add_error("submodule path '${path}' is not libs/dvv-<name>")
            continue()
        endif()
        set(name "${CMAKE_MATCH_1}")
        if(name STREQUAL "dvv-build")
            set(has_build TRUE)
        endif()
        if(NOT url STREQUAL "../${name}")
            add_error("${path}: URL '${url}' is not '../${name}' (relative, no .git suffix)")
        endif()
        set(dir "${repo}/${path}")
        if(NOT EXISTS "${dir}/.git")
            add_error("${path} is not checked out: run `git submodule update --init`")
            continue()
        endif()
        execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${repo}" ls-tree HEAD -- "${path}"
                        OUTPUT_VARIABLE tree ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
        if(NOT tree MATCHES "^160000 commit ([0-9a-f]+)\t")
            add_error("${path} has no committed pin (gitlink) in HEAD")
            continue()
        endif()
        set(pin "${CMAKE_MATCH_1}")

        # The version at the pin (not the work tree), read before the checkout check, so that the
        # workflows' @vX is checked against the pinned dvv-build even when its checkout differs.
        set(version "")
        if(name STREQUAL "dvv-build")
            execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${dir}" show "${pin}:VERSION"
                            RESULT_VARIABLE rc OUTPUT_VARIABLE text ERROR_QUIET)
            if(rc EQUAL 0)
                string(REGEX MATCH "^[ \t\r\n]*[0-9]+\\.[0-9]+\\.[0-9]+" version "${text}")
                string(STRIP "${version}" version)
            endif()
        else()
            execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${dir}" show "${pin}:CMakeLists.txt"
                            RESULT_VARIABLE rc OUTPUT_VARIABLE text ERROR_QUIET)
            if(rc EQUAL 0)
                dvv_project_version(version "${name}" "${text}")
            endif()
            # A library's own overrides at the pin (e.g. a tag placed on a branch commit).
            execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${dir}" show "${pin}:dvv-deps.txt"
                            RESULT_VARIABLE rc OUTPUT_VARIABLE text ERROR_QUIET)
            if(rc EQUAL 0)
                dvv_read_deps_file("${name}" "${path}/dvv-deps.txt" sub TEXT "${text}"
                                   ERROR_VARIABLE parse_error)
                if(NOT parse_error STREQUAL "")
                    add_error("${path}: its dvv-deps.txt at the pin ${pin} is not valid: ${parse_error}")
                endif()
                foreach(o IN LISTS sub_overrides)
                    add_error("${path}: its dvv-deps.txt at the pin ${pin} overrides ${o} with "
                              "${sub_commit_${o}}: pin a release whose dvv-deps.txt has no override")
                endforeach()
            endif()
        endif()
        if(name STREQUAL "dvv-build")
            set(build_version "${version}")
        endif()

        execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${dir}" rev-parse HEAD
                        OUTPUT_VARIABLE head ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
        if(NOT head STREQUAL pin)
            add_error("${path} is checked out at ${head}, not at the pin ${pin}: run "
                      "`git submodule update` or commit the new pin")
            continue()
        endif()
        if(version STREQUAL "")
            add_error("${path}: cannot read its version at the pin ${pin} (VERSION or project(... VERSION))")
            continue()
        endif()

        execute_process(COMMAND "${GIT_EXECUTABLE}" -c credential.interactive=never -C "${dir}"
                                ls-remote origin "refs/tags/v${version}*"
                        RESULT_VARIABLE rc OUTPUT_VARIABLE refs ERROR_VARIABLE err
                        OUTPUT_STRIP_TRAILING_WHITESPACE)
        if(NOT rc EQUAL 0)
            string(STRIP "${err}" err)
            add_error("${path}: cannot list the tags of its origin: ${err}")
            continue()
        endif()
        string(REPLACE "\n" ";" refs "${refs}")
        set(direct "")
        set(peeled "")
        foreach(ref IN LISTS refs)
            if(ref MATCHES "^([0-9a-f]+)[ \t]+(.+)$")
                if(CMAKE_MATCH_2 STREQUAL "refs/tags/v${version}^{}")
                    set(peeled "${CMAKE_MATCH_1}")
                elseif(CMAKE_MATCH_2 STREQUAL "refs/tags/v${version}")
                    set(direct "${CMAKE_MATCH_1}")
                endif()
            endif()
        endforeach()
        set(tag "${peeled}")
        if(tag STREQUAL "")
            set(tag "${direct}")
        endif()
        if(tag STREQUAL "")
            add_error("${path}: pin ${pin} (version ${version}) is not tagged: origin has no tag "
                      "v${version} - tag that commit v${version} and push the tag, or pin a tagged commit")
        elseif(NOT tag STREQUAL pin)
            add_error("${path}: pin ${pin} has version ${version}, but tag v${version} on origin is "
                      "${tag}: pin the tagged commit or bump the version")
        else()
            message(STATUS "check-pins: app mode: ${path} ${version} = tag v${version}")
        endif()
    endforeach()

    if(NOT has_build)
        add_error("no submodule libs/dvv-build in ${repo}/.gitmodules")
    elseif(build_version STREQUAL "")
        add_error("the workflows' dvv-build @vX were not checked: the version of libs/dvv-build at its "
                  "pin is unknown (see above)")
    else()
        check_workflows("${build_version}" "libs/dvv-build VERSION ${build_version}"
                        "libs/dvv-build has VERSION ${build_version}")
    endif()
endif()

if(errors)
    list(JOIN errors "\n  " text)
    message(FATAL_ERROR "check-pins (${MODE} mode) for ${repo} failed:\n  ${text}")
endif()
message(STATUS "check-pins: ${MODE} mode: ${repo}: all checks passed")
