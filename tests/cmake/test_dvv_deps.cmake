# Tests cmake/DvvDeps.cmake (dvv_dependencies()) against a fixture dvv root built in WORK_DIR:
#   <root>/dvv-build   stub: VERSION and copies of DvvDeps.cmake and DvvDepsFile.cmake
#   <root>/dvv-alpha   fake lib, needs dvv-build
#   <root>/dvv-beta    fake lib, needs dvv-build and dvv-alpha (a dep that calls dvv_dependencies())
#   <root>/dvv-gamma   fake lib, needs all of them; it is the configured top level (lib layout)
# In the app layout (APP) the top level is <case>/app (project fakeapp) and the root is <case>/app/libs.
# Each case configures the top level (LANGUAGES NONE) and checks the result and the messages.
#   cmake -DWORK_DIR=<dir> -DGENERATOR=<generator> [-DPLATFORM=<platform>] [-DMAKE_PROGRAM=<path>]
#         [-DDVV_DEPS=<DvvDeps.cmake>] -P test_dvv_deps.cmake
cmake_minimum_required(VERSION 4.2)

foreach(var IN ITEMS WORK_DIR GENERATOR)
    if(NOT DEFINED ${var} OR "${${var}}" STREQUAL "")
        message(FATAL_ERROR "test_dvv_deps: -D${var}=... is required")
    endif()
endforeach()
file(TO_CMAKE_PATH "${WORK_DIR}" WORK_DIR)
if(NOT DEFINED DVV_DEPS)
    set(DVV_DEPS "${CMAKE_CURRENT_LIST_DIR}/../../cmake/DvvDeps.cmake")
endif()
if(NOT EXISTS "${DVV_DEPS}")
    message(FATAL_ERROR "test_dvv_deps: ${DVV_DEPS} does not exist")
endif()
# DvvDeps.cmake includes the shared reader next to it.
cmake_path(GET DVV_DEPS PARENT_PATH DVV_DEPS_FILE)
set(DVV_DEPS_FILE "${DVV_DEPS_FILE}/DvvDepsFile.cmake")

# Writes the fake project <name> in <dir> with project version <version> ("none": no VERSION);
# ARGN = its dvv-deps.txt lines. The top level records its variables right before dvv_dependencies();
# each dependency reports, as leaked=[...], the variables it starts with beyond those, except
# CMake's and FetchContent's own and the _dvv_deps_ prefix. The top level reports, as leaked=[...],
# what dvv_dependencies() gave back beyond its documented results.
function(fixture_project dir name version call_args)
    set(deps "# dvv dependencies: <repository> <minimum version>, dependency order (read by dvv-build).\n")
    foreach(line IN LISTS ARGN)
        string(APPEND deps "${line}\n")
    endforeach()
    file(WRITE "${dir}/dvv-deps.txt" "${deps}")
    if(version STREQUAL "none")
        set(project_version "")
    else()
        set(project_version "VERSION ${version}")
    endif()
    file(WRITE "${dir}/CMakeLists.txt" "cmake_minimum_required(VERSION 4.2)
get_property(_fx_top_vars GLOBAL PROPERTY fx_top_vars)
set(_fx_leaked \"\")
if(_fx_top_vars)
    get_cmake_property(_fx_leaked VARIABLES)
    list(REMOVE_ITEM _fx_leaked \${_fx_top_vars})
    list(FILTER _fx_leaked EXCLUDE REGEX \"^(_dvv_deps_|_fx_|CMAKE_|FETCHCONTENT_|_?FetchContent_|__cmake|ARG[VNC])\")
    # FetchContent's and project()'s own results for the deps added before this one.
    list(FILTER _fx_leaked EXCLUDE REGEX \"^dvv_[a-z]+_(SOURCE_DIR|BINARY_DIR|POPULATED|IS_TOP_LEVEL)$\")
endif()
project(${name} ${project_version} LANGUAGES NONE)
option(DVV_BUILD_TESTS \"Build the tests\" \${PROJECT_IS_TOP_LEVEL})
include(\"\${DVV_BUILD_CMAKE_DIR}/DvvDeps.cmake\")
if(PROJECT_IS_TOP_LEVEL)
    get_cmake_property(_fx_vars VARIABLES)
    set_property(GLOBAL PROPERTY fx_top_vars \"\${_fx_vars}\")
endif()
dvv_dependencies(${call_args})
if(PROJECT_IS_TOP_LEVEL)
    # The caller gets DVV_BUILD_VERSION and dvv_<x>_MIN_VERSION|SOURCE_DIR|BINARY_DIR back, nothing else.
    get_cmake_property(_fx_leaked VARIABLES)
    list(REMOVE_ITEM _fx_leaked \${_fx_vars})
    list(FILTER _fx_leaked EXCLUDE REGEX \"^(_fx_|CMAKE_|FETCHCONTENT_|DVV_BUILD_VERSION$)\")
    list(FILTER _fx_leaked EXCLUDE REGEX \"^dvv_[a-z]+_(MIN_VERSION|SOURCE_DIR|BINARY_DIR|IS_TOP_LEVEL)$\")
endif()
get_property(configure_deps DIRECTORY PROPERTY CMAKE_CONFIGURE_DEPENDS)
message(STATUS \"fixture: ${name} tests=\${DVV_BUILD_TESTS} leaked=[\${_fx_leaked}] build_ver=[\${DVV_BUILD_VERSION}] alpha_min=[\${dvv_alpha_MIN_VERSION}] alpha_src=[\${dvv_alpha_SOURCE_DIR}] configure_deps=[\${configure_deps}]\")
")
endfunction()

# Writes the fake lib <root>/<repo>; ARGN = its dvv-deps.txt lines.
function(fixture_lib root repo version)
    string(REPLACE "-" "_" name "${repo}")
    fixture_project("${root}/${repo}" ${name} ${version} "" ${ARGN})
endfunction()

# run_case(<name> [FAIL] [APP] [NO_DEPS_FILE] [ALPHA_COPY] [BUILD_VERSION v] [ALPHA_VERSION v|none]
#          [BETA lib|missing|empty] [CALL_ARGS arg] [TOP_DEPS lines...] [BETA_DEPS lines...]
#          [ARGS cmake args...] [EXPECT regexes...] [EXPECT_ONCE regexes...] [EXPECT_NONE regexes...])
# The top level is dvv-gamma in <case>/root, or with APP fakeapp in <case>/app (root <case>/app/libs).
# ALPHA_COPY writes a second dvv-alpha 0.1.1 at <case>/other/dvv-alpha.
function(run_case name)
    cmake_parse_arguments(PARSE_ARGV 1 arg "FAIL;APP;NO_DEPS_FILE;ALPHA_COPY"
                          "BUILD_VERSION;ALPHA_VERSION;BETA;CALL_ARGS"
                          "TOP_DEPS;BETA_DEPS;ARGS;EXPECT;EXPECT_ONCE;EXPECT_NONE")
    if(NOT arg_BUILD_VERSION)
        set(arg_BUILD_VERSION 0.1.3)
    endif()
    if(NOT arg_ALPHA_VERSION)
        set(arg_ALPHA_VERSION 0.1.0)
    endif()
    if(NOT arg_BETA)
        set(arg_BETA lib)
    endif()
    if(NOT arg_TOP_DEPS)
        set(arg_TOP_DEPS "dvv-build 0.1.0" "dvv-alpha 0.1.0" "dvv-beta 0.1.0")
    endif()
    if(NOT arg_BETA_DEPS)
        set(arg_BETA_DEPS "dvv-build 0.1.0" "dvv-alpha 0.1.0")
    endif()

    set(dir "${WORK_DIR}/${name}")
    if(arg_APP)
        set(root "${dir}/app/libs")
        set(top "${dir}/app")
    else()
        set(root "${dir}/root")
        set(top "${root}/dvv-gamma")
    endif()
    file(REMOVE_RECURSE "${dir}")
    file(WRITE "${root}/dvv-build/VERSION" "${arg_BUILD_VERSION}\n")
    file(MAKE_DIRECTORY "${root}/dvv-build/cmake")
    file(COPY_FILE "${DVV_DEPS}" "${root}/dvv-build/cmake/DvvDeps.cmake")
    file(COPY_FILE "${DVV_DEPS_FILE}" "${root}/dvv-build/cmake/DvvDepsFile.cmake")
    fixture_lib("${root}" dvv-alpha ${arg_ALPHA_VERSION} "dvv-build 0.1.0")
    if(arg_ALPHA_COPY)
        fixture_lib("${dir}/other" dvv-alpha 0.1.1 "dvv-build 0.1.0")
    endif()
    if(arg_BETA STREQUAL "lib")
        fixture_lib("${root}" dvv-beta 0.1.0 ${arg_BETA_DEPS})
    elseif(arg_BETA STREQUAL "empty")
        file(MAKE_DIRECTORY "${root}/dvv-beta")
    endif()
    if(arg_APP)
        fixture_project("${top}" fakeapp 0.9.0 "${arg_CALL_ARGS}" ${arg_TOP_DEPS})
    else()
        fixture_project("${top}" dvv_gamma 0.1.0 "${arg_CALL_ARGS}" ${arg_TOP_DEPS})
    endif()
    if(arg_NO_DEPS_FILE)
        file(REMOVE "${top}/dvv-deps.txt")
    endif()

    set(cmd "${CMAKE_COMMAND}" -S "${top}" -B "${dir}/build" -G "${GENERATOR}")
    if(PLATFORM)
        list(APPEND cmd -A "${PLATFORM}")
    endif()
    if(MAKE_PROGRAM AND GENERATOR MATCHES "Ninja")
        list(APPEND cmd "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}")
    endif()
    list(APPEND cmd "-DDVV_BUILD_CMAKE_DIR=${root}/dvv-build/cmake" -DDVV_BUILD_TESTS=ON ${arg_ARGS})
    execute_process(COMMAND ${cmd} RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE out)
    # CMake wraps long messages ("\n  "); join them so a phrase matches across a wrap.
    string(REGEX REPLACE "\n +" " " flat "${out}")

    set(problems "")
    if(arg_FAIL AND rc EQUAL 0)
        string(APPEND problems "\n  configure succeeded, expected a failure")
    elseif(NOT arg_FAIL AND NOT rc EQUAL 0)
        string(APPEND problems "\n  configure failed (${rc}), expected success")
    endif()
    foreach(re IN LISTS arg_EXPECT)
        if(NOT flat MATCHES "${re}")
            string(APPEND problems "\n  missing: ${re}")
        endif()
    endforeach()
    # (Not REGEX MATCHALL: a match that holds a ';' would count as two list items.)
    foreach(re IN LISTS arg_EXPECT_ONCE)
        if(NOT flat MATCHES "${re}")
            string(APPEND problems "\n  expected once, found 0: ${re}")
            continue()
        endif()
        string(FIND "${flat}" "${CMAKE_MATCH_0}" pos)
        string(LENGTH "${CMAKE_MATCH_0}" len)
        math(EXPR pos "${pos} + ${len}")
        string(SUBSTRING "${flat}" ${pos} -1 rest)
        if(rest MATCHES "${re}")
            string(APPEND problems "\n  expected once, found more: ${re}")
        endif()
    endforeach()
    foreach(re IN LISTS arg_EXPECT_NONE)
        if(flat MATCHES "${re}")
            string(APPEND problems "\n  unexpected: ${CMAKE_MATCH_0}")
        endif()
    endforeach()
    if(problems)
        message("test_dvv_deps: case ${name} FAILED:${problems}\n--- output ---\n${out}--- end ---")
        set_property(GLOBAL APPEND PROPERTY test_dvv_deps_failed "${name}")
    else()
        message(STATUS "test_dvv_deps: case ${name} passed")
    endif()
endfunction()

string(CONCAT fetch_hint "lib: run `cmake -DREPO=dvv-gamma -P dvv-build/tools/fetch-deps\\.cmake` "
                         "in [^;]*/root; app: run `git submodule update --init` in the app")
string(CONCAT version_hint "put a 0\\.x version >= [0-9.]+ there \\(lib: check out that tag; app: move "
                           "the libs/ submodule\\) or change the minimum in dvv-[a-z]+'s dvv-deps\\.txt")

# All minimums met: each lib is configured once, the deps without tests, the top level with tests;
# DVV_BUILD_VERSION, dvv_<x>_MIN_VERSION and dvv_<x>_SOURCE_DIR reach the caller; no DvvDeps
# variable reaches the deps.
run_case(ok ARGS -DDVV_TEST_DEPENDENCIES=
    EXPECT_ONCE "fixture: dvv_alpha tests=OFF leaked=\\[\\] " "fixture: dvv_beta tests=OFF leaked=\\[\\] "
                "fixture: dvv_gamma tests=ON leaked=\\[\\] build_ver=\\[0\\.1\\.3\\] alpha_min=\\[0\\.1\\.0\\] alpha_src=\\[[^]]*/root/dvv-alpha\\] configure_deps=\\[[^]]*/dvv-gamma/dvv-deps\\.txt.[^]]*/dvv-build/VERSION\\]"
    EXPECT_NONE "leaked=\\[[^]]+\\]" "CMake Warning")
# DVV_TEST_DEPENDENCIES: the deps keep the tests.
run_case(test_dependencies ARGS -DDVV_TEST_DEPENDENCIES=ON
    EXPECT_ONCE "fixture: dvv_alpha tests=ON " "fixture: dvv_beta tests=ON " "fixture: dvv_gamma tests=ON ")
# App layout: the top level is outside the root and not a dvv project.
run_case(app APP
    EXPECT_ONCE "fixture: dvv_alpha tests=OFF leaked=\\[\\] " "fixture: dvv_beta tests=OFF leaked=\\[\\] "
                "fixture: fakeapp tests=ON leaked=\\[\\] build_ver=\\[0\\.1\\.3\\] alpha_min=\\[0\\.1\\.0\\] alpha_src=\\[[^]]*/app/libs/dvv-alpha\\]"
    EXPECT_NONE "leaked=\\[[^]]+\\]" "CMake Warning")
run_case(app_too_low FAIL APP TOP_DEPS "dvv-build 0.1.0" "dvv-alpha 0.2.0" "dvv-beta 0.1.0"
    EXPECT "fakeapp requires dvv-alpha >= 0\\.2\\.0 \\(same major\\), found 0\\.1\\.0 at [^ ]*/app/libs/dvv-alpha;")
# A dep folder is missing, or present but empty (an app clone without --recursive).
run_case(missing_folder FAIL BETA missing
    EXPECT "dvv-gamma needs dvv-beta: .*/dvv-beta is missing or empty; ${fetch_hint}")
run_case(empty_folder FAIL BETA empty
    EXPECT "dvv-gamma needs dvv-beta: .*/dvv-beta is missing or empty; ${fetch_hint}")
# A dep below the minimum, of another major version, or without a project version.
run_case(too_low FAIL TOP_DEPS "dvv-build 0.1.0" "dvv-alpha 0.2.0" "dvv-beta 0.1.0"
    EXPECT "dvv-gamma requires dvv-alpha >= 0\\.2\\.0 \\(same major\\), found 0\\.1\\.0 at .*/dvv-alpha; ${version_hint}")
run_case(other_major FAIL ALPHA_VERSION 1.0.0 BETA_DEPS "dvv-build 0.1.0"
    EXPECT "dvv-gamma requires dvv-alpha >= 0\\.1\\.0 \\(same major\\), found 1\\.0\\.0 at .*/dvv-alpha")
run_case(no_version FAIL ALPHA_VERSION none
    EXPECT "requires dvv-alpha >= 0\\.1\\.0 \\(same major\\), found no version \\(project\\(\\) without VERSION\\?\\) at .*/dvv-alpha")
# dvv-build below the minimum, or of another major version.
run_case(build_too_low FAIL TOP_DEPS "dvv-build 0.2.0" "dvv-alpha 0.1.0" "dvv-beta 0.1.0"
    EXPECT "dvv-gamma requires dvv-build >= 0\\.2\\.0 \\(same major\\), found 0\\.1\\.3 at .*/dvv-build; ${version_hint}")
run_case(build_other_major FAIL BUILD_VERSION 1.0.0
    EXPECT "dvv-gamma requires dvv-build >= 0\\.1\\.0 \\(same major\\), found 1\\.0\\.0 at .*/dvv-build")
# dvv-beta is a dep of dvv-gamma and calls dvv_dependencies() itself: its own minimums are checked
# against the versions the top level resolved.
run_case(nested_dep_too_low FAIL BETA_DEPS "dvv-build 0.1.0" "dvv-alpha 0.2.0"
    EXPECT "dvv-beta requires dvv-alpha >= 0\\.2\\.0 \\(same major\\), found 0\\.1\\.0 at .*/dvv-alpha")
# The strict file: a malformed line, no dvv-build line, a repo or dvv-build twice, the lib itself,
# no file at all. The dvv-build line may be anywhere.
run_case(build_line_last TOP_DEPS "dvv-alpha 0.1.0" "dvv-beta 0.1.0" "dvv-build 0.1.0"
    EXPECT_ONCE "fixture: dvv_gamma tests=ON ")
run_case(bad_line FAIL TOP_DEPS "dvv-build 0.1.0" "dvv-alpha 0.1"
    EXPECT "dvv-deps\\.txt: bad line 'dvv-alpha 0\\.1' \\(expected 'dvv-<name> <major>\\.<minor>\\.<patch>'\\)")
run_case(no_build_line FAIL TOP_DEPS "dvv-alpha 0.1.0" "dvv-beta 0.1.0"
    EXPECT "dvv-gamma: [^ ]*/dvv-gamma/dvv-deps\\.txt has no dvv-build line; add 'dvv-build <minimum version>'")
run_case(duplicate FAIL TOP_DEPS "dvv-build 0.1.0" "dvv-alpha 0.1.0" "dvv-beta 0.1.0" "dvv-alpha 0.1.0"
    EXPECT "dvv-gamma: [^ ]*/dvv-deps\\.txt lists dvv-alpha twice; keep one line")
run_case(duplicate_build FAIL TOP_DEPS "dvv-build 9.9.9" "dvv-alpha 0.1.0" "dvv-build 0.1.0"
    EXPECT "dvv-gamma: [^ ]*/dvv-deps\\.txt lists dvv-build twice; keep one line")
run_case(self_listing FAIL TOP_DEPS "dvv-build 0.1.0" "dvv-alpha 0.1.0" "dvv-gamma 0.1.0"
    EXPECT "dvv-gamma: [^ ]*/dvv-deps\\.txt lists dvv-gamma itself; remove that line")
run_case(no_deps_file FAIL NO_DEPS_FILE
    EXPECT "dvv-gamma: [^ ]*/dvv-gamma/dvv-deps\\.txt does not exist; create it with a 'dvv-build <major>\\.<minor>\\.<patch>' line")
# dvv_dependencies() takes no arguments, not even a false one.
run_case(arguments FAIL CALL_ARGS OFF
    EXPECT "dvv_dependencies\\(\\) takes no arguments, got 'OFF'")
# An old FetchContent override takes dvv-alpha from a second copy: a warning (once), and the version
# check reads the copy in use.
run_case(override ALPHA_COPY ARGS "-DFETCHCONTENT_SOURCE_DIR_DVV_ALPHA=${WORK_DIR}/override/other/dvv-alpha"
    EXPECT_ONCE "FETCHCONTENT_SOURCE_DIR_DVV_ALPHA takes dvv-alpha from [^ ]*/override/other/dvv-alpha, not from [^ ]*/root/dvv-alpha \\(a second copy\\); remove it: `cmake -U FETCHCONTENT_SOURCE_DIR_DVV_ALPHA`"
                "fixture: dvv_gamma tests=ON leaked=\\[\\] build_ver=\\[0\\.1\\.3\\] alpha_min=\\[0\\.1\\.0\\] alpha_src=\\[[^]]*/other/dvv-alpha\\]")
# FETCHCONTENT_TRY_FIND_PACKAGE_MODE=ALWAYS with an installed dvv_alpha: a clear error.
file(WRITE "${WORK_DIR}/_package/dvv_alphaConfig.cmake" "")
run_case(installed_package FAIL ARGS -DFETCHCONTENT_TRY_FIND_PACKAGE_MODE=ALWAYS "-Ddvv_alpha_DIR=${WORK_DIR}/_package"
    EXPECT "dvv-gamma: FETCHCONTENT_TRY_FIND_PACKAGE_MODE=ALWAYS would take the dvv dependencies from installed packages, not from [^ ]*/root; remove it: `cmake -U FETCHCONTENT_TRY_FIND_PACKAGE_MODE`")

get_property(failed GLOBAL PROPERTY test_dvv_deps_failed)
if(failed)
    message(FATAL_ERROR "test_dvv_deps: failed cases: ${failed}")
endif()
message(STATUS "test_dvv_deps: all cases passed")
