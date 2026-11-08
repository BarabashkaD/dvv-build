# Tests for tools/select-vulkan-driver.cmake with stand-ins for brew, the device check and pgrep:
# which driver the macOS CI jobs choose, and when the job must fail. Runs on any host (the stand-ins
# are shell scripts; skipped on Windows).
# Run: cmake -DWORK_DIR=<empty scratch dir> -P tests/ci/test_select_vulkan_driver.cmake
cmake_minimum_required(VERSION 4.2)
if(NOT DEFINED WORK_DIR)
    message(FATAL_ERROR "pass -DWORK_DIR=<scratch directory>")
endif()
if(CMAKE_HOST_WIN32)
    message(STATUS "select-vulkan-driver tests: skipped (POSIX stand-ins)")
    return()
endif()
set(script "${CMAKE_CURRENT_LIST_DIR}/../../tools/select-vulkan-driver.cmake")
file(REMOVE_RECURSE "${WORK_DIR}")
set(prefix "${WORK_DIR}/prefix")
set(kosmickrisp "${prefix}/share/vulkan/icd.d/libkosmickrisp_icd.json")
set(mesa "${WORK_DIR}/cellar/mesa")
set(lavapipe "${mesa}/share/vulkan/icd.d/lvp_icd.aarch64.json")
set(state "${WORK_DIR}/state")
file(MAKE_DIRECTORY "${state}")

function(executable path text)
    file(WRITE "${path}" "${text}")
    file(CHMOD "${path}" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
endfunction()
# brew: records every call; `install` fails while state/install-failures holds a count above 0.
executable("${WORK_DIR}/brew" "#!/bin/sh
echo \"$* NO_AUTO_UPDATE=$HOMEBREW_NO_AUTO_UPDATE\" >> '${state}/brew-calls'
case \"$1\" in
  install)
    n=$(cat '${state}/install-failures' 2>/dev/null || echo 0)
    if [ \"$n\" -gt 0 ]; then echo $((n - 1)) > '${state}/install-failures'; echo 'Error: 503' >&2; exit 1; fi ;;
  --prefix) echo '${mesa}' ;;
  list) printf 'mesa 26.2.6\\nllvm 23.1.5\\n' ;;
esac
")
# The device check: passes for a manifest whose name is listed in state/passing.
file(WRITE "${WORK_DIR}/check.cmake" "
if(DEFINED DRIVER_FILES)
    set(manifest \"\${DRIVER_FILES}\")
else()
    set(manifest \"\${PREFIX}/share/vulkan/icd.d/libkosmickrisp_icd.json\")
endif()
cmake_path(GET manifest FILENAME name)
file(STRINGS \"${state}/passing\" passing)
if(NOT name IN_LIST passing)
    message(FATAL_ERROR \"stub check: no device on \${name}\")
endif()
message(STATUS \"stub check passed on \${name}\")
")
executable("${WORK_DIR}/pgrep" "#!/bin/sh\n[ -f '${state}/windowserver' ]\n")

# run(<name> <0|1 expected failure> <expected output regex>): runs the script with the stand-ins and
# OUTPUT=<WORK_DIR>/<name>.out; sets `output` (normalized) and `result` (the OUTPUT file's text).
function(run name expect_failure expected)
    file(REMOVE "${WORK_DIR}/${name}.out" "${state}/brew-calls")
    execute_process(COMMAND "${CMAKE_COMMAND}" "-DPREFIX=${prefix}" "-DBREW=${WORK_DIR}/brew"
                            "-DCHECK=${WORK_DIR}/check.cmake" "-DPGREP=${WORK_DIR}/pgrep"
                            "-DOUTPUT=${WORK_DIR}/${name}.out" "-DPAUSES=0;0" ${ARGN} -P "${script}"
                    RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
    string(REGEX REPLACE "[ \t\r\n]+" " " text "${out}${err}")
    if(expect_failure AND status EQUAL 0)
        message(FATAL_ERROR "FAIL: ${name}: succeeded:\n${out}${err}")
    elseif(NOT expect_failure AND NOT status EQUAL 0)
        message(FATAL_ERROR "FAIL: ${name}: failed:\n${out}${err}")
    elseif(NOT text MATCHES "${expected}")
        message(FATAL_ERROR "FAIL: ${name}: output lacks '${expected}':\n${out}${err}")
    endif()
    set(result "")
    if(EXISTS "${WORK_DIR}/${name}.out")
        file(READ "${WORK_DIR}/${name}.out" result)
    endif()
    set(result "${result}" PARENT_SCOPE)
    set(calls "")
    if(EXISTS "${state}/brew-calls")
        file(STRINGS "${state}/brew-calls" calls)
    endif()
    set(calls "${calls}" PARENT_SCOPE)
endfunction()
function(expect_result name wanted)
    if(NOT result STREQUAL wanted)
        message(FATAL_ERROR "FAIL: ${name}: OUTPUT is\n${result}\nnot\n${wanted}")
    endif()
endfunction()

# (b) No KosmicKrisp manifest: a broken prefix fails, it never falls back to lavapipe.
run(manifest-missing 1 "no KosmicKrisp manifest .*libkosmickrisp_icd\\.json")
if(calls)
    message(FATAL_ERROR "FAIL: manifest-missing: brew was called: ${calls}")
endif()

file(WRITE "${kosmickrisp}" "{}\n")
file(WRITE "${lavapipe}" "{}\n")
# (a) KosmicKrisp has a device: it is chosen and brew is never called; display with WindowServer.
file(WRITE "${state}/passing" "libkosmickrisp_icd.json\n")
file(WRITE "${state}/windowserver" "")
run(kosmickrisp 0 "driver: kosmickrisp")
expect_result(kosmickrisp "driver=kosmickrisp\nmanifest=${kosmickrisp}\ndisplay=1\n")
if(calls)
    message(FATAL_ERROR "FAIL: kosmickrisp: brew was called: ${calls}")
endif()
file(REMOVE "${state}/windowserver")
run(kosmickrisp-headless 0 "driver: kosmickrisp")
expect_result(kosmickrisp-headless "driver=kosmickrisp\nmanifest=${kosmickrisp}\ndisplay=0\n")

# From here KosmicKrisp has no device (the GitHub runners).
file(WRITE "${state}/passing" "lvp_icd.aarch64.json\n")
file(WRITE "${state}/windowserver" "")
# (f) lavapipe: installed with Homebrew's update switched off, versions printed, no display tests
# even with a desktop session.
run(lavapipe 0 "driver: lavapipe \\(mesa 26\\.2\\.6, llvm 23\\.1\\.5\\)")
expect_result(lavapipe "driver=lavapipe\nmanifest=${lavapipe}\ndisplay=0\n")
list(GET calls 0 first)
if(NOT first STREQUAL "install mesa NO_AUTO_UPDATE=1")
    message(FATAL_ERROR "FAIL: lavapipe: first brew call is '${first}'")
endif()

# (c) The switch: GPU tests skip, no brew call.
run(switch-off 0 "DVV_MACOS_SOFTWARE_GPU=off" -DSWITCH=off)
expect_result(switch-off "driver=none\nmanifest=\ndisplay=0\n")
if(calls)
    message(FATAL_ERROR "FAIL: switch-off: brew was called: ${calls}")
endif()
# The switch is read without regard to case, and as any CMake false value: OFF, false, 0, no.
foreach(value IN ITEMS OFF Off false 0 no)
    run(switch-${value} 0 "DVV_MACOS_SOFTWARE_GPU=${value}" -DSWITCH=${value})
    expect_result(switch-${value} "driver=none\nmanifest=\ndisplay=0\n")
endforeach()
# Any other value, or none, keeps lavapipe; an unknown one is named.
run(switch-typo 0 "DVV_MACOS_SOFTWARE_GPU=offf is not off" -DSWITCH=offf)
expect_result(switch-typo "driver=lavapipe\nmanifest=${lavapipe}\ndisplay=0\n")

# (d) Homebrew fails every time: exactly three installs, then an error naming Homebrew.
file(WRITE "${state}/install-failures" "5\n")
run(brew-fails 1 "Homebrew could not install mesa \\(3 attempts\\)")
list(LENGTH calls count)
if(NOT count EQUAL 3)
    message(FATAL_ERROR "FAIL: brew-fails: ${count} brew calls, expected 3: ${calls}")
endif()
# Two failures and then success: lavapipe after the third attempt.
file(WRITE "${state}/install-failures" "2\n")
run(brew-recovers 0 "driver: lavapipe")

# (e) Zero or two lavapipe manifests.
file(REMOVE "${lavapipe}")
run(no-manifest 1 "expected one lvp_icd\\.\\*\\.json in ${mesa}/share/vulkan/icd\\.d, found 0")
file(WRITE "${lavapipe}" "{}\n")
file(WRITE "${mesa}/share/vulkan/icd.d/lvp_icd.x86_64.json" "{}\n")
run(two-manifests 1 "expected one lvp_icd\\.\\*\\.json in .*found 2")
file(REMOVE "${mesa}/share/vulkan/icd.d/lvp_icd.x86_64.json")

# (g) lavapipe installed but its device check fails.
file(WRITE "${state}/passing" "nothing\n")
run(lavapipe-no-device 1 "lavapipe has no usable Vulkan device")

message(STATUS "select-vulkan-driver tests passed")
