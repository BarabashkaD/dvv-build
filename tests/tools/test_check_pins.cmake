# Tests for tools/check-pins.cmake with local bare repositories and tags in WORK_DIR (no network).
# Run: cmake -DWORK_DIR=<scratch dir> -P tests/tools/test_check_pins.cmake
cmake_minimum_required(VERSION 4.2)
if(NOT DEFINED WORK_DIR)
    message(FATAL_ERROR "pass -DWORK_DIR=<scratch directory>")
endif()
find_program(GIT_EXECUTABLE git REQUIRED)
set(script "${CMAKE_CURRENT_LIST_DIR}/../../tools/check-pins.cmake")
set(failures 0)
file(REMOVE_RECURSE "${WORK_DIR}")
file(MAKE_DIRECTORY "${WORK_DIR}")
set(remote "${WORK_DIR}/remote")
set(ref "example-owner/dvv-build/.github/workflows/dvv-ci.yml")
set(uses "uses: ${ref}")

function(run_git)
    execute_process(COMMAND "${GIT_EXECUTABLE}" ${ARGN} RESULT_VARIABLE rc OUTPUT_VARIABLE out
                    ERROR_VARIABLE err OUTPUT_STRIP_TRAILING_WHITESPACE)
    if(NOT rc EQUAL 0)
        message(FATAL_ERROR "git ${ARGN} failed:\n${out}${err}")
    endif()
    set(git_out "${out}" PARENT_SCOPE)
endfunction()

function(identity dir)
    run_git(-C "${dir}" config user.name test-user)
    run_git(-C "${dir}" config user.email test@users.noreply.github.com)
    run_git(-C "${dir}" config commit.gpgsign false)
    run_git(-C "${dir}" config tag.gpgsign false)
endfunction()

# publish(<name> <version> <annotated|lightweight|none>): commits a fake dvv repository at <version>
# (dvv-build: VERSION, else project()), tags it v<version> as asked, pushes to <remote>/<name> and
# sets <name>_sha to the commit.
function(publish name version tag)
    set(work "${WORK_DIR}/work/${name}")
    if(NOT EXISTS "${work}")
        run_git(init -q --bare -b main "${remote}/${name}")
        run_git(init -q -b main "${work}")
        identity("${work}")
        run_git(-C "${work}" remote add origin "${remote}/${name}")
    endif()
    string(REPLACE "-" "_" id "${name}")
    if(name STREQUAL "dvv-build")
        file(WRITE "${work}/VERSION" "${version}\n")
    else()
        file(WRITE "${work}/CMakeLists.txt" "project(${id} VERSION ${version} LANGUAGES NONE)\n")
    endif()
    file(APPEND "${work}/notes.txt" "${version} ${tag}\n")
    run_git(-C "${work}" add -A)
    run_git(-C "${work}" commit -q -m "${name} ${version}")
    if(tag STREQUAL "annotated")
        run_git(-C "${work}" tag -a "v${version}" -m "${name} ${version}")
    elseif(tag STREQUAL "lightweight")
        run_git(-C "${work}" tag "v${version}")
    endif()
    run_git(-C "${work}" push -q origin main --tags)
    run_git(-C "${work}" rev-parse HEAD)
    set(${id}_sha "${git_out}" PARENT_SCOPE)
endfunction()

# expect(<repo dir> <0|1 expected failure> <expected regex or ""> [<extra cmake arguments>...])
function(expect repo expect_failure expected_text)
    execute_process(COMMAND "${CMAKE_COMMAND}" "-DREPO=${repo}" ${ARGN} -P "${script}"
                    RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
    set(all "${out}${err}")
    string(REGEX REPLACE "[ \t\r\n]+" " " flat "${all}")
    set(last_out "${flat}" PARENT_SCOPE)
    if(expect_failure AND status EQUAL 0)
        message(SEND_ERROR "FAIL: expected check-pins to fail for ${repo}\n${all}")
        set(failures 1 PARENT_SCOPE)
    elseif(NOT expect_failure AND NOT status EQUAL 0)
        message(SEND_ERROR "FAIL: expected check-pins to pass for ${repo}\n${all}")
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

# Lib mode: the dvv-ci.yml @vX of the workflows equals the dvv-build line of dvv-deps.txt.
set(lib "${WORK_DIR}/lib/dvv-gpu")
file(WRITE "${lib}/dvv-deps.txt" "# deps\r\ndvv-base 0.1.0\r\ndvv-build 0.1.0\r\n")
file(WRITE "${lib}/.github/workflows/ci.yml"
     "jobs:\n  ci:\n    # old: ${uses}@v0.0.9\n    ${uses}@v0.1.0\n")
file(WRITE "${lib}/.github/workflows/other.yaml" "jobs:\n  ci:\n    uses: \"${ref}@v0.1.0\" # quoted\n")
expect("${lib}" 0 "lib mode: ci.yml @v0.1.0 = dvv-build 0.1.0.*lib mode: other.yaml @v0.1.0 = dvv-build 0.1.0")
expect_absent("v0.0.9")
file(REMOVE "${lib}/.github/workflows/other.yaml")
file(WRITE "${lib}/.github/workflows/other.yml" "jobs:\n  ci:\n    uses: '${ref}@v0.2.0'\n")
expect("${lib}" 1 "other.yml: dvv-build workflow @v0.2.0, but dvv-deps.txt has dvv-build 0.1.0")
file(REMOVE "${lib}/.github/workflows/other.yml")
file(WRITE "${lib}/.github/workflows/ci.yml" "jobs:\n  ci:\n    runs-on: x\n")
expect("${lib}" 1 "no workflow in .* uses dvv-build's dvv-ci.yml")
file(WRITE "${lib}/.github/workflows/ci.yml" "jobs:\n  ci:\n    ${uses}@v0.1.0\n")
file(WRITE "${lib}/dvv-deps.txt" "dvv-base 0.1.0\n")
expect("${lib}" 1 "has no dvv-build line")
# The other dvv-deps.txt errors, through the shared reader (cmake/DvvDepsFile.cmake).
file(WRITE "${lib}/dvv-deps.txt" "dvv-build 0.1.0\ndvv-base 0.1\n")
expect("${lib}" 1 "dvv-gpu: [^ ]*/dvv-deps.txt: bad line 'dvv-base 0.1'")
file(WRITE "${lib}/dvv-deps.txt" "dvv-build 0.1.0\ndvv-base 0.1.0\ndvv-base 0.1.0\n")
expect("${lib}" 1 "lists dvv-base twice")
file(WRITE "${lib}/dvv-deps.txt" "dvv-build 0.1.0\ndvv-build 0.1.0\n")
expect("${lib}" 1 "lists dvv-build twice")
file(WRITE "${lib}/dvv-deps.txt" "dvv-build 0.1.0\ndvv-gpu 0.1.0\n")
expect("${lib}" 1 "lists dvv-gpu itself")
# A branch-only override is a finding: main depends on tags only.
set(sha "0123456789abcdef0123456789abcdef01234567")
file(WRITE "${lib}/dvv-deps.txt" "dvv-build 0.1.0\ndvv-base 0.1.0 @${sha}\n")
expect("${lib}" 1 "dvv-deps.txt: dvv-base 0.1.0 @${sha} is a branch-only override: back on tags before merge")
file(WRITE "${lib}/dvv-deps.txt" "dvv-build 0.1.0 @${sha}\n")
expect("${lib}" 1 "the dvv-build line takes no override")
file(REMOVE "${lib}/dvv-deps.txt")
expect("${lib}" 1 "dvv-deps.txt does not exist")
expect("${lib}" 1 "MODE must be lib or app" -DMODE=other)

# App mode with an empty .gitmodules: no submodule at all.
set(empty_app "${WORK_DIR}/app-empty/rawreel")
run_git(init -q -b main "${empty_app}")
file(WRITE "${empty_app}/.gitmodules" "")
expect("${empty_app}" 1 "no submodule libs/dvv-build in")

# App mode fixtures: dvv-build v0.1.0 (lightweight tag); dvv-base v0.1.0 (annotated), a later
# untagged commit still at 0.1.0 and an untagged 0.1.1.
publish(dvv-build 0.1.0 lightweight)
publish(dvv-base 0.1.0 annotated)
set(base_tagged "${dvv_base_sha}")
publish(dvv-base 0.1.0 none)
set(base_later "${dvv_base_sha}")
publish(dvv-base 0.1.1 none)
set(base_untagged "${dvv_base_sha}")
# Only a near tag (a release candidate) on the 0.1.1 commit.
run_git(-C "${WORK_DIR}/work/dvv-base" tag v0.1.1-rc1)
run_git(-C "${WORK_DIR}/work/dvv-base" push -q origin --tags)

set(app "${WORK_DIR}/app/rawreel")
run_git(init -q -b main "${app}")
identity("${app}")
run_git(-C "${app}" remote add origin "${remote}/rawreel")
run_git(-C "${app}" -c protocol.file.allow=always submodule add -q ../dvv-build libs/dvv-build)
run_git(-C "${app}" -c protocol.file.allow=always submodule add -q ../dvv-base libs/dvv-base)
run_git(-C "${app}/libs/dvv-base" checkout -q "${base_tagged}")
file(WRITE "${app}/.github/workflows/ci.yml" "jobs:\n  ci:\n    ${uses}@v0.1.0\n")
file(WRITE "${app}/.github/workflows/release.yml" "jobs:\n  build:\n    runs-on: x\n")
run_git(-C "${app}" add -A)
run_git(-C "${app}" commit -q -m "app")

expect("${app}" 0 "app mode.*libs/dvv-build 0.1.0 = tag v0.1.0.*libs/dvv-base 0.1.0 = tag v0.1.0")
expect("${app}" 0 "libs/dvv-base" -DMODE=app)

# As in CI (actions/checkout with submodules: recursive): a shallow clone with shallow submodules and
# local tags removed (the worst case); the tags are resolved on the origins.
run_git(init -q --bare -b main "${remote}/rawreel")
run_git(-C "${app}" push -q origin HEAD:refs/heads/main)
if(remote MATCHES "^/")
    set(remote_url "file://${remote}")
else()
    set(remote_url "file:///${remote}")
endif()
set(shallow "${WORK_DIR}/shallow/rawreel")
run_git(-c protocol.file.allow=always clone -q --depth 1 --no-tags --recurse-submodules
        --shallow-submodules "${remote_url}/rawreel" "${shallow}")
foreach(sub IN ITEMS dvv-build dvv-base)
    run_git(-C "${shallow}/libs/${sub}" rev-parse --is-shallow-repository)
    if(NOT git_out STREQUAL "true")
        message(SEND_ERROR "FAIL: libs/${sub} of the shallow clone is not shallow")
        math(EXPR failures "${failures} + 1")
    endif()
    run_git(-C "${shallow}/libs/${sub}" tag -l)
    if(NOT git_out STREQUAL "")
        string(REPLACE "\n" ";" shallow_tags "${git_out}")
        run_git(-C "${shallow}/libs/${sub}" tag -d ${shallow_tags})
    endif()
endforeach()
expect("${shallow}" 0 "libs/dvv-build 0.1.0 = tag v0.1.0.*libs/dvv-base 0.1.0 = tag v0.1.0")
# The same shallow, tag-less clone with an untagged pin fails.
run_git(-C "${shallow}/libs/dvv-base" fetch -q --depth 1 origin "${base_untagged}")
run_git(-C "${shallow}/libs/dvv-base" checkout -q "${base_untagged}")
identity("${shallow}")
run_git(-C "${shallow}" commit -q -am "pin 0.1.1")
expect("${shallow}" 1 "libs/dvv-base: pin ${base_untagged} \\(version 0.1.1\\) is not tagged: origin has no tag v0.1.1")

# The version comes from the pinned commit, not from an edited work tree.
file(WRITE "${app}/libs/dvv-base/CMakeLists.txt" "project(dvv_base VERSION 0.9.0 LANGUAGES NONE)\n")
file(WRITE "${app}/libs/dvv-build/VERSION" "0.9.0\n")
expect("${app}" 0 "libs/dvv-build 0.1.0 = tag v0.1.0.*libs/dvv-base 0.1.0 = tag v0.1.0")
run_git(-C "${app}/libs/dvv-base" checkout -q -- CMakeLists.txt)
run_git(-C "${app}/libs/dvv-build" checkout -q -- VERSION)

# A branch-only override in the app's own dvv-deps.txt: the app moves the submodule instead.
set(fake_sha "0123456789abcdef0123456789abcdef01234567")
file(WRITE "${app}/dvv-deps.txt" "dvv-build 0.1.0\ndvv-base 0.1.0 @${fake_sha}\n")
expect("${app}" 1 "dvv-deps.txt: dvv-base 0.1.0 @${fake_sha} is a branch-only override: in the app, move the libs/dvv-base submodule instead")
file(REMOVE "${app}/dvv-deps.txt")

# An origin that cannot be listed.
run_git(-C "${app}/libs/dvv-base" remote rename origin upstream)
expect("${app}" 1 "libs/dvv-base: cannot list the tags of its origin: ")
run_git(-C "${app}/libs/dvv-base" remote rename upstream origin)

# URLs must be relative ../<name>, without .git.
foreach(url "https://example.invalid/dvv-base" "../dvv-base.git" "../dvv-gpu")
    run_git(-C "${app}" config -f .gitmodules submodule.libs/dvv-base.url "${url}")
    expect("${app}" 1 "libs/dvv-base: URL '${url}' is not '../dvv-base'")
endforeach()
run_git(-C "${app}" checkout -q -- .gitmodules)

# The workflows' @vX equals the pinned dvv-build VERSION.
file(WRITE "${app}/.github/workflows/ci.yml" "jobs:\n  ci:\n    ${uses}@v0.2.0\n")
expect("${app}" 1 "ci.yml: dvv-build workflow @v0.2.0, but libs/dvv-build has VERSION 0.1.0")
run_git(-C "${app}" checkout -q -- .github/workflows/ci.yml)

# The checked-out submodule differs from the committed pin.
run_git(-C "${app}/libs/dvv-base" checkout -q "${base_later}")
expect("${app}" 1 "libs/dvv-base is checked out at ${base_later}, not at the pin ${base_tagged}")

# A pin at a commit without the tag of its version.
run_git(-C "${app}/libs/dvv-base" checkout -q "${base_untagged}")
run_git(-C "${app}" commit -q -am "pin 0.1.1")
expect("${app}" 1 "libs/dvv-base: pin ${base_untagged} \\(version 0.1.1\\) is not tagged: origin has no tag v0.1.1")

# A pin at a version whose tag is another commit.
run_git(-C "${app}/libs/dvv-base" checkout -q "${base_later}")
run_git(-C "${app}" commit -q -am "pin later")
expect("${app}" 1 "libs/dvv-base: pin ${base_later} has version 0.1.0, but tag v0.1.0 on origin is ${base_tagged}")

# A tagged library release whose dvv-deps.txt still carries an override (a tag on a branch commit).
file(WRITE "${WORK_DIR}/work/dvv-base/dvv-deps.txt" "dvv-build 0.1.0\ndvv-platform 0.1.0 @${fake_sha}\n")
publish(dvv-base 0.1.2 annotated)
run_git(-C "${app}/libs/dvv-base" fetch -q origin)
run_git(-C "${app}/libs/dvv-base" checkout -q "${dvv_base_sha}")
run_git(-C "${app}" commit -q -am "pin 0.1.2")
expect("${app}" 1 "libs/dvv-base: its dvv-deps.txt at the pin ${dvv_base_sha} overrides dvv-platform with ${fake_sha}: pin a release")

# A submodule outside libs/ and a missing checkout.
run_git(-C "${app}" config -f .gitmodules submodule.libs/dvv-base.path tools/dvv-base)
expect("${app}" 1 "submodule path 'tools/dvv-base' is not libs/dvv-<name>")
run_git(-C "${app}" checkout -q -- .gitmodules)
run_git(-C "${app}" submodule deinit -q -f libs/dvv-base)
expect("${app}" 1 "libs/dvv-base is not checked out")

# dvv-build checked out away from its pin: the workflows' @vX are still checked (at the pin's VERSION).
file(WRITE "${app}/.github/workflows/ci.yml" "jobs:\n  ci:\n    ${uses}@v0.2.0\n")
run_git(-C "${app}/libs/dvv-build" checkout -q --detach HEAD)
run_git(-C "${app}/libs/dvv-build" -c user.name=test-user -c user.email=test@users.noreply.github.com
        commit -q --allow-empty -m "local")
expect("${app}" 1 "libs/dvv-build is checked out at .*ci.yml: dvv-build workflow @v0.2.0, but libs/dvv-build has VERSION 0.1.0")
# dvv-build not checked out: its version is unknown, and the output says the @vX check was skipped.
run_git(-C "${app}" submodule deinit -q -f libs/dvv-build)
expect("${app}" 1 "libs/dvv-build is not checked out.*the workflows' dvv-build @vX were not checked")

if(failures)
    message(FATAL_ERROR "check-pins tests failed")
endif()
message(STATUS "check-pins tests passed")
