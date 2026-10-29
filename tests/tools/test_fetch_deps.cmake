# Tests for tools/fetch-deps.cmake with local bare repositories and tags in WORK_DIR (no network).
# Run: cmake -DWORK_DIR=<scratch dir> -P tests/tools/test_fetch_deps.cmake
cmake_minimum_required(VERSION 4.2)
if(NOT DEFINED WORK_DIR)
    message(FATAL_ERROR "pass -DWORK_DIR=<scratch directory>")
endif()
find_program(GIT_EXECUTABLE git REQUIRED)
set(script "${CMAKE_CURRENT_LIST_DIR}/../../tools/fetch-deps.cmake")
set(parser "${CMAKE_CURRENT_LIST_DIR}/../../cmake/DvvDepsFile.cmake")
set(failures 0)
file(REMOVE_RECURSE "${WORK_DIR}")
file(MAKE_DIRECTORY "${WORK_DIR}")
set(remote "${WORK_DIR}/remote")
unset(ENV{DVV_GIT_BASE_URL})

function(run_git)
    execute_process(COMMAND "${GIT_EXECUTABLE}" ${ARGN} RESULT_VARIABLE rc OUTPUT_VARIABLE out
                    ERROR_VARIABLE err)
    if(NOT rc EQUAL 0)
        message(FATAL_ERROR "git ${ARGN} failed:\n${out}${err}")
    endif()
    string(STRIP "${out}" out)
    set(git_out "${out}" PARENT_SCOPE)
endfunction()

function(identity dir)
    run_git(-C "${dir}" config user.name test-user)
    run_git(-C "${dir}" config user.email test@users.noreply.github.com)
    run_git(-C "${dir}" config commit.gpgsign false)
    run_git(-C "${dir}" config tag.gpgsign false)
endfunction()

# release(<name> <version> <dvv-deps.txt>): commits a fake dvv repository at <version>, tags it
# v<version> and pushes both to the bare repository <remote>/<name>.
function(release name version deps)
    set(work "${WORK_DIR}/work/${name}")
    if(NOT EXISTS "${work}")
        run_git(init -q --bare -b main "${remote}/${name}")
        run_git(init -q -b main "${work}")
        identity("${work}")
        run_git(-C "${work}" remote add origin "${remote}/${name}")
    endif()
    string(REPLACE "-" "_" id "${name}")
    file(WRITE "${work}/CMakeLists.txt"
         "cmake_minimum_required(VERSION 4.2)\nproject(${id} VERSION ${version} LANGUAGES NONE)\n")
    file(WRITE "${work}/dvv-deps.txt" "${deps}")
    run_git(-C "${work}" add -A)
    run_git(-C "${work}" commit -q -m "${name} ${version}")
    run_git(-C "${work}" tag -a "v${version}" -m "${name} ${version}")
    run_git(-C "${work}" push -q origin main --tags)
endfunction()

# new_root(<case> <dvv-build version>): a dvv root <WORK_DIR>/<case> with a dvv-build holding the script.
function(new_root case build_version)
    set(dir "${WORK_DIR}/${case}")
    file(MAKE_DIRECTORY "${dir}/dvv-build/tools" "${dir}/dvv-build/cmake")
    file(COPY "${script}" DESTINATION "${dir}/dvv-build/tools")
    file(COPY "${parser}" DESTINATION "${dir}/dvv-build/cmake")
    file(WRITE "${dir}/dvv-build/VERSION" "${build_version}\n")
    set(root "${dir}" PARENT_SCOPE)
endfunction()

# new_lib(<name> <dvv-deps.txt> <origin or "">): the library <root>/<name>.
function(new_lib name deps origin)
    run_git(init -q -b main "${root}/${name}")
    if(NOT origin STREQUAL "")
        run_git(-C "${root}/${name}" remote add origin "${origin}")
    endif()
    file(WRITE "${root}/${name}/dvv-deps.txt" "${deps}")
endfunction()

# expect(<repo> <0|1 expected failure> <expected regex or ""> [<extra cmake arguments>...])
function(expect repo expect_failure expected_text)
    execute_process(COMMAND "${CMAKE_COMMAND}" "-DREPO=${repo}" ${ARGN}
                            -P "${root}/dvv-build/tools/fetch-deps.cmake"
                    WORKING_DIRECTORY "${root}" RESULT_VARIABLE status OUTPUT_VARIABLE out
                    ERROR_VARIABLE err)
    set(all "${out}${err}")
    string(REGEX REPLACE "[ \t\r\n]+" " " flat "${all}")
    set(last_out "${flat}" PARENT_SCOPE)
    if(expect_failure AND status EQUAL 0)
        message(SEND_ERROR "FAIL: expected fetch-deps to fail in ${root}\n${all}")
        set(failures 1 PARENT_SCOPE)
    elseif(NOT expect_failure AND NOT status EQUAL 0)
        message(SEND_ERROR "FAIL: expected fetch-deps to pass in ${root}\n${all}")
        set(failures 1 PARENT_SCOPE)
    elseif(NOT expected_text STREQUAL "" AND NOT flat MATCHES "${expected_text}")
        message(SEND_ERROR "FAIL: output in ${root} lacks '${expected_text}'\n${all}")
        set(failures 1 PARENT_SCOPE)
    endif()
endfunction()

function(expect_version dir version)
    file(READ "${dir}/CMakeLists.txt" text)
    if(NOT text MATCHES "VERSION ${version} ")
        message(SEND_ERROR "FAIL: ${dir} is not at ${version}")
        set(failures 1 PARENT_SCOPE)
    endif()
endfunction()

release(dvv-base 0.1.0 "dvv-build 0.1.0\n")
release(dvv-base 0.2.0 "dvv-build 0.1.0\n")
release(dvv-platform 0.1.0 "dvv-build 0.1.0\ndvv-base 0.1.0\n")
release(dvv-platform 0.2.0 "dvv-build 0.1.0\ndvv-base 0.2.0\n")
release(dvv-registry 0.1.0 "dvv-base 0.1.0\ndvv-build 0.2.0\n")
release(dvv-media 0.1.0 "dvv-build 0.1.0\ndvv-base 1.0.0\n")
release(dvv-nodeps 0.1.0 "")
# A broken release: tag v0.4.0 on a commit whose project() says 0.4.1.
set(work "${WORK_DIR}/work/dvv-base")
file(WRITE "${work}/CMakeLists.txt" "project(dvv_base VERSION 0.4.1 LANGUAGES NONE)\n")
run_git(-C "${work}" commit -q -am "dvv-base 0.4.1")
run_git(-C "${work}" tag -a v0.4.0 -m "mis-tagged")
run_git(-C "${work}" push -q origin main --tags)
if(remote MATCHES "^/")
    set(file_url "file://${remote}")
else()
    set(file_url "file:///${remote}")
endif()
# An untagged dvv-base 0.2.1 commit on a branch (not on main): the target of the branch-only overrides.
run_git(-C "${work}" checkout -q -b feature v0.2.0)
file(WRITE "${work}/CMakeLists.txt"
     "cmake_minimum_required(VERSION 4.2)\nproject(dvv_base VERSION 0.2.1 LANGUAGES NONE)\n")
run_git(-C "${work}" commit -q -am "dvv-base 0.2.1 on a branch")
run_git(-C "${work}" push -q origin feature)
run_git(-C "${work}" rev-parse HEAD)
set(feature_sha "${git_out}")
run_git(-C "${work}" checkout -q main)

# expect_absent(<regex>): the output of the last expect() does not match <regex>.
function(expect_absent regex)
    if(last_out MATCHES "${regex}")
        message(SEND_ERROR "FAIL: output in ${root} has '${regex}'\n${last_out}")
        set(failures 1 PARENT_SCOPE)
    endif()
endfunction()

# Clones at the minimum tags (not at the newest commit), base URL from the lib's origin; CRLF, a
# comment and the dvv-build line in the middle are accepted. A second run finds them present.
new_root(ok 0.1.0)
new_lib(dvv-gpu "# dvv dependencies\r\ndvv-base 0.1.0\r\ndvv-build 0.1.0\r\ndvv-platform 0.1.0\r\n"
        "${remote}/dvv-gpu.git")
expect(dvv-gpu 0 "dvv-base: cloned v0.1.0 from .*dvv-platform: cloned v0.1.0")
expect_version("${root}/dvv-base" 0.1.0)
expect_version("${root}/dvv-platform" 0.1.0)
expect(dvv-gpu 0 "dvv-base 0.1.0 present at .*dvv-platform 0.1.0 present at")

# DVV_GIT_BASE_URL as a -D argument and from the environment, for a lib without an origin.
new_root(base_arg 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.2.0\n" "")
expect(dvv-gpu 0 "dvv-base: cloned v0.2.0" "-DDVV_GIT_BASE_URL=${remote}")
expect_version("${root}/dvv-base" 0.2.0)
new_root(base_env 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.1.0\n" "")
set(ENV{DVV_GIT_BASE_URL} "${remote}/")
expect(dvv-gpu 0 "dvv-base: cloned v0.1.0")
unset(ENV{DVV_GIT_BASE_URL})

new_root(no_base 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.1.0\n" "")
expect(dvv-gpu 1 "has no origin.*DVV_GIT_BASE_URL")

new_root(no_tag 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.3.0\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "could not clone .*dvv-base at tag v0.3.0")
if(EXISTS "${root}/dvv-base")
    message(SEND_ERROR "FAIL: the failed clone left ${root}/dvv-base")
    set(failures 1)
endif()

# Over a URL (not a local path) the clone is shallow.
new_root(shallow 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.1.0\n" "")
expect(dvv-gpu 0 "dvv-base: cloned v0.1.0" "-DDVV_GIT_BASE_URL=${file_url}")
execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${root}/dvv-base" rev-parse --is-shallow-repository
                OUTPUT_VARIABLE shallow OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT shallow STREQUAL "true")
    message(SEND_ERROR "FAIL: ${root}/dvv-base is not a shallow clone ('${shallow}')")
    set(failures 1)
endif()

# Credentials in a base URL never reach the output (an unknown scheme fails without network).
new_root(secret 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.1.0\n" "")
expect(dvv-gpu 1 "could not clone nosuch://localhost/owner/dvv-base"
       "-DDVV_GIT_BASE_URL=nosuch://user:secret@localhost/owner")
expect_absent("secret")

# A lib whose only line is dvv-build (dvv-base) needs no origin and no base URL.
new_root(no_deps 0.1.0)
new_lib(dvv-base "dvv-build 0.1.0\n" "")
expect(dvv-base 0 "dvv-base: all dvv dependencies present")

# Two problems in one run: a missing tag and a dependency release without a valid dvv-deps.txt.
new_root(two_errors 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.3.0\ndvv-nodeps 0.1.0\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "could not clone .*dvv-base at tag v0.3.0.* dvv-nodeps 0.1.0 has no valid dvv-deps.txt \\(a broken release of dvv-nodeps\\): dvv-nodeps: .*has no dvv-build line")

# A tag v<min> must have exactly version <min>.
new_root(mis_tagged 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.4.0\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "dvv-base tag v0.4.0 from .* has project version '0.4.1', not 0.4.0")

# An existing dependency below the minimum is reported, not updated.
new_root(too_low 0.1.0)
run_git(clone -q --branch v0.1.0 "${remote}/dvv-base" "${root}/dvv-base")
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.2.0\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "dvv-gpu needs dvv-base >= 0.2.0 \\(same major\\), found 0.1.0 at")
new_root(other_major 0.1.0)
file(MAKE_DIRECTORY "${root}/dvv-base")
file(WRITE "${root}/dvv-base/CMakeLists.txt" "project(dvv_base VERSION 1.0.0 LANGUAGES NONE)\n")
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.1.0\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "needs dvv-base >= 0.1.0 \\(same major\\), found 1.0.0")
file(WRITE "${root}/dvv-base/CMakeLists.txt" "project(dvv_base LANGUAGES NONE)\n")
expect(dvv-gpu 1 "needs dvv-base >= 0.1.0 \\(same major\\), found no version")

# Transitive minimums: a dependency needs more than the lib states.
new_root(dep_needs_more 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.1.0\ndvv-platform 0.2.0\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "dvv-platform 0.2.0 needs dvv-base >= 0.2.0: raise the dvv-base line of dvv-gpu/dvv-deps.txt")
new_root(dep_needs_build 0.2.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.1.0\ndvv-registry 0.1.0\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "dvv-registry 0.1.0 needs dvv-build >= 0.2.0: raise the dvv-build line of dvv-gpu/dvv-deps.txt")
new_root(dep_not_listed 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-platform 0.1.0\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "dvv-platform 0.1.0 needs dvv-base, which dvv-gpu/dvv-deps.txt does not list")
new_root(lib_raises 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.2.0\ndvv-platform 0.1.0\n" "${remote}/dvv-gpu")
expect(dvv-gpu 0 "dvv-platform: cloned v0.1.0")
new_root(dep_major 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.1.0\ndvv-media 0.1.0\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "dvv-media 0.1.0 is built for dvv-base 1.x, dvv-gpu needs dvv-base 0.x: use a dvv-media release for dvv-base 0.x")
# A present dependency above the minimum is checked at its tag v<minimum> when it has that tag ...
new_root(above_min 0.1.0)
run_git(clone -q --branch v0.2.0 "${remote}/dvv-platform" "${root}/dvv-platform")
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.1.0\ndvv-platform 0.1.0\n" "${remote}/dvv-gpu")
expect(dvv-gpu 0 "dvv-platform 0.2.0 present at")
# ... else at the present version, with advice that fits.
new_root(above_min_no_tag 0.1.0)
file(WRITE "${root}/dvv-platform/CMakeLists.txt" "project(dvv_platform VERSION 0.2.0 LANGUAGES NONE)\n")
file(WRITE "${root}/dvv-platform/dvv-deps.txt" "dvv-build 0.1.0\ndvv-base 0.2.0\n")
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.1.0\ndvv-platform 0.1.0\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "dvv-platform 0.2.0 at .*dvv-platform \\(above the minimum 0.1.0 of dvv-gpu, no tag v0.1.0 there\\) needs dvv-base >= 0.2.0: check out dvv-platform v0.1.0 or raise the dvv-base line of dvv-gpu/dvv-deps.txt")
# ... also when the newer release added a dvv dependency the library does not list.
new_root(above_not_listed 0.1.0)
file(WRITE "${root}/dvv-platform/CMakeLists.txt" "project(dvv_platform VERSION 0.2.0 LANGUAGES NONE)\n")
file(WRITE "${root}/dvv-platform/dvv-deps.txt" "dvv-build 0.1.0\ndvv-base 0.1.0\ndvv-registry 0.1.0\n")
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.1.0\ndvv-platform 0.1.0\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "dvv-platform 0.2.0 at .*dvv-platform \\(above the minimum 0.1.0 of dvv-gpu, no tag v0.1.0 there\\) needs dvv-registry, which dvv-gpu/dvv-deps.txt does not list: check out dvv-platform v0.1.0 or add 'dvv-registry 0.1.0' before the dvv-platform line")
# A tag v<minimum> without dvv-deps.txt is a broken release, not a missing tag.
new_root(tag_no_deps_file 0.1.0)
set(dir "${root}/dvv-platform")
run_git(init -q -b main "${dir}")
identity("${dir}")
file(WRITE "${dir}/CMakeLists.txt" "project(dvv_platform VERSION 0.1.0 LANGUAGES NONE)\n")
run_git(-C "${dir}" add -A)
run_git(-C "${dir}" commit -q -m "dvv-platform 0.1.0 without dvv-deps.txt")
run_git(-C "${dir}" tag v0.1.0)
file(WRITE "${dir}/CMakeLists.txt" "project(dvv_platform VERSION 0.2.0 LANGUAGES NONE)\n")
file(WRITE "${dir}/dvv-deps.txt" "dvv-build 0.1.0\ndvv-base 0.1.0\n")
run_git(-C "${dir}" add -A)
run_git(-C "${dir}" commit -q -m "dvv-platform 0.2.0")
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.1.0\ndvv-platform 0.1.0\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "dvv-platform tag v0.1.0 at .*dvv-platform has no dvv-deps.txt \\(a broken release of dvv-platform\\)")
expect_absent("no tag v0.1.0 there")

# The dvv-build running the script is checked too.
new_root(build_low 0.1.0)
new_lib(dvv-gpu "dvv-build 0.2.0\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "dvv-gpu needs dvv-build >= 0.2.0 \\(same major\\), found 0.1.0")

# dvv-deps.txt errors (as DvvDeps.cmake) and bad arguments.
new_root(parse 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.1.0\ndvv-base 0.1.0\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "lists dvv-base twice")
file(WRITE "${root}/dvv-gpu/dvv-deps.txt" "dvv-build 0.1.0\ndvv-build 0.1.0\n")
expect(dvv-gpu 1 "lists dvv-build twice")
file(WRITE "${root}/dvv-gpu/dvv-deps.txt" "dvv-base 0.1.0\n")
expect(dvv-gpu 1 "has no dvv-build line")
file(WRITE "${root}/dvv-gpu/dvv-deps.txt" "dvv-build 0.1.0\ndvv-base 0.1\n")
expect(dvv-gpu 1 "bad line 'dvv-base 0.1'")
file(WRITE "${root}/dvv-gpu/dvv-deps.txt" "dvv-build 0.1.0\ndvv-gpu 0.1.0\n")
expect(dvv-gpu 1 "lists dvv-gpu itself")
expect(dvv-missing 1 "folder [^ ]*/dvv-missing does not exist")
expect("" 1 "pass -DREPO=")
foreach(bad "./dvv-gpu" "dvv-gpu/" "${root}/dvv-gpu" "..")
    expect("${bad}" 1 "REPO is the folder name of the library in ")
endforeach()

# One credential mask for both scripts: user:token@ goes; free text between a "://" and a later "@"
# (git's "use file:// instead" warnings) stays.
include("${parser}")
dvv_hide_credentials(shown "https://user:token@localhost/x, use file:// instead. see @mention\nssh://git@localhost/y")
if(NOT shown STREQUAL "https://localhost/x, use file:// instead. see @mention\nssh://localhost/y")
    message(SEND_ERROR "FAIL: dvv_hide_credentials gave '${shown}'")
    set(failures 1)
endif()
foreach(tool fetch-deps check-pins)
    file(READ "${CMAKE_CURRENT_LIST_DIR}/../../tools/${tool}.cmake" text)
    if(NOT text MATCHES "dvv_hide_credentials\\(" OR text MATCHES "REGEX REPLACE \"://")
        message(SEND_ERROR "FAIL: tools/${tool}.cmake does not mask credentials with dvv_hide_credentials()")
        set(failures 1)
    endif()
endforeach()

# Branch-only override ' @<commit>': exactly that commit is fetched (shallow over a URL) instead of the
# tag, its version only has to meet the minimum, the dependencies' minimums are read at that commit, and
# a second run accepts the folder at that commit.
new_root(override 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.2.0 @${feature_sha}\ndvv-platform 0.1.0\n" "")
expect(dvv-gpu 0 "dvv-base: checked out commit ${feature_sha} \\(version 0.2.1, override of v0.2.0\\) from file:.*dvv-platform: cloned v0.1.0"
       "-DDVV_GIT_BASE_URL=${file_url}")
expect_version("${root}/dvv-base" 0.2.1)
run_git(-C "${root}/dvv-base" rev-parse --is-shallow-repository)
if(NOT git_out STREQUAL "true")
    message(SEND_ERROR "FAIL: the override checkout of dvv-base is not shallow")
    set(failures 1)
endif()
expect(dvv-gpu 0 "dvv-base 0.2.1 present at .* at the override commit ${feature_sha} \\(minimum 0.2.0\\)"
       "-DDVV_GIT_BASE_URL=${file_url}")
# The commit's version is below the minimum.
new_root(override_too_low 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.3.0 @${feature_sha}\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "dvv-base commit ${feature_sha} from .* has project version '0.2.1', but dvv-gpu needs dvv-base >= 0.3.0 \\(same major\\)")
# A commit the origin does not have: a clear error, and no folder is left behind.
new_root(override_unknown 0.1.0)
set(unknown_sha "0123456789abcdef0123456789abcdef01234567")
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.2.0 @${unknown_sha}\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "could not check out dvv-base commit ${unknown_sha} \\(the override in dvv-gpu/dvv-deps.txt\\) from .*check the commit is pushed there")
if(EXISTS "${root}/dvv-base")
    message(SEND_ERROR "FAIL: a failed override checkout left ${root}/dvv-base behind")
    set(failures 1)
endif()
# An existing folder at another commit is reported, not updated.
new_root(override_mismatch 0.1.0)
run_git(clone -q --branch v0.2.0 "${remote}/dvv-base" "${root}/dvv-base")
run_git(-C "${root}/dvv-base" rev-parse HEAD)
set(tag_sha "${git_out}")
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.2.0 @${feature_sha}\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "dvv-gpu overrides dvv-base with commit ${feature_sha}, but .*/dvv-base is at ${tag_sha}: set the override to that folder's commit")
# The commit is checked before the version: an existing folder below the minimum on another commit gets
# the override advice, not the tag advice.
new_root(override_mismatch_low 0.1.0)
run_git(clone -q --branch v0.1.0 "${remote}/dvv-base" "${root}/dvv-base")
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.2.0 @${feature_sha}\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "dvv-gpu overrides dvv-base with commit ${feature_sha}, but .*/dvv-base is at [0-9a-f]+: set the override")
expect_absent("checkout v0\\.2\\.0")
# A malformed override is a parse error.
new_root(override_bad 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.2.0 @abc\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "bad override '@abc' in line 'dvv-base 0.2.0 @abc'")
# A dependency's own override must be repeated exactly. A dvv-platform branch commit overrides dvv-base.
set(work "${WORK_DIR}/work/dvv-platform")
run_git(-C "${work}" checkout -q -b feature v0.1.0)
file(WRITE "${work}/dvv-deps.txt" "dvv-build 0.1.0\ndvv-base 0.1.0 @${feature_sha}\n")
run_git(-C "${work}" commit -q -am "dvv-platform with a dvv-base override")
run_git(-C "${work}" push -q origin feature)
run_git(-C "${work}" rev-parse HEAD)
set(platform_sha "${git_out}")
run_git(-C "${work}" checkout -q main)
run_git(-C "${WORK_DIR}/work/dvv-base" rev-parse main)
set(base_main_sha "${git_out}")
# (a) not repeated, (b) repeated, (c) overridden with a different commit.
new_root(override_transitive 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.1.0\ndvv-platform 0.1.0 @${platform_sha}\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "overrides dvv-base with ${feature_sha}: add ' @${feature_sha}' to the dvv-base line of dvv-gpu/dvv-deps\\.txt")
new_root(override_transitive_ok 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.1.0 @${feature_sha}\ndvv-platform 0.1.0 @${platform_sha}\n"
        "${remote}/dvv-gpu")
expect(dvv-gpu 0 "dvv-platform: checked out commit ${platform_sha}")
new_root(override_transitive_other 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-base 0.1.0 @${base_main_sha}\ndvv-platform 0.1.0 @${platform_sha}\n"
        "${remote}/dvv-gpu")
expect(dvv-gpu 1 "overrides dvv-base with ${feature_sha}: add ' @${feature_sha}'")
# A dependency's override that the library does not list is suggested with the override.
new_root(override_transitive_missing 0.1.0)
new_lib(dvv-gpu "dvv-build 0.1.0\ndvv-platform 0.1.0 @${platform_sha}\n" "${remote}/dvv-gpu")
expect(dvv-gpu 1 "does not list: add 'dvv-base 0\\.1\\.0 @${feature_sha}' before the dvv-platform line")

if(failures)
    message(FATAL_ERROR "fetch-deps tests failed")
endif()
message(STATUS "fetch-deps tests passed")
