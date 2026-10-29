# fetch-deps.cmake: puts the dvv dependencies of a library next to it (lib layout). Part of dvv-build.
# Usage, from any folder:
#   cmake -DREPO=<library> [-DDVV_GIT_BASE_URL=<base URL>] -P <root>/dvv-build/tools/fetch-deps.cmake
# REPO is the folder name of the library in the dvv root (e.g. dvv-gpu), not a path; check-pins.cmake
# takes a path instead. The dvv root is the parent folder of the dvv-build holding this script. It
# reads <root>/<REPO>/dvv-deps.txt (with cmake/DvvDepsFile.cmake, as DvvDeps.cmake does) and then:
# 1. checks that this dvv-build's VERSION has the major of the dvv-build line and is >= it;
# 2. for each dvv-<x> line: an existing <root>/dvv-<x> must have the same major and a version
#    >= the minimum (it is never updated); a missing one is cloned at tag v<minimum>, depth 1, from
#    <base URL>/dvv-<x>, and its version must be exactly the minimum. The base URL is
#    DVV_GIT_BASE_URL (-D or environment), else the library's origin URL without its last path component.
#    A line with a branch-only override ' @<commit>' instead fetches exactly that commit (depth 1) into
#    a missing folder, verifies the checkout and requires a version >= the minimum (same major); an
#    existing folder must be checked out at that commit;
# 3. checks the rule "a repository's minimum for X >= the minimum for X of each of its dvv
#    dependencies" for every dependency's own dvv-deps.txt (X = dvv-build or a dvv library), and that
#    the library lists every dvv library its dependencies list. A dependency above its minimum is
#    checked at its tag v<minimum> when its folder has that tag, else at its present version.
# All problems are reported together; the script fails if there is any. Git never asks for
# credentials (it fails instead), and credentials in a URL are not printed.
cmake_minimum_required(VERSION 4.2)
include("${CMAKE_CURRENT_LIST_DIR}/../cmake/DvvDepsFile.cmake")
find_program(GIT_EXECUTABLE git REQUIRED)
set(ENV{GIT_TERMINAL_PROMPT} 0)
set(ENV{GCM_INTERACTIVE} never)
cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH build_dir)
cmake_path(GET build_dir PARENT_PATH root)
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
    set(errors "${errors};${text}")
    string(REGEX REPLACE "^;" "" errors "${errors}")
    set(errors "${errors}" PARENT_SCOPE)
endfunction()

# version_of(<out> <dir>): the project() version of the dvv library in <dir>, or "".
function(version_of out dir)
    set(version "")
    if(EXISTS "${dir}/CMakeLists.txt")
        cmake_path(GET dir FILENAME name)
        file(READ "${dir}/CMakeLists.txt" text)
        dvv_project_version(version "${name}" "${text}")
    endif()
    set(${out} "${version}" PARENT_SCOPE)
endfunction()

if(NOT DEFINED REPO OR REPO STREQUAL "")
    message(FATAL_ERROR "pass -DREPO=<folder name of the library in ${root}, e.g. dvv-gpu>")
endif()
if(NOT REPO MATCHES "^[A-Za-z0-9._-]+$" OR REPO MATCHES "^[.]+$")
    message(FATAL_ERROR "REPO is the folder name of the library in ${root} (e.g. dvv-gpu), not a path: "
                        "got '${REPO}'")
endif()
set(lib_dir "${root}/${REPO}")
if(NOT IS_DIRECTORY "${lib_dir}")
    message(FATAL_ERROR "folder ${lib_dir} does not exist: REPO is the folder name of the library in "
                        "${root}")
endif()
dvv_read_deps_file("${REPO}" "${lib_dir}/dvv-deps.txt" lib)

# 1. This dvv-build.
set(build_version "")
if(EXISTS "${build_dir}/VERSION")
    file(STRINGS "${build_dir}/VERSION" build_version LIMIT_COUNT 1)
    string(STRIP "${build_version}" build_version)
endif()
dvv_version_meets(ok "${build_version}" "${lib_build_min}")
if(NOT ok)
    message(FATAL_ERROR "${REPO} needs dvv-build >= ${lib_build_min} (same major), found ${build_version} "
                        "at ${build_dir}: clone dvv-build at tag v${lib_build_min} next to ${REPO}")
endif()

# 2. The dependencies.
set(base_url "${DVV_GIT_BASE_URL}")
if(base_url STREQUAL "")
    set(base_url "$ENV{DVV_GIT_BASE_URL}")
endif()
if(base_url STREQUAL "" AND lib_repos)
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${lib_dir}" remote get-url origin
                    RESULT_VARIABLE rc OUTPUT_VARIABLE origin ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
    if(NOT rc EQUAL 0 OR origin STREQUAL "")
        message(FATAL_ERROR "${REPO} has no origin to derive the dependencies' URLs from: pass "
                            "-DDVV_GIT_BASE_URL=<URL of the folder or account holding the dvv repositories>")
    endif()
    string(REPLACE "\\" "/" origin "${origin}")
    string(REGEX REPLACE "/+$" "" origin "${origin}")
    string(REGEX REPLACE "\\.git$" "" origin "${origin}")
    if(NOT origin MATCHES "^(.+)/[^/]+$")
        dvv_hide_credentials(origin "${origin}")
        message(FATAL_ERROR "cannot derive a base URL from ${REPO}'s origin '${origin}': pass "
                            "-DDVV_GIT_BASE_URL=<base URL>")
    endif()
    set(base_url "${CMAKE_MATCH_1}")
endif()
string(REPLACE "\\" "/" base_url "${base_url}")
string(REGEX REPLACE "/+$" "" base_url "${base_url}")

set(present "")
foreach(dep IN LISTS lib_repos)
    set(min "${lib_min_${dep}}")
    set(commit "${lib_commit_${dep}}")
    set(dir "${root}/${dep}")
    if(EXISTS "${dir}")
        if(NOT commit STREQUAL "")
            # The override is checked first: the folder's commit decides, its version comes second.
            execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${dir}" rev-parse HEAD
                            OUTPUT_VARIABLE head ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
            if(NOT head STREQUAL commit)
                if(head STREQUAL "")
                    set(head "no git commit")
                endif()
                add_error("${REPO} overrides ${dep} with commit ${commit}, but ${dir} is at ${head}: set "
                          "the override to that folder's commit (`git -C ${dir} rev-parse HEAD`), check out "
                          "${commit} there, or remove that folder and run this script again")
                continue()
            endif()
        endif()
        version_of(found "${dir}")
        dvv_version_meets(ok "${found}" "${min}")
        if(found STREQUAL "")
            set(found "no version (no project(... VERSION) in CMakeLists.txt)")
        endif()
        if(NOT ok AND NOT commit STREQUAL "")
            add_error("${dep} commit ${commit} at ${dir} has project version '${found}', but ${REPO} "
                      "needs ${dep} >= ${min} (same major): override a later commit or lower the minimum")
            continue()
        elseif(NOT ok)
            add_error("${REPO} needs ${dep} >= ${min} (same major), found ${found} at ${dir}: check it "
                      "out at a matching tag (`git -C ${dir} fetch --tags` and `git -C ${dir} checkout "
                      "v${min}`) or remove that folder and run this script again")
            continue()
        endif()
        if(NOT commit STREQUAL "")
            message(STATUS "fetch-deps: ${dep} ${found} present at ${dir} at the override commit ${commit} "
                           "(minimum ${min})")
        else()
            message(STATUS "fetch-deps: ${dep} ${found} present at ${dir} (minimum ${min})")
        endif()
    elseif(NOT commit STREQUAL "")
        # The branch-only override: fetch exactly that commit (depth 1) instead of the tag.
        set(url "${base_url}/${dep}")
        dvv_hide_credentials(shown "${url}")
        set(steps "init|-q|${dir}" "-C|${dir}|remote|add|origin|${url}"
                  "-C|${dir}|-c|credential.interactive=never|fetch|-q|--depth|1|origin|${commit}"
                  "-C|${dir}|-c|advice.detachedHead=false|checkout|-q|--detach|FETCH_HEAD")
        set(out "")
        foreach(step IN LISTS steps)
            string(REPLACE "|" ";" step "${step}")
            execute_process(COMMAND "${GIT_EXECUTABLE}" ${step}
                            RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
            if(NOT rc EQUAL 0)
                string(STRIP "${out}${err}" out)
                dvv_hide_credentials(out "${out}")
                if(out STREQUAL "")
                    set(out "git failed (${rc})")
                endif()
                break()
            endif()
            set(out "")
        endforeach()
        if(out STREQUAL "")
            execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${dir}" rev-parse HEAD
                            OUTPUT_VARIABLE head ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
            if(NOT head STREQUAL commit)
                set(out "the checkout is at '${head}', not at ${commit}")
            endif()
        endif()
        if(NOT out STREQUAL "")
            file(REMOVE_RECURSE "${dir}")
            add_error("could not check out ${dep} commit ${commit} (the override in ${REPO}/dvv-deps.txt) "
                      "from ${shown}: ${out} - check the commit is pushed there or set DVV_GIT_BASE_URL")
            continue()
        endif()
        version_of(found "${dir}")
        dvv_version_meets(ok "${found}" "${min}")
        if(NOT ok)
            add_error("${dep} commit ${commit} from ${shown} has project version '${found}', but ${REPO} "
                      "needs ${dep} >= ${min} (same major): override a later commit or lower the minimum")
            continue()
        endif()
        message(STATUS "fetch-deps: ${dep}: checked out commit ${commit} (version ${found}, override of "
                       "v${min}) from ${shown}")
    else()
        set(url "${base_url}/${dep}")
        dvv_hide_credentials(shown "${url}")
        execute_process(COMMAND "${GIT_EXECUTABLE}" -c advice.detachedHead=false
                                -c credential.interactive=never clone -q --depth 1
                                --branch "v${min}" "${url}" "${dir}"
                        RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
        if(NOT rc EQUAL 0)
            file(REMOVE_RECURSE "${dir}")
            string(STRIP "${out}${err}" out)
            dvv_hide_credentials(out "${out}")
            add_error("could not clone ${shown} (${dep} at tag v${min}): ${out} - check the tag "
                      "exists there or set DVV_GIT_BASE_URL")
            continue()
        endif()
        version_of(found "${dir}")
        if(NOT found STREQUAL min)
            add_error("${dep} tag v${min} from ${shown} has project version '${found}', not ${min} "
                      "(a broken release of ${dep})")
            continue()
        endif()
        message(STATUS "fetch-deps: ${dep}: cloned v${min} from ${shown}")
    endif()
    list(APPEND present "${dep}")
endforeach()

# 3. The dependencies' own minimums, at the library's minimum of each dependency when possible.
foreach(dep IN LISTS present)
    set(min "${lib_min_${dep}}")
    set(dir "${root}/${dep}")
    version_of(dep_version "${dir}")
    set(at "${dep} ${dep_version}")
    set(above "")
    set(text_args "")
    set(where "${dir}/dvv-deps.txt")
    if(NOT lib_commit_${dep} STREQUAL "")
        # An override is checked as checked out: its work tree is what the build uses.
        set(at "${dep} ${dep_version} (commit ${lib_commit_${dep}})")
    elseif(NOT dep_version STREQUAL min)
        set(tagged FALSE)
        if(EXISTS "${dir}/.git")
            execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${dir}" rev-parse -q --verify "refs/tags/v${min}"
                            RESULT_VARIABLE rc OUTPUT_QUIET ERROR_QUIET)
            if(rc EQUAL 0)
                set(tagged TRUE)
            endif()
        endif()
        if(tagged)
            execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${dir}" show "v${min}:dvv-deps.txt"
                            RESULT_VARIABLE rc OUTPUT_VARIABLE text ERROR_QUIET)
            if(NOT rc EQUAL 0)
                add_error("${dep} tag v${min} at ${dir} has no dvv-deps.txt (a broken release of ${dep})")
                continue()
            endif()
            set(at "${dep} ${min}")
            set(text_args TEXT "${text}")
            set(where "${where} at tag v${min}")
        else()
            string(CONCAT above "${dep} ${dep_version} at ${dir} (above the minimum ${min} of "
                                "${REPO}, no tag v${min} there)")
        endif()
    endif()
    dvv_read_deps_file("${dep}" "${where}" dep ${text_args} ERROR_VARIABLE parse_error)
    if(NOT parse_error STREQUAL "")
        add_error("${at} has no valid dvv-deps.txt (a broken release of ${dep}): ${parse_error}")
        continue()
    endif()
    # Each check is <x>|<the library's minimum>|<the dependency's minimum>.
    set(checks "dvv-build|${lib_build_min}|${dep_build_min}")
    foreach(x IN LISTS dep_repos)
        set(line "${x} ${dep_min_${x}}")
        if(NOT dep_commit_${x} STREQUAL "")
            set(line "${line} @${dep_commit_${x}}")
        endif()
        if(NOT x IN_LIST lib_repos)
            if(NOT above STREQUAL "")
                add_error("${above} needs ${x}, which ${REPO}/dvv-deps.txt does not list: check out ${dep} "
                          "v${min} or add '${line}' before the ${dep} line")
            else()
                add_error("${at} needs ${x}, which ${REPO}/dvv-deps.txt does not list: add '${line}' "
                          "before the ${dep} line")
            endif()
            continue()
        endif()
        # A dependency's own override must be repeated exactly (the clones are shallow, so no ancestry
        # check): the library then carries it as a direct override, which check-pins rejects.
        if(NOT dep_commit_${x} STREQUAL "" AND NOT lib_commit_${x} STREQUAL dep_commit_${x})
            add_error("${at} overrides ${x} with ${dep_commit_${x}}: add ' @${dep_commit_${x}}' to the ${x} "
                      "line of ${REPO}/dvv-deps.txt")
        endif()
        list(APPEND checks "${x}|${lib_min_${x}}|${dep_min_${x}}")
    endforeach()
    foreach(check IN LISTS checks)
        string(REPLACE "|" ";" check "${check}")
        list(GET check 0 x)
        list(GET check 1 lib_min)
        list(GET check 2 dep_min)
        dvv_version_meets(ok "${lib_min}" "${dep_min}")
        if(ok)
            continue()
        endif()
        string(REGEX MATCH "^[0-9]+" lib_major "${lib_min}")
        string(REGEX MATCH "^[0-9]+" dep_major "${dep_min}")
        if(NOT lib_major EQUAL dep_major)
            add_error("${at} is built for ${x} ${dep_major}.x, ${REPO} needs ${x} ${lib_major}.x: use a "
                      "${dep} release for ${x} ${lib_major}.x")
        elseif(NOT above STREQUAL "")
            add_error("${above} needs ${x} >= ${dep_min}: check out ${dep} v${min} or raise the ${x} line "
                      "of ${REPO}/dvv-deps.txt")
        else()
            add_error("${at} needs ${x} >= ${dep_min}: raise the ${x} line of ${REPO}/dvv-deps.txt")
        endif()
    endforeach()
endforeach()

if(errors)
    list(JOIN errors "\n  " text)
    message(FATAL_ERROR "fetch-deps for ${REPO} failed:\n  ${text}")
endif()
message(STATUS "fetch-deps: ${REPO}: all dvv dependencies present in ${root}")
