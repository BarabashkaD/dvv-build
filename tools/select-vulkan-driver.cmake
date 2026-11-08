# Chooses the Vulkan driver the macOS CI jobs run the GPU tests on, and writes the choice for the
# workflow. The prefix's KosmicKrisp (spec U-MAC2) when the runner's Metal device can run it;
# otherwise Mesa's lavapipe from Homebrew's mesa bottle, a software driver for CI only (never in the
# prefix or a package), as Linux CI takes lavapipe from apt.
#
# Usage: cmake -DPREFIX=<prefix> [-DSWITCH=<DVV_MACOS_SOFTWARE_GPU>] [-DBREW=<brew>]
#              [-DCHECK=<check-vulkan-device.cmake>] [-DPGREP=<pgrep>] [-DOUTPUT=<file>]
#              [-DPAUSES=<s>;<s>] -P tools/select-vulkan-driver.cmake
#   PREFIX   the third-party prefix (<root>/_third_party/appleclang)
#   SWITCH   the repository variable DVV_MACOS_SOFTWARE_GPU: off, false, 0 or no (any case) skips
#            lavapipe (the GPU tests skip, as before 0.4.0), a way out of a bad Homebrew bottle
#            without a release
#   BREW, CHECK, PGREP  the programs used (defaults: brew from PATH, check-vulkan-device.cmake next to
#            this script, pgrep); the tests pass stand-ins
#   OUTPUT   where driver=, manifest= and display= are appended (default $GITHUB_OUTPUT)
#   PAUSES   the pauses before the second and third `brew install` attempt (default 60;300)
# Writes driver=kosmickrisp|lavapipe|none, manifest=<the ICD manifest or empty> and display=1|0 (the
# display tests run only on KosmicKrisp with a desktop session: presenting on lavapipe on a runner is
# unproven). Fails on a prefix without KosmicKrisp's manifest (broken: run bootstrap), when Homebrew
# cannot install mesa in three attempts, without exactly one lavapipe manifest, or when lavapipe has
# no usable Vulkan 1.4 device.
cmake_minimum_required(VERSION 4.2)
if(NOT PREFIX)
    message(FATAL_ERROR "select-vulkan-driver: pass -DPREFIX=<third-party prefix>")
endif()
if(NOT DEFINED CHECK)
    set(CHECK "${CMAKE_CURRENT_LIST_DIR}/check-vulkan-device.cmake")
endif()
if(NOT DEFINED PGREP)
    set(PGREP pgrep)
endif()
if(NOT DEFINED OUTPUT)
    set(OUTPUT "$ENV{GITHUB_OUTPUT}")
endif()
if(NOT DEFINED PAUSES)
    set(PAUSES 60 300)
endif()

# write(<driver> <manifest> <display>) records the choice and ends the script.
macro(write driver manifest display)
    message(STATUS "select-vulkan-driver: driver: ${driver}${versions}; display tests: ${display}")
    if(OUTPUT)
        file(APPEND "${OUTPUT}" "driver=${driver}\nmanifest=${manifest}\ndisplay=${display}\n")
    endif()
    return()
endmacro()

# device(<manifest> <out_var>): TRUE when the device check passes on that driver.
function(device manifest out_var)
    execute_process(COMMAND "${CMAKE_COMMAND}" "-DPREFIX=${PREFIX}" "-DDRIVER_FILES=${manifest}"
                            -P "${CHECK}"
                    RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
    message("${out}${err}")
    if(status EQUAL 0)
        set(${out_var} TRUE PARENT_SCOPE)
    else()
        set(${out_var} FALSE PARENT_SCOPE)
    endif()
endfunction()

set(versions "")
set(kosmickrisp "${PREFIX}/share/vulkan/icd.d/libkosmickrisp_icd.json")
if(NOT EXISTS "${kosmickrisp}")
    message(FATAL_ERROR "select-vulkan-driver: no KosmicKrisp manifest ${kosmickrisp}: the prefix "
                        "is broken; run bootstrap")
endif()
device("${kosmickrisp}" usable)
if(usable)
    execute_process(COMMAND "${PGREP}" -x WindowServer RESULT_VARIABLE session
                    OUTPUT_QUIET ERROR_QUIET)
    if(session EQUAL 0)
        write(kosmickrisp "${kosmickrisp}" 1)
    endif()
    message("::notice::No desktop session (WindowServer); the display tests are left out")
    write(kosmickrisp "${kosmickrisp}" 0)
endif()

# Any CMake false value switches lavapipe off (off, OFF, false, 0, no): whoever sets the variable in
# a hurry need not guess the spelling. Any other value keeps lavapipe and is named.
if(DEFINED SWITCH AND NOT "${SWITCH}" STREQUAL "")
    string(TOUPPER "${SWITCH}" switch_value)
    set(off_values OFF FALSE 0 NO)
    if(switch_value IN_LIST off_values)
        message("::warning::DVV_MACOS_SOFTWARE_GPU=${SWITCH}: no lavapipe, so the GPU tests skip on "
                "this runner and the display tests are left out")
        write(none "" 0)
    endif()
    message("::notice::DVV_MACOS_SOFTWARE_GPU=${SWITCH} is not off (off, false, 0 or no); lavapipe "
            "is used")
endif()

if(NOT DEFINED BREW)
    find_program(BREW brew)
    if(NOT BREW)
        message(FATAL_ERROR "select-vulkan-driver: KosmicKrisp has no device and Homebrew (brew) "
                            "is not installed")
    endif()
endif()
# No update, no cleanup and no check of other installed formulae: install mesa and what it needs.
set(brew_env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1
             HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1)
set(attempt 1)
while(TRUE)
    execute_process(COMMAND "${CMAKE_COMMAND}" -E env ${brew_env} "${BREW}" install mesa
                    RESULT_VARIABLE status)
    if(status EQUAL 0)
        break()
    endif()
    if(attempt EQUAL 3)
        message(FATAL_ERROR "select-vulkan-driver: Homebrew could not install mesa (3 attempts); "
                            "set the repository variable DVV_MACOS_SOFTWARE_GPU=off to skip the "
                            "GPU tests until it can")
    endif()
    math(EXPR index "${attempt} - 1")
    list(GET PAUSES ${index} pause)
    message("::warning::brew install mesa failed (attempt ${attempt} of 3); trying again in "
            "${pause} seconds")
    execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep "${pause}")
    math(EXPR attempt "${attempt} + 1")
endwhile()

execute_process(COMMAND "${BREW}" list --versions mesa llvm OUTPUT_VARIABLE listed
                OUTPUT_STRIP_TRAILING_WHITESPACE)
string(REPLACE "\n" ", " listed "${listed}")
set(versions " (${listed})")
execute_process(COMMAND "${BREW}" --prefix mesa OUTPUT_VARIABLE mesa
                OUTPUT_STRIP_TRAILING_WHITESPACE RESULT_VARIABLE status)
if(NOT status EQUAL 0 OR mesa STREQUAL "")
    message(FATAL_ERROR "select-vulkan-driver: brew --prefix mesa failed")
endif()
file(GLOB manifests "${mesa}/share/vulkan/icd.d/lvp_icd.*.json")
list(LENGTH manifests count)
if(NOT count EQUAL 1)
    message(FATAL_ERROR "select-vulkan-driver: expected one lvp_icd.*.json in "
                        "${mesa}/share/vulkan/icd.d, found ${count}")
endif()
device("${manifests}" usable)
if(NOT usable)
    message(FATAL_ERROR "select-vulkan-driver: lavapipe has no usable Vulkan device${versions}")
endif()
write(lavapipe "${manifests}" 0)
