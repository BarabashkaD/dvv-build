# dvv_dependencies(): adds the dvv dependencies of the calling repository. Part of dvv-build.
# A dvv library or the app includes this file from DVV_BUILD_CMAKE_DIR (set by the dvv presets) and
# calls dvv_dependencies() right after project(). It reads ${PROJECT_SOURCE_DIR}/dvv-deps.txt:
#   # comment
#   dvv-build <major>.<minor>.<patch>    minimum of this dvv-build (its VERSION file), exactly once
#   dvv-<x> <major>.<minor>.<patch>      minimum of each dvv dependency, in dependency order
# A ' @<commit>' after a dvv-<x> version (a branch-only override, see DvvDepsFile.cmake) changes
# nothing here: the folder <root>/dvv-<x> is used as it is, and its version is checked as usual.
# The dvv-build line may be anywhere in the file. A repository does not list itself.
# The dvv root is the folder holding this dvv-build: the parent folder of a library (lib layout) or
# <app>/libs (app layout). Every dependency is the folder <root>/dvv-<x>; the first declaration of a
# dependency wins, so inside the app every library resolves to the one copy in libs/. A
# FETCHCONTENT_SOURCE_DIR_DVV_<X> that points elsewhere gives a warning (it breaks the one-copy rule);
# FETCHCONTENT_TRY_FIND_PACKAGE_MODE=ALWAYS is an error.
# For each dependency it then checks the version (project(dvv_<x> VERSION ...)) against the minimum:
# same major and >= the minimum. A library added as a dependency calls dvv_dependencies() again,
# which adds nothing new and checks that library's minimums against the versions already resolved.
# So the rule "a repository's minimum for X >= the minimum for X of each of its dvv dependencies" is
# enforced here only through the resolved versions; fetch-deps.cmake checks the minimums themselves.
# The top level builds its dependencies without tests unless DVV_TEST_DEPENDENCIES is set.
# Sets in the caller: DVV_BUILD_VERSION, and per dependency dvv_<x>_MIN_VERSION (for the package
# config templates), dvv_<x>_SOURCE_DIR and dvv_<x>_BINARY_DIR.
# The dependencies are added inside the function, so they start with its variables; all of them use
# the _dvv_deps_ prefix. The one variable meant to reach them is DVV_BUILD_TESTS.
# dvv-deps.txt is read by DvvDepsFile.cmake, the reader shared with tools/fetch-deps.cmake and
# tools/check-pins.cmake.
include_guard(GLOBAL)
include(FetchContent)
include("${CMAKE_CURRENT_LIST_DIR}/DvvDepsFile.cmake")

# Fails unless <found> has the major of <min> and is >= <min>.
function(_dvv_deps_check who what found min where)
    string(REGEX MATCH "^[0-9]+" min_major "${min}")
    if(found STREQUAL "")
        set(found "no version (project() without VERSION?)")
    else()
        dvv_version_meets(ok "${found}" "${min}")
        if(ok)
            return()
        endif()
    endif()
    message(FATAL_ERROR "${who} requires ${what} >= ${min} (same major), found ${found} at ${where}; "
                        "put a ${min_major}.x version >= ${min} there (lib: check out that tag; app: "
                        "move the libs/ submodule) or change the minimum in ${who}'s dvv-deps.txt")
endfunction()

function(dvv_dependencies)
    if(ARGC GREATER 0)
        message(FATAL_ERROR "dvv_dependencies() takes no arguments, got '${ARGV}'")
    endif()
    cmake_path(GET CMAKE_CURRENT_FUNCTION_LIST_DIR PARENT_PATH _dvv_deps_build_dir)
    cmake_path(GET _dvv_deps_build_dir PARENT_PATH _dvv_deps_root)
    string(REPLACE "_" "-" _dvv_deps_who "${PROJECT_NAME}")
    set(_dvv_deps_file "${PROJECT_SOURCE_DIR}/dvv-deps.txt")
    # Sets _dvv_deps_build_min, _dvv_deps_repos and _dvv_deps_min_<repo>; fails on a missing or bad file.
    dvv_read_deps_file("${_dvv_deps_who}" "${_dvv_deps_file}" _dvv_deps)
    # A changed minimum or dvv-build version re-runs the configure.
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
                 "${_dvv_deps_file}" "${_dvv_deps_build_dir}/VERSION")

    set(_dvv_deps_build_version "")
    if(EXISTS "${_dvv_deps_build_dir}/VERSION")
        file(STRINGS "${_dvv_deps_build_dir}/VERSION" _dvv_deps_build_version LIMIT_COUNT 1)
        string(STRIP "${_dvv_deps_build_version}" _dvv_deps_build_version)
    endif()
    _dvv_deps_check("${_dvv_deps_who}" dvv-build "${_dvv_deps_build_version}" "${_dvv_deps_build_min}"
                    "${_dvv_deps_build_dir}")
    set(DVV_BUILD_VERSION "${_dvv_deps_build_version}" PARENT_SCOPE)

    # The folders first: FetchContent's own error for a missing SOURCE_DIR does not say what to do.
    string(REPLACE "_" "-" _dvv_deps_top "${CMAKE_PROJECT_NAME}")
    set(_dvv_deps_names "")
    foreach(_dvv_deps_repo IN LISTS _dvv_deps_repos)
        set(_dvv_deps_src "${_dvv_deps_root}/${_dvv_deps_repo}")
        if(NOT IS_DIRECTORY "${_dvv_deps_src}" OR NOT EXISTS "${_dvv_deps_src}/CMakeLists.txt")
            message(FATAL_ERROR "${_dvv_deps_who} needs ${_dvv_deps_repo}: ${_dvv_deps_src} is missing or "
                                "empty; lib: run `cmake -DREPO=${_dvv_deps_top} -P dvv-build/tools/fetch-deps.cmake` "
                                "in ${_dvv_deps_root}; app: run `git submodule update --init` in the app")
        endif()
        string(REPLACE "-" "_" _dvv_deps_name "${_dvv_deps_repo}")
        string(TOUPPER "${_dvv_deps_name}" _dvv_deps_upper)
        set(_dvv_deps_override "${FETCHCONTENT_SOURCE_DIR_${_dvv_deps_upper}}")
        get_property(_dvv_deps_warned GLOBAL PROPERTY _dvv_deps_warned_${_dvv_deps_name})
        if(NOT _dvv_deps_override STREQUAL "" AND NOT _dvv_deps_warned)
            file(REAL_PATH "${_dvv_deps_override}" _dvv_deps_override)
            file(REAL_PATH "${_dvv_deps_src}" _dvv_deps_real)
            if(NOT _dvv_deps_override STREQUAL _dvv_deps_real)
                set_property(GLOBAL PROPERTY _dvv_deps_warned_${_dvv_deps_name} TRUE)
                message(WARNING "${_dvv_deps_who}: FETCHCONTENT_SOURCE_DIR_${_dvv_deps_upper} takes "
                                "${_dvv_deps_repo} from ${_dvv_deps_override}, not from ${_dvv_deps_src} "
                                "(a second copy); remove it: `cmake -U FETCHCONTENT_SOURCE_DIR_${_dvv_deps_upper}`")
            endif()
        endif()
        FetchContent_Declare(${_dvv_deps_name} SOURCE_DIR "${_dvv_deps_src}")
        list(APPEND _dvv_deps_names ${_dvv_deps_name})
    endforeach()

    # ALWAYS would take the deps from installed packages instead of <root>, and the version check
    # below would then fail with a cryptic error.
    if(_dvv_deps_names AND FETCHCONTENT_TRY_FIND_PACKAGE_MODE STREQUAL "ALWAYS")
        message(FATAL_ERROR "${_dvv_deps_who}: FETCHCONTENT_TRY_FIND_PACKAGE_MODE=ALWAYS would take the "
                            "dvv dependencies from installed packages, not from ${_dvv_deps_root}; "
                            "remove it: `cmake -U FETCHCONTENT_TRY_FIND_PACKAGE_MODE`")
    endif()
    # This normal variable reaches the dependencies' option(DVV_BUILD_TESTS) and ends with the function.
    if(PROJECT_IS_TOP_LEVEL AND NOT DVV_TEST_DEPENDENCIES)
        set(DVV_BUILD_TESTS OFF)
    endif()
    if(_dvv_deps_names)
        FetchContent_MakeAvailable(${_dvv_deps_names})
    endif()

    foreach(_dvv_deps_repo IN LISTS _dvv_deps_repos)
        string(REPLACE "-" "_" _dvv_deps_name "${_dvv_deps_repo}")
        FetchContent_GetProperties(${_dvv_deps_name} SOURCE_DIR _dvv_deps_src BINARY_DIR _dvv_deps_bin)
        get_directory_property(_dvv_deps_found DIRECTORY "${_dvv_deps_src}"
                               DEFINITION ${_dvv_deps_name}_VERSION)
        _dvv_deps_check("${_dvv_deps_who}" "${_dvv_deps_repo}" "${_dvv_deps_found}"
                        "${_dvv_deps_min_${_dvv_deps_repo}}" "${_dvv_deps_src}")
        message(VERBOSE "${_dvv_deps_who}: ${_dvv_deps_repo} ${_dvv_deps_found} at ${_dvv_deps_src} "
                        "(minimum ${_dvv_deps_min_${_dvv_deps_repo}})")
        set(${_dvv_deps_name}_MIN_VERSION "${_dvv_deps_min_${_dvv_deps_repo}}" PARENT_SCOPE)
        set(${_dvv_deps_name}_SOURCE_DIR "${_dvv_deps_src}" PARENT_SCOPE)
        set(${_dvv_deps_name}_BINARY_DIR "${_dvv_deps_bin}" PARENT_SCOPE)
    endforeach()
endfunction()
