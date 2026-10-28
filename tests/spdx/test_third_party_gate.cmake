# dvv_third_party() must stop configuration for a disallowed licence or a malformed declaration
# and record an accepted one. Run: cmake -P tests/spdx/test_third_party_gate.cmake
cmake_minimum_required(VERSION 4.2)
set(module "${CMAKE_CURRENT_LIST_DIR}/../../cmake/DvvThirdParty.cmake")
set(hash "0000000000000000000000000000000000000000000000000000000000000000")

# Probe mode: runs PROBE_CODE after the module. The code has no semicolons and separates its
# commands with "|", so it passes through a command line intact.
if(DEFINED PROBE_CODE)
    include("${module}")
    string(REPLACE "|" "\n" code "${PROBE_CODE}")
    cmake_language(EVAL CODE "${code}")
    message(STATUS "accepted")
    return()
endif()

# decl(<code variable> <name> <spdx> <linkage> [<more arguments>...]): appends a declaration.
function(decl code_variable name spdx linkage)
    list(JOIN ARGN " " more)
    set(code "${${code_variable}}")
    string(APPEND code "|dvv_third_party(${name} VERSION 1.0 URL https://example.com/${name}.tgz"
                       " SHA256 ${hash} SPDX \"${spdx}\" LINKAGE ${linkage}"
                       " LICENSE_FILES LICENSE ${more})")
    set(${code_variable} "${code}" PARENT_SCOPE)
endfunction()

# expect(<code> <0|1 expected failure> <expected output regex>)
function(expect code expect_failure expected_text)
    execute_process(COMMAND "${CMAKE_COMMAND}" "-DPROBE_CODE=${code}"
                            -P "${CMAKE_CURRENT_LIST_FILE}"
                    RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
    if(expect_failure AND status EQUAL 0)
        message(FATAL_ERROR "FAIL: accepted: ${code}")
    endif()
    if(NOT expect_failure AND NOT status EQUAL 0)
        message(FATAL_ERROR "FAIL: rejected: ${code}\n${err}")
    endif()
    # CMake wraps long messages; compare with every run of white space folded into one space.
    string(REGEX REPLACE "[ \t\r\n]+" " " output "${out}${err}")
    if(NOT output MATCHES "${expected_text}")
        message(FATAL_ERROR "FAIL: output lacks '${expected_text}' for: ${code}\n${out}${err}")
    endif()
endfunction()

# gate(<spdx> <linkage> <0|1 expected failure> <expected output regex>)
function(gate spdx linkage expect_failure expected_text)
    set(code "set(CMAKE_SYSTEM_NAME Windows)")
    decl(code probe "${spdx}" ${linkage})
    expect("${code}" ${expect_failure} "${expected_text}")
endfunction()

gate("GPL-3.0-only" static 1 "Licence gate: probe 1.0 \\(GPL-3.0-only\\) rejected")
gate("MIT" static 0 "accepted")
gate("NCSA" tool 0 "accepted")
gate("CC-BY-4.0" tool 0 "accepted")
gate("NCSA" runtime 1 "rejected: not allowed for runtime linkage: NCSA")
gate("MIT AND CC-BY-4.0" static 1 "rejected: not allowed for static linkage: CC-BY-4.0")

# The gate judges a declaration that is not built on this platform, too.
set(code "set(CMAKE_SYSTEM_NAME Linux)")
decl(code windows_only "GPL-3.0-only" static ONLY_ON Windows)
expect("${code}" 1 "Licence gate: windows_only 1.0 \\(GPL-3.0-only\\) rejected")

# Required keys and malformed declarations.
string(CONCAT code "set(CMAKE_SYSTEM_NAME Windows)|dvv_third_party(probe VERSION 1.0"
                   " URL https://example.com/p.tgz SHA256 ${hash} SPDX MIT LINKAGE static)")
expect("${code}" 1 "dvv_third_party\\(probe\\): LICENSE_FILES is required")
set(code "set(CMAKE_SYSTEM_NAME Windows)")
decl(code probe MIT static ONLY_ON Darwin)
expect("${code}" 1 "ONLY_ON must be one of Windows")
set(code "set(CMAKE_SYSTEM_NAME Windows)")
decl(code probe MIT tool PREBUILT CMAKE_ARGS -DX=1)
expect("${code}" 1 "PREBUILT takes no CMAKE_ARGS")
set(code "set(CMAKE_SYSTEM_NAME Windows)")
decl(code probe MIT static CONFIGS Debug Release)
expect("${code}" 0 "accepted")
set(code "set(CMAKE_SYSTEM_NAME Windows)")
decl(code probe MIT static CONFIGS Debug RelWithDebInfo)
expect("${code}" 1 "dvv_third_party\\(probe\\): CONFIGS takes Debug and Release only, not 'RelWithDebInfo'")
set(code "set(CMAKE_SYSTEM_NAME Windows)")
decl(code probe MIT tool PREBUILT CONFIGS Debug Release)
expect("${code}" 1 "dvv_third_party\\(probe\\): PREBUILT takes no CONFIGS")
# A prebuilt archive replaces <prefix>/<name> as a whole, so the name must not be a shared folder.
set(code "set(CMAKE_SYSTEM_NAME Windows)")
decl(code bin MIT tool PREBUILT)
expect("${code}" 1 "dvv_third_party\\(bin\\): a PREBUILT name must not be a prefix folder")
set(code "set(CMAKE_SYSTEM_NAME Windows)")
decl(code probe MIT static POST_INSTALL no-such-script.cmake)
expect("${code}" 1 "dvv_third_party\\(probe\\): POST_INSTALL script not found")

# Names and dependencies.
set(code "set(CMAKE_SYSTEM_NAME Windows)")
decl(code twice MIT static)
decl(code twice MIT static)
expect("${code}" 1 "dvv_third_party\\(twice\\): declared twice for Windows")
set(code "set(CMAKE_SYSTEM_NAME Linux)")
decl(code twice MIT static ONLY_ON Windows)
decl(code twice MIT static)
expect("${code}" 1 "dvv_third_party\\(twice\\): declared twice for Windows")
set(code "set(CMAKE_SYSTEM_NAME Windows)")
decl(code user MIT static DEPENDS later)
decl(code later MIT static)
expect("${code}" 1 "dvv_third_party\\(user\\): DEPENDS later is not declared before it for Windows")
# Checked for every platform the dependant is built on, whatever the current platform is.
set(code "set(CMAKE_SYSTEM_NAME Windows)")
decl(code windows_only MIT static ONLY_ON Windows)
decl(code user MIT static DEPENDS windows_only)
expect("${code}" 1 "dvv_third_party\\(user\\): DEPENDS windows_only is not declared before it for Linux")

# An accepted set: one name per platform, a dependency, a prebuilt tool and a post-install script
# (relative to the declaring file, here this one). Only the Linux declarations are recorded.
set(code "set(CMAKE_SYSTEM_NAME Linux)")
decl(code headers MIT static)
decl(code tool MIT tool ONLY_ON Windows PREBUILT)
decl(code tool MIT tool ONLY_ON Linux PREBUILT POST_INSTALL test_third_party_gate.cmake)
decl(code user MIT static DEPENDS headers tool CONFIGS Debug Release
     CMAKE_ARGS -DA=1 -DB=<INSTALL_DIR>)
string(APPEND code [[|get_property(names GLOBAL PROPERTY DVV_THIRD_PARTY_NAMES)]]
                   [[|message(STATUS "names=<${names}>")]])
foreach(key IN ITEMS tool_PREBUILT tool_POST_INSTALL user_DEPENDS user_CMAKE_ARGS user_PREBUILT
                     user_CONFIGS headers_CONFIGS)
    string(APPEND code "|get_property(value GLOBAL PROPERTY DVV_THIRD_PARTY_${key})"
                       "|message(STATUS \"${key}=<\${value}>\")")
endforeach()
expect("${code}" 0 "names=<headers.tool.user>")
expect("${code}" 0 "tool_PREBUILT=<TRUE>")
expect("${code}" 0 "tool_POST_INSTALL=<[^>]*/tests/spdx/test_third_party_gate\\.cmake>")
expect("${code}" 0 "user_DEPENDS=<headers.tool>")
expect("${code}" 0 "user_CMAKE_ARGS=<-DA=1.-DB=<INSTALL_DIR>>")
expect("${code}" 0 "user_PREBUILT=<FALSE>")
expect("${code}" 0 "user_CONFIGS=<Debug.Release>")
expect("${code}" 0 "headers_CONFIGS=<Release>")

# SHIPPED (M4 design D19): only an entry whose code or files are in a package; a tool never ships.
set(code "set(CMAKE_SYSTEM_NAME Windows)")
decl(code probe MIT tool SHIPPED)
expect("${code}" 1 "dvv_third_party\\(probe\\): SHIPPED needs LINKAGE static or runtime")
set(code "set(CMAKE_SYSTEM_NAME Windows)")
decl(code shipped MIT runtime PREBUILT SHIPPED)
decl(code kept MIT static)
string(APPEND code [[|get_property(a GLOBAL PROPERTY DVV_THIRD_PARTY_shipped_SHIPPED)]]
                   [[|get_property(b GLOBAL PROPERTY DVV_THIRD_PARTY_kept_SHIPPED)]]
                   [[|message(STATUS "shipped=<${a}> kept=<${b}>")]])
expect("${code}" 0 "shipped=<TRUE> kept=<FALSE>")

# dvv_source_pin (M4 design D27).
set(pin "dvv_source_pin(lame VERSION 3.100 URL https://example.com/lame.tgz")
string(CONCAT code "set(CMAKE_SYSTEM_NAME Windows)|${pin} SHA256 ${hash})"
                   [[|get_property(n GLOBAL PROPERTY DVV_SOURCE_PIN_NAMES)]]
                   [[|get_property(u GLOBAL PROPERTY DVV_SOURCE_PIN_lame_URL)]]
                   [[|get_property(v GLOBAL PROPERTY DVV_SOURCE_PIN_lame_VERSION)]]
                   [[|message(STATUS "pin=<${n} ${v} ${u}>")]])
expect("${code}" 0 "pin=<lame 3.100 https://example.com/lame.tgz>")
expect("set(CMAKE_SYSTEM_NAME Windows)|${pin})" 1 "dvv_source_pin\\(lame\\): SHA256 is required")
string(TOUPPER "${hash}" upper_hash)
string(REPLACE "0" "A" upper_hash "${upper_hash}")
expect("set(CMAKE_SYSTEM_NAME Windows)|${pin} SHA256 ${upper_hash})" 1
       "dvv_source_pin\\(lame\\): SHA256 must be 64 lower-case hex digits")
expect("set(CMAKE_SYSTEM_NAME Windows)|${pin} SHA256 ${hash}0)" 1 "SHA256 must be 64 lower-case")
expect("set(CMAKE_SYSTEM_NAME Windows)|${pin} SHA256 ${hash})|${pin} SHA256 ${hash})" 1
       "dvv_source_pin\\(lame\\): pinned twice")
expect("set(CMAKE_SYSTEM_NAME Windows)|${pin} SHA256 ${hash} EXTRA 1)" 1
       "dvv_source_pin\\(lame\\): unexpected 'EXTRA.1'")

message(STATUS "third-party gate tests passed")
