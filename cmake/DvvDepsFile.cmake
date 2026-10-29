# DvvDepsFile.cmake: the one reader of dvv-deps.txt and the dvv version rule. Part of dvv-build.
# Included by DvvDeps.cmake, tools/fetch-deps.cmake and tools/check-pins.cmake, so all of them apply
# the same rules (the two tools also share its credential mask). Functions only: including it changes
# nothing else. CI reads the dvv-build line with bash before dvv-build is checked out
# (.github/workflows/dvv-ci.yml); that reader follows the same rules.
# The format of dvv-deps.txt:
#   # comment                            (blank lines are ignored too; a CR before the line end is dropped)
#   dvv-build <major>.<minor>.<patch>    minimum of dvv-build (its VERSION file), exactly once, anywhere
#   dvv-<x> <major>.<minor>.<patch>      minimum of each dvv dependency, once each, in dependency order
#   dvv-<x> <major>.<minor>.<patch> @<commit>
#                                        the same with a branch-only override: tools/fetch-deps.cmake
#                                        checks out <commit> (40 lowercase hex digits, one per line)
#                                        instead of tag v<minimum>; tools/check-pins.cmake rejects it
#                                        in lib and app mode, so it never reaches main. The dvv-build
#                                        line takes none.
# Any other line is an error, and a repository does not list itself.
include_guard(GLOBAL)

# dvv_read_deps_file(<who> <file> <prefix> [TEXT <content>] [ERROR_VARIABLE <var>])
# Reads <file> of the repository <who> (its folder name, e.g. dvv-gpu). With TEXT, parses <content>
# instead and names it <file> in the messages. Sets in the caller <prefix>_build_min (the dvv-build
# minimum), <prefix>_repos (the dvv libraries in file order), <prefix>_min_<repo> and
# <prefix>_commit_<repo> (the override commit, else empty) for each of them, and <prefix>_overrides
# (the libraries with an override). A problem is a FATAL_ERROR; with ERROR_VARIABLE it is stored in
# <var> instead (empty when the file is valid) and <prefix>_build_min, <prefix>_repos and
# <prefix>_overrides are empty.
function(dvv_read_deps_file who file prefix)
    cmake_parse_arguments(PARSE_ARGV 3 arg "" "TEXT;ERROR_VARIABLE" "")
    if(arg_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "dvv_read_deps_file(): unknown arguments '${arg_UNPARSED_ARGUMENTS}'")
    endif()
    set(error "")
    set(build_min "")
    set(repos "")
    set(overrides "")
    if(DEFINED arg_TEXT)
        string(REPLACE "\r" "" text "${arg_TEXT}")
        string(REPLACE "\n" ";" lines "${text}")
    elseif(NOT EXISTS "${file}")
        string(CONCAT error "${who}: ${file} does not exist; create it with a 'dvv-build "
                            "<major>.<minor>.<patch>' line and one 'dvv-<x> <version>' line per dvv dependency")
        set(lines "")
    else()
        file(STRINGS "${file}" lines)
    endif()
    foreach(line IN LISTS lines)
        string(REPLACE "\r" "" line "${line}")
        string(STRIP "${line}" line)
        if(line STREQUAL "" OR line MATCHES "^#")
            continue()
        endif()
        if(NOT line MATCHES "^(dvv-[a-z0-9-]+)[ \t]+([0-9]+\\.[0-9]+\\.[0-9]+)([ \t]+@.*)?$")
            set(error "${who}: ${file}: bad line '${line}' (expected 'dvv-<name> <major>.<minor>.<patch> [@<commit>]')")
            break()
        endif()
        set(repo "${CMAKE_MATCH_1}")
        set(min "${CMAKE_MATCH_2}")
        string(STRIP "${CMAKE_MATCH_3}" override)
        set(commit "")
        if(NOT override STREQUAL "")
            string(LENGTH "${override}" length)
            if(NOT override MATCHES "^@[0-9a-f]+$" OR NOT length EQUAL 41)
                string(CONCAT error "${who}: ${file}: bad override '${override}' in line '${line}' "
                                    "(expected one ' @<commit>' after the version: 40 lowercase hex digits)")
                break()
            elseif(repo STREQUAL "dvv-build")
                string(CONCAT error "${who}: ${file}: the dvv-build line takes no override (CI checks out "
                                    "dvv-build at tag v${min}); remove '${override}'")
                break()
            endif()
            string(SUBSTRING "${override}" 1 -1 commit)
        endif()
        if(repo STREQUAL who)
            set(error "${who}: ${file} lists ${repo} itself; remove that line")
            break()
        elseif(repo IN_LIST repos OR (repo STREQUAL "dvv-build" AND NOT build_min STREQUAL ""))
            set(error "${who}: ${file} lists ${repo} twice; keep one line")
            break()
        elseif(repo STREQUAL "dvv-build")
            set(build_min "${min}")
        else()
            list(APPEND repos "${repo}")
            set(min_${repo} "${min}")
            set(commit_${repo} "${commit}")
            if(NOT commit STREQUAL "")
                list(APPEND overrides "${repo}")
            endif()
        endif()
    endforeach()
    if(error STREQUAL "" AND build_min STREQUAL "" AND (DEFINED arg_TEXT OR EXISTS "${file}"))
        set(error "${who}: ${file} has no dvv-build line; add 'dvv-build <minimum version>'")
    endif()
    if(NOT error STREQUAL "")
        if(NOT DEFINED arg_ERROR_VARIABLE)
            message(FATAL_ERROR "${error}")
        endif()
        set(${arg_ERROR_VARIABLE} "${error}" PARENT_SCOPE)
        set(${prefix}_build_min "" PARENT_SCOPE)
        set(${prefix}_repos "" PARENT_SCOPE)
        set(${prefix}_overrides "" PARENT_SCOPE)
        return()
    endif()
    if(DEFINED arg_ERROR_VARIABLE)
        set(${arg_ERROR_VARIABLE} "" PARENT_SCOPE)
    endif()
    foreach(repo IN LISTS repos)
        set(${prefix}_min_${repo} "${min_${repo}}" PARENT_SCOPE)
        set(${prefix}_commit_${repo} "${commit_${repo}}" PARENT_SCOPE)
    endforeach()
    set(${prefix}_overrides "${overrides}" PARENT_SCOPE)
    set(${prefix}_build_min "${build_min}" PARENT_SCOPE)
    set(${prefix}_repos "${repos}" PARENT_SCOPE)
endfunction()

# dvv_version_meets(<out> <found> <min>): TRUE when <found> has the major of <min> and is >= <min>.
function(dvv_version_meets out found min)
    string(REGEX MATCH "^[0-9]+" min_major "${min}")
    string(REGEX MATCH "^[0-9]+" found_major "${found}")
    if(NOT found STREQUAL "" AND found_major EQUAL min_major AND found VERSION_GREATER_EQUAL min)
        set(${out} TRUE PARENT_SCOPE)
    else()
        set(${out} FALSE PARENT_SCOPE)
    endif()
endfunction()

# dvv_project_version(<out> <repo> <text>): the VERSION of project(dvv_<x> ...) in <text>, the
# CMakeLists.txt of the repository <repo> (dvv-<x>), or "" when there is none.
function(dvv_project_version out repo text)
    string(REPLACE "-" "_" id "${repo}")
    if(text MATCHES "project[ \t]*[(][ \t\r\n]*${id}[ \t\r\n]+VERSION[ \t\r\n]+([0-9]+\\.[0-9]+\\.[0-9]+)")
        set(${out} "${CMAKE_MATCH_1}" PARENT_SCOPE)
    else()
        set(${out} "" PARENT_SCOPE)
    endif()
endfunction()

# dvv_hide_credentials(<out> <text>): <text> with the credentials of every URL in it removed
# ("://user:token@" becomes "://"). Used by tools/fetch-deps.cmake and tools/check-pins.cmake for
# URLs and for git's output; the user part never spans '/', '@' or white space.
function(dvv_hide_credentials out text)
    string(REGEX REPLACE "://[^/@ \t\r\n]+@" "://" text "${text}")
    set(${out} "${text}" PARENT_SCOPE)
endfunction()
