# Tests for the scripts the third-party superbuild runs (deps/*.cmake).
# Run: cmake -DWORK_DIR=<scratch dir> -P tests/deps/test_superbuild_scripts.cmake
# The test works in the fixed subfolder <scratch dir>/dvv-superbuild-scripts-test and deletes only that.
cmake_minimum_required(VERSION 4.2)
if(NOT DEFINED WORK_DIR)
    message(FATAL_ERROR "pass -DWORK_DIR=<scratch directory>")
endif()
cmake_path(ABSOLUTE_PATH WORK_DIR NORMALIZE)
set(WORK_DIR "${WORK_DIR}/dvv-superbuild-scripts-test")
set(deps "${CMAKE_CURRENT_LIST_DIR}/../../deps")
set(hash_zero "0000000000000000000000000000000000000000000000000000000000000000")
file(REMOVE_RECURSE "${WORK_DIR}")
file(MAKE_DIRECTORY "${WORK_DIR}")

# run_script(<0|1 expected failure> <expected output regex or ""> <script> [-D<name>=<value>...])
function(run_script expect_failure expected_text script)
    execute_process(COMMAND "${CMAKE_COMMAND}" ${ARGN} -P "${script}"
                    RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
    string(REGEX REPLACE "[ \t\r\n]+" " " output "${out}${err}")
    if(expect_failure AND status EQUAL 0)
        message(FATAL_ERROR "FAIL: ${script} ${ARGN} succeeded")
    elseif(NOT expect_failure AND NOT status EQUAL 0)
        message(FATAL_ERROR "FAIL: ${script} ${ARGN} failed:\n${out}${err}")
    elseif(expected_text AND NOT output MATCHES "${expected_text}")
        message(FATAL_ERROR "FAIL: output of ${script} lacks '${expected_text}':\n${out}${err}")
    endif()
endfunction()

function(expect_file_text file expected_text)
    if(NOT EXISTS "${file}")
        message(FATAL_ERROR "FAIL: ${file} does not exist")
    endif()
    file(READ "${file}" text)
    string(REPLACE "\r\n" "\n" text "${text}")
    if(NOT text MATCHES "${expected_text}")
        message(FATAL_ERROR "FAIL: ${file} lacks '${expected_text}':\n${text}")
    endif()
endfunction()

function(expect_no_file_text file unexpected_text)
    if(NOT EXISTS "${file}")
        message(FATAL_ERROR "FAIL: ${file} does not exist")
    endif()
    file(READ "${file}" text)
    string(REPLACE "\r\n" "\n" text "${text}")
    if(text MATCHES "${unexpected_text}")
        message(FATAL_ERROR "FAIL: ${file} contains '${unexpected_text}':\n${text}")
    endif()
endfunction()

# write-notices.cmake copies every licence file, globs in sorted order.
set(source "${WORK_DIR}/notices/source")
file(WRITE "${source}/LICENSE" "main licence\n")
file(WRITE "${source}/LICENSES/b.txt" "licence b\n")
file(WRITE "${source}/LICENSES/a.txt" "licence a\n")
set(notices "${WORK_DIR}/notices/THIRD_PARTY_NOTICES.txt")
set(entries "one|1.0|MIT|https://example.com/one.tgz|${source}|LICENSE|LICENSES/*.txt"
            "two|2.0|Apache-2.0|https://example.com/two.tgz|${source}|LICENSES/b.txt")
# A list cannot pass through run_script's ARGN intact, so this call is made directly.
execute_process(COMMAND "${CMAKE_COMMAND}" "-DOUTPUT=${notices}" "-DENTRIES=${entries}"
                        -P "${deps}/write-notices.cmake"
                RESULT_VARIABLE status)
if(NOT status EQUAL 0)
    message(FATAL_ERROR "FAIL: write-notices.cmake failed for two entries")
endif()
expect_file_text("${notices}" "one 1.0\nLicence: MIT\nSource: https://example.com/one.tgz\n\n\
--- LICENSE ---\n\nmain licence\n\n--- LICENSES/a.txt ---\n\nlicence a\n\n\
--- LICENSES/b.txt ---\n\nlicence b\n")
expect_file_text("${notices}" "two 2.0\nLicence: Apache-2.0\n.*--- LICENSES/b.txt ---\n")
run_script(1 "Licence file 'COPYING' of one not found" "${deps}/write-notices.cmake"
           "-DOUTPUT=${notices}" "-DENTRIES=one|1.0|MIT|https://example.com|${source}|COPYING")
run_script(1 "Licence file 'docs/\\*.md' of one not found" "${deps}/write-notices.cmake"
           "-DOUTPUT=${notices}" "-DENTRIES=one|1.0|MIT|https://example.com|${source}|docs/*.md")
run_script(1 "Licence file 'LICENSES' of one not found" "${deps}/write-notices.cmake"
           "-DOUTPUT=${notices}" "-DENTRIES=one|1.0|MIT|https://example.com|${source}|LICENSES")
run_script(1 "No licence file given for one" "${deps}/write-notices.cmake"
           "-DOUTPUT=${notices}" "-DENTRIES=one|1.0|MIT|https://example.com|${source}")

# write-notices.cmake: a custom first line and the Visual C++ runtime paragraph (M4 design D17, D19).
execute_process(COMMAND "${CMAKE_COMMAND}" "-DOUTPUT=${notices}" "-DENTRIES=${entries}"
                        "-DHEADER=Third-party software in the rawreel packages" -DMSVC_RUNTIME=ON
                        -P "${deps}/write-notices.cmake"
                RESULT_VARIABLE status)
if(NOT status EQUAL 0)
    message(FATAL_ERROR "FAIL: write-notices.cmake failed with HEADER and MSVC_RUNTIME")
endif()
expect_file_text("${notices}" "^Third-party software in the rawreel packages\n")
expect_file_text("${notices}" "\nMicrosoft Visual C\\+\\+ runtime\nFiles: vcruntime140.dll")
expect_file_text("${notices}" "Licence: Microsoft Software License Terms for Microsoft Visual Studio")
execute_process(COMMAND "${CMAKE_COMMAND}" "-DOUTPUT=${notices}" "-DENTRIES=${entries}"
                        -DMSVC_RUNTIME=OFF -P "${deps}/write-notices.cmake"
                RESULT_VARIABLE status)
if(NOT status EQUAL 0)
    message(FATAL_ERROR "FAIL: write-notices.cmake failed with MSVC_RUNTIME=OFF")
endif()
expect_file_text("${notices}" "^Third-party software used by rawreel and the dvv libraries\n")
expect_no_file_text("${notices}" "Visual C\\+\\+ runtime")

# write-notices.cmake copies an entry's licence supplements after its licence files, with their
# origin, and checks their SHA256 again.
set(supplement "${WORK_DIR}/notices/supplement/LICENSE")
file(WRITE "${supplement}" "supplement text\n")
file(SHA256 "${supplement}" supplement_hash)
set(origin "Lib|2.1|https://example.com/LICENSE")
execute_process(COMMAND "${CMAKE_COMMAND}" "-DOUTPUT=${notices}" "-DENTRIES=${entries}"
                        "-DSUPPLEMENTS=one|${supplement}|${supplement_hash}|lib/LICENSE|${origin}"
                        -P "${deps}/write-notices.cmake"
                RESULT_VARIABLE status)
if(NOT status EQUAL 0)
    message(FATAL_ERROR "FAIL: write-notices.cmake failed with SUPPLEMENTS")
endif()
expect_file_text("${notices}" "\n--- LICENSES/b.txt ---\n\nlicence b\n\n\
--- lib/LICENSE \\(supplement: not in the one 1\\.0 archive\\) ---\n\
From Lib 2\\.1: https://example\\.com/LICENSE\n\nsupplement text\n\n=+\ntwo 2\\.0\n")
expect_no_file_text("${notices}" "two 2\\.0\n.*supplement")
set(one "one|1.0|MIT|https://example.com|${source}|LICENSE")
run_script(1 "Licence supplement 'lib/LICENSE' of one does not match its SHA256 pin"
           "${deps}/write-notices.cmake" "-DOUTPUT=${notices}" "-DENTRIES=${one}"
           "-DSUPPLEMENTS=one|${supplement}|${hash_zero}|lib/LICENSE|${origin}")
run_script(1 "Licence supplement 'lib/LICENSE' of one not found"
           "${deps}/write-notices.cmake" "-DOUTPUT=${notices}" "-DENTRIES=${one}"
           "-DSUPPLEMENTS=one|${supplement}.missing|${supplement_hash}|lib/LICENSE|${origin}")

# dvv_licence_supplement(): the file lies in licenses/<name>-supplement/ next to the declaring file
# and must match its pin; the entry may be built on another platform only.
set(probe "${WORK_DIR}/supplement-pin/probe.cmake")
file(WRITE "${WORK_DIR}/supplement-pin/licenses/probe-supplement/a/LICENSE" "probe licence\n")
file(SHA256 "${WORK_DIR}/supplement-pin/licenses/probe-supplement/a/LICENSE" probe_hash)
file(WRITE "${probe}" "include(\"${CMAKE_CURRENT_LIST_DIR}/../../cmake/DvvThirdParty.cmake\")
set(CMAKE_SYSTEM_NAME Windows)
if(NOT PROBE_UNDECLARED)
    dvv_third_party(probe VERSION 1.0 URL https://example.com/p.tgz SHA256 ${hash_zero}
        SPDX MIT LINKAGE runtime LICENSE_FILES LICENSE ONLY_ON Linux PREBUILT)
endif()
dvv_licence_supplement(probe FILE \"\${PROBE_FILE}\" COMPONENT Lib VERSION 2.1
    URL https://example.com/LICENSE SHA256 \"\${PROBE_SHA256}\")
get_property(supplements GLOBAL PROPERTY DVV_THIRD_PARTY_probe_SUPPLEMENTS)
message(STATUS \"supplements=<\${supplements}>\")
")
run_script(0 "supplements=<[^>]*/supplement-pin/licenses/probe-supplement/a/LICENSE\\|\
${probe_hash}\\|a/LICENSE\\|Lib\\|2\\.1\\|https://example\\.com/LICENSE>" "${probe}"
           -DPROBE_FILE=a/LICENSE -DPROBE_SHA256=${probe_hash})
run_script(1 "dvv_licence_supplement\\(probe\\): licenses/probe-supplement/a/MISSING not found"
           "${probe}" -DPROBE_FILE=a/MISSING -DPROBE_SHA256=${probe_hash})
run_script(1 "a/LICENSE has SHA256 ${probe_hash}, pinned ${hash_zero}" "${probe}"
           -DPROBE_FILE=a/LICENSE -DPROBE_SHA256=${hash_zero})
run_script(1 "SHA256 must be 64 lower-case hex digits" "${probe}"
           -DPROBE_FILE=a/LICENSE -DPROBE_SHA256=${probe_hash}0)
run_script(1 "dvv_licence_supplement\\(probe\\): probe is not declared before it" "${probe}"
           -DPROBE_FILE=a/LICENSE -DPROBE_SHA256=${probe_hash} -DPROBE_UNDECLARED=1)
run_script(1 "FILE must be a relative path with '/' and without '..'" "${probe}"
           -DPROBE_FILE=../probe.cmake -DPROBE_SHA256=${probe_hash})

# post-install/vk-bootstrap.cmake installs the source file that dvv-gpu compiles.
set(source "${WORK_DIR}/vk-bootstrap/source")
set(prefix "${WORK_DIR}/vk-bootstrap/prefix")
file(WRITE "${source}/src/VkBootstrap.cpp" "// vk-bootstrap\n")
run_script(0 "" "${deps}/post-install/vk-bootstrap.cmake" "-DSOURCE_DIR=${source}"
           "-DPREFIX=${prefix}")
expect_file_text("${prefix}/src/vk-bootstrap/VkBootstrap.cpp" "// vk-bootstrap")
run_script(1 "pass -DPREFIX" "${deps}/post-install/vk-bootstrap.cmake" "-DSOURCE_DIR=${source}")

# post-install/Vulkan-ValidationLayers.cmake makes the Linux manifest name its library relative to
# itself and leaves the Windows layout alone.
set(script "${deps}/post-install/Vulkan-ValidationLayers.cmake")
set(prefix "${WORK_DIR}/validation/linux")
set(manifest "${prefix}/share/vulkan/explicit_layer.d/VkLayer_khronos_validation.json")
file(WRITE "${manifest}" "{\n    \"layer\": {\n        \"name\": \"VK_LAYER_KHRONOS_validation\",\n\
        \"library_path\": \"libVkLayer_khronos_validation.so\",\n        \"api_version\": \"1.4.365\"\n\
    }\n}\n")
set(relative "\"library_path\": \"../../../lib/libVkLayer_khronos_validation.so\",\n")
run_script(1 "libVkLayer_khronos_validation.so is not in <prefix>/lib" "${script}"
           "-DPREFIX=${prefix}")
file(WRITE "${prefix}/lib/libVkLayer_khronos_validation.so" "")
run_script(0 "" "${script}" "-DPREFIX=${prefix}")
expect_file_text("${manifest}" "\"name\": \"VK_LAYER_KHRONOS_validation\",\n *${relative}")
run_script(0 "" "${script}" "-DPREFIX=${prefix}")
expect_file_text("${manifest}" "${relative} *\"api_version\"")
set(prefix "${WORK_DIR}/validation/windows")
file(WRITE "${prefix}/bin/VkLayer_khronos_validation.json"
     "{\"layer\": {\"library_path\": \".\\\\VkLayer_khronos_validation.dll\"}}")
run_script(0 "" "${script}" "-DPREFIX=${prefix}")
expect_file_text("${prefix}/bin/VkLayer_khronos_validation.json"
                 "\"library_path\": \"\\.\\\\\\\\VkLayer_khronos_validation\\.dll\"")
run_script(1 "no VkLayer_khronos_validation.json in the prefix" "${script}"
           "-DPREFIX=${WORK_DIR}/validation/empty")

# dvv_third_party_build_configs(): a single-config generator builds Release only.
set(probe "${WORK_DIR}/configs/probe.cmake")
file(WRITE "${probe}" "include(\"${CMAKE_CURRENT_LIST_DIR}/../../cmake/DvvThirdParty.cmake\")
set(CMAKE_SYSTEM_NAME Windows)
set(configs_arg \"\")
if(PROBE_CONFIGS STREQUAL \"both\")
    set(configs_arg CONFIGS Debug Release)
elseif(PROBE_CONFIGS STREQUAL \"release\")
    set(configs_arg CONFIGS Release)
endif()
dvv_third_party(probe VERSION 1.0 URL https://example.com/p.tgz
    SHA256 0000000000000000000000000000000000000000000000000000000000000000
    SPDX MIT LINKAGE static LICENSE_FILES LICENSE \${configs_arg})
dvv_third_party_build_configs(probe \"\${MULTI_CONFIG}\" configs)
message(STATUS \"configs=<\${configs}>\")
")
run_script(1 "dvv_third_party\\(probe\\): CONFIGS Debug Release needs a multi-config generator"
           "${probe}" -DMULTI_CONFIG=0 -DPROBE_CONFIGS=both)
run_script(0 "configs=<Release>" "${probe}" -DMULTI_CONFIG=0 -DPROBE_CONFIGS=none)
run_script(0 "configs=<Release>" "${probe}" -DMULTI_CONFIG=0 -DPROBE_CONFIGS=release)
run_script(0 "configs=<Debug;Release>" "${probe}" -DMULTI_CONFIG=1 -DPROBE_CONFIGS=both)

message(STATUS "superbuild script tests passed")
