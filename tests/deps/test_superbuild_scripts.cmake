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
if(DEFINED PROBE_SYSTEM)
    set(CMAKE_SYSTEM_NAME \${PROBE_SYSTEM})
endif()
set(platforms_arg \"\")
if(DEFINED PROBE_PLATFORMS)
    string(REPLACE \",\" \";\" platforms \"\${PROBE_PLATFORMS}\")
    set(platforms_arg PLATFORMS \${platforms})
endif()
if(NOT PROBE_UNDECLARED)
    dvv_third_party(probe VERSION 1.0 URL https://example.com/p.tgz SHA256 ${hash_zero}
        SPDX MIT LINKAGE runtime LICENSE_FILES LICENSE ONLY_ON Linux PREBUILT)
endif()
dvv_licence_supplement(probe FILE \"\${PROBE_FILE}\" COMPONENT Lib VERSION 2.1
    URL https://example.com/LICENSE SHA256 \"\${PROBE_SHA256}\" \${platforms_arg})
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
# PLATFORMS: the supplement is attached only where its component is built; its file is still
# checked everywhere.
run_script(0 "supplements=<[^>]*/a/LICENSE\\|" "${probe}" -DPROBE_FILE=a/LICENSE
           -DPROBE_SHA256=${probe_hash} -DPROBE_SYSTEM=Linux "-DPROBE_PLATFORMS=Windows,Linux")
run_script(0 "supplements=<>" "${probe}" -DPROBE_FILE=a/LICENSE -DPROBE_SHA256=${probe_hash}
           -DPROBE_SYSTEM=Darwin "-DPROBE_PLATFORMS=Windows,Linux")
run_script(1 "a/LICENSE has SHA256 ${probe_hash}, pinned ${hash_zero}" "${probe}"
           -DPROBE_FILE=a/LICENSE -DPROBE_SHA256=${hash_zero} -DPROBE_SYSTEM=Darwin
           "-DPROBE_PLATFORMS=Windows,Linux")
run_script(1 "dvv_licence_supplement\\(probe\\): PLATFORMS must name Windows, Linux or Darwin, \
not 'FreeBSD'" "${probe}" -DPROBE_FILE=a/LICENSE -DPROBE_SHA256=${probe_hash}
           -DPROBE_PLATFORMS=FreeBSD)

# post-install/vk-bootstrap.cmake installs the source file that dvv-gpu compiles.
set(source "${WORK_DIR}/vk-bootstrap/source")
set(prefix "${WORK_DIR}/vk-bootstrap/prefix")
file(WRITE "${source}/src/VkBootstrap.cpp" "// vk-bootstrap\n")
run_script(0 "" "${deps}/post-install/vk-bootstrap.cmake" "-DSOURCE_DIR=${source}"
           "-DPREFIX=${prefix}")
expect_file_text("${prefix}/src/vk-bootstrap/VkBootstrap.cpp" "// vk-bootstrap")
run_script(1 "pass -DPREFIX" "${deps}/post-install/vk-bootstrap.cmake" "-DSOURCE_DIR=${source}")

# post-install/Vulkan-ValidationLayers.cmake installs the layer of the extracted LunarG SDK (its top
# folder dropped by the extract step) and its manifest, keeps only the licence file the notices
# read and removes the rest of the SDK. Linux: x86_64/lib/<layer>.so into <prefix>/lib (debug
# sections stripped when a strip program is found), the manifest into
# <prefix>/share/vulkan/explicit_layer.d with library_path relative to it, LICENSE.txt kept. Windows
# (the installer's Bin/ folder): DLL and manifest into <prefix>/bin, the layer's LICENSE.txt
# (a licence supplement) kept.
set(script "${deps}/post-install/Vulkan-ValidationLayers.cmake")
set(layer VkLayer_khronos_validation)
set(source "${WORK_DIR}/validation/linux/source")
set(prefix "${WORK_DIR}/validation/linux/prefix")
file(WRITE "${source}/x86_64/lib/lib${layer}.so" "layer\n")
file(WRITE "${source}/x86_64/lib/libvulkan.so.1" "loader\n")
file(WRITE "${source}/x86_64/share/vulkan/explicit_layer.d/${layer}.json"
     "{\n    \"layer\": {\n        \"name\": \"VK_LAYER_KHRONOS_validation\",\n\
        \"library_path\": \"libVkLayer_khronos_validation.so\",\n        \"api_version\": \"1.4.363\"\n\
    }\n}\n")
file(WRITE "${source}/LICENSE.txt" "LunarG statement\n")
file(WRITE "${source}/setup-env.sh" "sdk\n")
set(linux_args "-DSOURCE_DIR=${source}" "-DPREFIX=${prefix}" -DPLATFORM=Linux)
run_script(1 "pass -DPREFIX" "${script}" "-DSOURCE_DIR=${source}")
run_script(0 "no strip program: lib${layer}\\.so keeps its debug sections" "${script}" ${linux_args}
           "-DSTRIP=")
expect_file_text("${prefix}/lib/lib${layer}.so" "^layer\n$")
expect_file_text("${prefix}/share/vulkan/explicit_layer.d/${layer}.json"
                 "\"name\": \"VK_LAYER_KHRONOS_validation\",\n *\"library_path\": \
\"\\.\\./\\.\\./\\.\\./lib/libVkLayer_khronos_validation\\.so\",\n *\"api_version\"")
file(GLOB_RECURSE kept LIST_DIRECTORIES false RELATIVE "${source}" "${source}/*")
if(NOT kept STREQUAL "LICENSE.txt")
    message(FATAL_ERROR "FAIL: the Linux post-install left '${kept}' in SOURCE_DIR")
endif()
expect_file_text("${source}/LICENSE.txt" "^LunarG statement\n$")
if(EXISTS "${prefix}/lib/libvulkan.so.1")
    message(FATAL_ERROR "FAIL: the Linux post-install installed more than the layer")
endif()
# Run again after the SDK is gone (the extract step did not run again): nothing to do.
run_script(0 "the validation layer is already installed" "${script}" ${linux_args})
# Without the SDK and with an installed file missing it cannot recover.
file(REMOVE "${prefix}/share/vulkan/explicit_layer.d/${layer}.json")
run_script(1 "the LunarG SDK is not in .* and .*${layer}\\.json is missing; run bootstrap with \
--force" "${script}" ${linux_args})
# A strip program found strips the layer's debug sections. The fake strip records its arguments,
# so not on Windows.
if(NOT CMAKE_HOST_WIN32)
    set(source "${WORK_DIR}/validation/strip/source")
    set(prefix "${WORK_DIR}/validation/strip/prefix")
    set(strip "${WORK_DIR}/validation/strip/strip")
    file(WRITE "${source}/x86_64/lib/lib${layer}.so" "layer\n")
    file(WRITE "${source}/x86_64/share/vulkan/explicit_layer.d/${layer}.json"
         "{\"layer\": {\"library_path\": \"../../../lib/libVkLayer_khronos_validation.so\"}}\n")
    file(WRITE "${source}/LICENSE.txt" "LunarG statement\n")
    file(WRITE "${strip}" "#!/bin/sh\necho \"$@\" > '${strip}.args'\n")
    file(CHMOD "${strip}" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
    run_script(0 "" "${script}" "-DSOURCE_DIR=${source}" "-DPREFIX=${prefix}"
               -DPLATFORM=Linux "-DSTRIP=${strip}")
    expect_file_text("${strip}.args" "^--strip-debug ${prefix}/lib/lib${layer}\\.so\n$")
endif()

set(source "${WORK_DIR}/validation/windows/source")
set(prefix "${WORK_DIR}/validation/windows/prefix")
file(WRITE "${source}/${layer}.dll" "layer\n")
file(WRITE "${source}/${layer}.pdb" "symbols\n")
file(WRITE "${source}/${layer}.json"
     "{\"layer\": {\"library_path\": \".\\\\VkLayer_khronos_validation.dll\"}}\n")
file(WRITE "${source}/vulkan-1.dll" "loader\n")
set(windows_args "-DSOURCE_DIR=${source}" "-DPREFIX=${prefix}" -DPLATFORM=Windows)
run_script(0 "" "${script}" ${windows_args})
expect_file_text("${prefix}/bin/${layer}.dll" "^layer\n$")
expect_file_text("${prefix}/bin/${layer}.json"
                 "\"library_path\": \"\\.\\\\\\\\VkLayer_khronos_validation\\.dll\"")
foreach(gone IN ITEMS "${prefix}/bin/${layer}.pdb" "${prefix}/bin/vulkan-1.dll"
                      "${prefix}/share/vulkan/explicit_layer.d/${layer}.json")
    if(EXISTS "${gone}")
        message(FATAL_ERROR "FAIL: ${gone} exists after the Windows post-install")
    endif()
endforeach()
file(GLOB_RECURSE kept LIST_DIRECTORIES false RELATIVE "${source}" "${source}/*")
if(NOT kept STREQUAL "vulkan-validationlayers/LICENSE.txt")
    message(FATAL_ERROR "FAIL: the Windows post-install left '${kept}' in SOURCE_DIR")
endif()
file(SHA256 "${source}/vulkan-validationlayers/LICENSE.txt" kept_hash)
file(SHA256 "${deps}/licenses/Vulkan-ValidationLayers-supplement/vulkan-validationlayers/LICENSE.txt"
     supplement_hash)
if(NOT kept_hash STREQUAL supplement_hash)
    message(FATAL_ERROR "FAIL: the kept LICENSE.txt is not the layer's licence supplement")
endif()
run_script(0 "the validation layer is already installed" "${script}" ${windows_args})
file(REMOVE "${prefix}/bin/${layer}.dll")
run_script(1 "the LunarG SDK is not in .* and .*${layer}\\.dll is missing; run bootstrap with \
--force" "${script}" ${windows_args})
# An SDK layout the script does not know (the top folder not dropped, or a new top-level entry) is
# reported as such, whatever is installed: --force would extract it the same way again.
set(source "${WORK_DIR}/validation/unexpected-windows/source")
set(prefix "${WORK_DIR}/validation/unexpected-windows/prefix")
file(WRITE "${source}/Bin/${layer}.dll" "layer\n")
file(WRITE "${source}/Lib/vulkan-1.lib" "loader\n")
run_script(1 "unexpected LunarG SDK layout in .*unexpected-windows/source \\(no .*${layer}\\.dll; \
found Bin, Lib\\)" "${script}" "-DSOURCE_DIR=${source}" "-DPREFIX=${prefix}" -DPLATFORM=Windows)
set(source "${WORK_DIR}/validation/unexpected-linux/source")
set(prefix "${WORK_DIR}/validation/unexpected-linux/prefix")
file(WRITE "${source}/LICENSE.txt" "LunarG statement\n")
file(WRITE "${source}/1.4.363.1/x86_64/lib/lib${layer}.so" "layer\n")
file(WRITE "${prefix}/lib/lib${layer}.so" "source-built layer\n")
file(WRITE "${prefix}/share/vulkan/explicit_layer.d/${layer}.json" "{}\n")
run_script(1 "unexpected LunarG SDK layout in .*unexpected-linux/source \\(no .*lib${layer}\\.so; \
found 1\\.4\\.363\\.1\\)" "${script}" "-DSOURCE_DIR=${source}" "-DPREFIX=${prefix}"
           -DPLATFORM=Linux)
run_script(1 "PLATFORM must be Windows or Linux" "${script}" "-DSOURCE_DIR=${source}"
           "-DPREFIX=${prefix}" -DPLATFORM=Darwin)

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

# dvv_third_party_common_args(): the arguments every built project gets. On Apple they carry the
# deployment target and the architectures (a plain build would target the SDK's version); elsewhere
# they are unchanged.
set(probe "${WORK_DIR}/common-args/probe.cmake")
file(WRITE "${probe}" "include(\"${CMAKE_CURRENT_LIST_DIR}/../../cmake/DvvThirdParty.cmake\")
set(APPLE \"\${PROBE_APPLE}\")
set(CMAKE_GENERATOR \"\${PROBE_GENERATOR}\")
set(CMAKE_C_COMPILER cc-probe)
set(CMAKE_CXX_COMPILER cxx-probe)
set(CMAKE_OSX_DEPLOYMENT_TARGET \"\${PROBE_TARGET}\")
set(CMAKE_OSX_ARCHITECTURES \"\${PROBE_ARCHITECTURES}\")
dvv_third_party_common_args(args)
list(JOIN args \"|\" args)
message(STATUS \"args=<\${args}>\")
")
set(base_args "--no-warn-unused-cli\\|-DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>\\|\
-DCMAKE_PREFIX_PATH=<INSTALL_DIR>\\|-DCMAKE_BUILD_TYPE=Release\\|-DCMAKE_C_COMPILER=cc-probe\\|\
-DCMAKE_CXX_COMPILER=cxx-probe")
# On Apple every compiled language maps the project's source, build and install folders out of
# __FILE__ and debug information, so shipped binaries carry no machine path.
set(maps "-ffile-prefix-map=<SOURCE_DIR>/= -ffile-prefix-map=<BINARY_DIR>/= \
-ffile-prefix-map=<INSTALL_DIR>/=")
run_script(0 "args=<${base_args}\\|-DCMAKE_OSX_DEPLOYMENT_TARGET=27\\.0\\|\
-DCMAKE_OSX_ARCHITECTURES=arm64\\|-DCMAKE_OBJC_COMPILER=cc-probe\\|\
-DCMAKE_OBJCXX_COMPILER=cxx-probe\\|-DCMAKE_C_FLAGS=${maps}\\|-DCMAKE_CXX_FLAGS=${maps}\\|\
-DCMAKE_OBJC_FLAGS=${maps}\\|-DCMAKE_OBJCXX_FLAGS=${maps}>" "${probe}" -DPROBE_APPLE=1
           -DPROBE_GENERATOR=Ninja -DPROBE_TARGET=27.0 -DPROBE_ARCHITECTURES=arm64)
run_script(1 "CMAKE_OSX_DEPLOYMENT_TARGET and CMAKE_OSX_ARCHITECTURES must be set on Apple"
           "${probe}" -DPROBE_APPLE=1 -DPROBE_GENERATOR=Ninja -DPROBE_ARCHITECTURES=arm64)
run_script(0 "args=<${base_args}>" "${probe}" -DPROBE_APPLE=0 -DPROBE_GENERATOR=Ninja
           -DPROBE_TARGET=27.0 -DPROBE_ARCHITECTURES=arm64)
run_script(0 "args=<${base_args}\\|-DCMAKE_VS_GLOBALS=UseMultiToolTask=true>" "${probe}"
           -DPROBE_APPLE=0 "-DPROBE_GENERATOR=Visual Studio 18 2026")

# dvv_third_party_shared_archive(): a PREBUILT entry with the URL and SHA256 of an entry it depends
# on shares that entry's archive.
set(probe "${WORK_DIR}/shared-archive/probe.cmake")
file(WRITE "${probe}" "include(\"${CMAKE_CURRENT_LIST_DIR}/../../cmake/DvvThirdParty.cmake\")
set(CMAKE_SYSTEM_NAME Darwin)
set(sdk URL https://example.com/sdk.zip SHA256 ${hash_zero} SPDX MIT LICENSE_FILES LICENSE PREBUILT)
dvv_third_party(other VERSION 1 URL https://example.com/other.zip
    SHA256 1111111111111111111111111111111111111111111111111111111111111111
    SPDX MIT LINKAGE tool LICENSE_FILES LICENSE PREBUILT)
dvv_third_party(driver VERSION 1 \${sdk} LINKAGE runtime)
dvv_third_party(tool VERSION 1 \${sdk} LINKAGE tool DEPENDS other driver)
dvv_third_party(alone VERSION 1 \${sdk} LINKAGE tool)
foreach(name IN ITEMS other driver tool alone)
    dvv_third_party_shared_archive(\${name} shared)
    message(STATUS \"\${name}=<\${shared}>\")
endforeach()
")
run_script(0 "other=<> -- driver=<> -- tool=<driver> -- alone=<>" "${probe}")

# post-install/kosmickrisp.cmake runs the LunarG SDK installer (its core component only) into the
# build tree, copies the KosmicKrisp driver, its manifest (library_path relative to the manifest)
# and vulkaninfo into the prefix, keeps the SDK's licence statement for the notices and removes the
# installer and the installed SDK. The fake installer is a shell script, so not on Windows.
if(NOT CMAKE_HOST_WIN32)
    set(script "${deps}/post-install/kosmickrisp.cmake")
    set(source "${WORK_DIR}/kosmickrisp/source")
    set(binary "${WORK_DIR}/kosmickrisp/binary")
    set(prefix "${WORK_DIR}/kosmickrisp/prefix")
    set(installer "${source}/Contents/MacOS/vulkansdk-macOS-1.4.363.1")
    set(args_file "${WORK_DIR}/kosmickrisp/installer-args.txt")
    # The fake records its arguments and installs the SDK layout under --root.
    file(WRITE "${installer}" "#!/bin/sh
echo \"$@\" > '${args_file}'
while [ $# -gt 0 ]; do
    if [ \"$1\" = --root ]; then root=$2; fi
    shift
done
mkdir -p \"$root/macOS/lib\" \"$root/macOS/bin\" \"$root/macOS/share/vulkan/icd.d\" \"$root/Licenses\"
mkdir -p \"$root/macOS/share/vulkan/explicit_layer.d\"
echo layer > \"$root/macOS/lib/libVkLayer_khronos_validation.dylib\"
printf '{\\n    \"layer\": {\\n        \"library_path\": \"libVkLayer_khronos_validation.dylib\",\\n        \"api_version\": \"1.4.363\"\\n    }\\n}\\n' > \"$root/macOS/share/vulkan/explicit_layer.d/VkLayer_khronos_validation.json\"
echo driver > \"$root/macOS/lib/libvulkan_kosmickrisp.dylib\"
echo moltenvk > \"$root/macOS/lib/libMoltenVK.dylib\"
printf '#!/bin/sh\\necho vulkaninfo\\n' > \"$root/macOS/bin/vulkaninfo\"
chmod +x \"$root/macOS/bin/vulkaninfo\"
printf '{\\n    \"ICD\": {\\n        \"api_version\": \"1.4.0\",\\n        \"library_path\": \"libvulkan_kosmickrisp.dylib\"\\n    },\\n    \"file_format_version\": \"1.0.0\"\\n}\\n' > \"$root/macOS/share/vulkan/icd.d/libkosmickrisp_icd.json\"
echo moltenvk > \"$root/macOS/share/vulkan/icd.d/MoltenVK_icd.json\"
echo 'LunarG statement' > \"$root/Licenses/LICENSE.txt\"
echo 'Revisions' > \"$root/VERSIONS.txt\"
")
    file(CHMOD "${installer}" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
    run_script(1 "pass -DBINARY_DIR" "${script}" "-DSOURCE_DIR=${source}" "-DPREFIX=${prefix}")
    run_script(0 "" "${script}" "-DSOURCE_DIR=${source}" "-DPREFIX=${prefix}"
               "-DBINARY_DIR=${binary}")
    expect_file_text("${args_file}" "^--root ${binary}/sdk --accept-licenses --default-answer \
--confirm-command install com\\.lunarg\\.vulkan\\.core\n$")
    expect_file_text("${prefix}/lib/libvulkan_kosmickrisp.dylib" "^driver\n$")
    expect_file_text("${prefix}/share/vulkan/icd.d/libkosmickrisp_icd.json"
        "\"api_version\": \"1\\.4\\.0\",\n *\"library_path\": \"\\.\\./\\.\\./\\.\\./lib/\
libvulkan_kosmickrisp\\.dylib\"\n")
    # The validation layer of the same SDK (entry Vulkan-ValidationLayers), the dylib whole.
    expect_file_text("${prefix}/lib/libVkLayer_khronos_validation.dylib" "^layer\n$")
    expect_file_text("${prefix}/share/vulkan/explicit_layer.d/VkLayer_khronos_validation.json"
        "\"library_path\": \"\\.\\./\\.\\./\\.\\./lib/libVkLayer_khronos_validation\\.dylib\",\n \
*\"api_version\"")
    expect_file_text("${prefix}/bin/vulkaninfo" "echo vulkaninfo")
    execute_process(COMMAND "${prefix}/bin/vulkaninfo" RESULT_VARIABLE status OUTPUT_QUIET)
    if(NOT status EQUAL 0)
        message(FATAL_ERROR "FAIL: the copied vulkaninfo is not executable")
    endif()
    expect_file_text("${source}/Licenses/LICENSE.txt" "LunarG statement")
    expect_file_text("${source}/VERSIONS.txt" "Revisions")
    foreach(gone IN ITEMS "${prefix}/lib/libMoltenVK.dylib"
                          "${prefix}/share/vulkan/icd.d/MoltenVK_icd.json" "${binary}/sdk"
                          "${source}/Contents")
        if(EXISTS "${gone}")
            message(FATAL_ERROR "FAIL: ${gone} exists after the KosmicKrisp post-install")
        endif()
    endforeach()
    # Run again without the installer (the extract step did not run again): nothing to do.
    run_script(0 "KosmicKrisp is already installed" "${script}" "-DSOURCE_DIR=${source}"
               "-DPREFIX=${prefix}" "-DBINARY_DIR=${binary}")
    # Without the installer and without the installed files it cannot recover.
    file(REMOVE "${prefix}/share/vulkan/explicit_layer.d/VkLayer_khronos_validation.json")
    run_script(1 "VkLayer_khronos_validation\\.json is missing; run bootstrap with --force"
               "${script}" "-DSOURCE_DIR=${source}" "-DPREFIX=${prefix}" "-DBINARY_DIR=${binary}")
    file(REMOVE "${prefix}/lib/libvulkan_kosmickrisp.dylib")
    run_script(1 "the SDK installer is not in .*; run bootstrap with --force" "${script}"
               "-DSOURCE_DIR=${source}" "-DPREFIX=${prefix}" "-DBINARY_DIR=${binary}")
    # A failing installer fails the step.
    file(MAKE_DIRECTORY "${source}/Contents/MacOS")
    file(WRITE "${installer}" "#!/bin/sh\necho 'installer broke' >&2\nexit 3\n")
    file(CHMOD "${installer}" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
    run_script(1 "the Vulkan SDK installer failed \\(3\\).*installer broke" "${script}"
               "-DSOURCE_DIR=${source}" "-DPREFIX=${prefix}" "-DBINARY_DIR=${binary}")
endif()


# dvv_third_party_separate_prefix_hash(): the marker of an entry installed into its own prefix is
# the SHA256 of one line per key (VERSION, URL, SHA256, LICENSE_FILES, CONFIGS, CMAKE_ARGS), then
# RECIPE_REV and TOOLCHAIN. SPDX and the other entries do not enter it.
set(probe "${WORK_DIR}/separate-prefix/probe.cmake")
file(WRITE "${probe}" "include(\"${CMAKE_CURRENT_LIST_DIR}/../../cmake/DvvThirdParty.cmake\")
set(CMAKE_SYSTEM_NAME Darwin)
if(DEFINED PROBE_REV)
    set(DVV_SEPARATE_PREFIX_RECIPE_REV \${PROBE_REV})
endif()
if(NOT DEFINED PROBE_KIND)
    set(PROBE_KIND \"SEPARATE_PREFIX wx\")
endif()
separate_arguments(kind UNIX_COMMAND \"\${PROBE_KIND}\")
dvv_third_party(other VERSION \"\${OTHER_VERSION}\" URL https://example.com/other.tgz
    SHA256 ${hash_zero} SPDX MIT LINKAGE static LICENSE_FILES LICENSE)
dvv_third_party(probe VERSION \"\${PROBE_VERSION}\" URL https://example.com/p.tgz
    SHA256 1111111111111111111111111111111111111111111111111111111111111111
    SPDX \"\${PROBE_SPDX}\" LINKAGE static LICENSE_FILES LICENSE docs/*.txt
    CMAKE_ARGS -DA=1 \"\${PROBE_ARG}\" \${kind})
dvv_third_party_separate_prefix_hash(probe \"\${PROBE_TOOLCHAIN}\" hash)
message(STATUS \"hash=<\${hash}>\")
")
# probe_hash(<out_var> [-D<name>=<value>...]): the probe's hash for the default inputs, changed by
# the given definitions.
function(probe_hash out_var)
    set(defaults -DPROBE_VERSION=1.0 -DPROBE_ARG=-DB=2 -DPROBE_SPDX=MIT -DOTHER_VERSION=1.0
                 -DPROBE_TOOLCHAIN=appleclang)
    execute_process(COMMAND "${CMAKE_COMMAND}" ${defaults} ${ARGN} -P "${probe}"
                    RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
    if(NOT status EQUAL 0 OR NOT out MATCHES "hash=<([0-9a-f]+)>")
        message(FATAL_ERROR "FAIL: the separate-prefix probe (${ARGN}) failed:\n${out}${err}")
    endif()
    string(LENGTH "${CMAKE_MATCH_1}" length)
    if(NOT length EQUAL 64)
        message(FATAL_ERROR "FAIL: the separate-prefix hash '${CMAKE_MATCH_1}' is not 64 hex")
    endif()
    set(${out_var} "${CMAKE_MATCH_1}" PARENT_SCOPE)
endfunction()
probe_hash(base)
probe_hash(again)
if(NOT base STREQUAL again)
    message(FATAL_ERROR "FAIL: the separate-prefix hash differs between two calls")
endif()
string(SHA256 expected "VERSION=1.0
URL=https://example.com/p.tgz
SHA256=1111111111111111111111111111111111111111111111111111111111111111
LICENSE_FILES=LICENSE;docs/*.txt
CONFIGS=Release
CMAKE_ARGS=-DA=1;-DB=2
RECIPE_REV=1
TOOLCHAIN=appleclang
")
if(NOT base STREQUAL expected)
    message(FATAL_ERROR "FAIL: the separate-prefix hash is not the SHA256 of its key lines")
endif()
foreach(change IN ITEMS -DPROBE_ARG=-DB=3 -DPROBE_VERSION=1.1 -DPROBE_REV=2
                        -DPROBE_TOOLCHAIN=clang)
    probe_hash(changed ${change})
    if(changed STREQUAL base)
        message(FATAL_ERROR "FAIL: the separate-prefix hash ignores ${change}")
    endif()
endforeach()
foreach(change IN ITEMS -DPROBE_SPDX=BSD-3-Clause -DOTHER_VERSION=2.0)
    probe_hash(changed ${change})
    if(NOT changed STREQUAL base)
        message(FATAL_ERROR "FAIL: the separate-prefix hash depends on ${change}")
    endif()
endforeach()
# The suffix is a plain folder-name part; a PREBUILT entry has no install to move; the hash needs
# an entry with a separate prefix.
run_script(1 "dvv_third_party\\(probe\\): SEPARATE_PREFIX must match \\^\\[a-z0-9\\]\\+\\$" "${probe}"
           -DPROBE_VERSION=1.0 -DPROBE_ARG=-DB=2 -DPROBE_SPDX=MIT -DOTHER_VERSION=1.0
           -DPROBE_TOOLCHAIN=appleclang "-DPROBE_KIND=SEPARATE_PREFIX Wx")
run_script(1 "dvv_third_party\\(probe\\): SEPARATE_PREFIX is not for PREBUILT" "${probe}"
           -DPROBE_VERSION=1.0 -DPROBE_ARG=-DB=2 -DPROBE_SPDX=MIT -DOTHER_VERSION=1.0
           -DPROBE_TOOLCHAIN=appleclang "-DPROBE_KIND=SEPARATE_PREFIX wx PREBUILT")
run_script(1 "dvv_third_party_separate_prefix_hash\\(probe\\): probe has no SEPARATE_PREFIX here"
           "${probe}" -DPROBE_VERSION=1.0 -DPROBE_ARG=-DB=2 -DPROBE_SPDX=MIT -DOTHER_VERSION=1.0
           -DPROBE_TOOLCHAIN=appleclang "-DPROBE_KIND=SHIPPED")

# tools/separate-prefix-hash.cmake prints the hash the superbuild computes for this host, for
# bootstrap and the CI cache key. The tool fixes DVV_BUNDLE_FFMPEG ON; the superbuild may run with
# OFF, so the hash must not depend on it: the host probe requires the tool's hash with both values,
# and on each of the three systems the two values give the same hash.
set(tool "${CMAKE_CURRENT_LIST_DIR}/../../tools/separate-prefix-hash.cmake")
execute_process(COMMAND "${CMAKE_COMMAND}" -DNAME=wxWidgets -DTOOLCHAIN=appleclang -P "${tool}"
                RESULT_VARIABLE status OUTPUT_VARIABLE tool_out ERROR_VARIABLE err)
if(NOT status EQUAL 0 OR NOT tool_out MATCHES "^hash=[0-9a-f]+\n$")
    message(FATAL_ERROR "FAIL: separate-prefix-hash.cmake printed '${tool_out}' (${status}):\n${err}")
endif()
set(probe "${WORK_DIR}/separate-prefix/host-probe.cmake")
file(WRITE "${probe}" "include(\"${CMAKE_CURRENT_LIST_DIR}/../../cmake/DvvThirdParty.cmake\")
if(SYSTEM)
    set(CMAKE_SYSTEM_NAME \"\${SYSTEM}\")
else()
    set(CMAKE_SYSTEM_NAME \"\${CMAKE_HOST_SYSTEM_NAME}\")
endif()
set(DVV_BUNDLE_FFMPEG \${BUNDLE})
include(\"${deps}/versions.cmake\")
dvv_third_party_separate_prefix_hash(wxWidgets appleclang hash)
message(STATUS \"hash=<\${hash}>\")
")
string(REGEX REPLACE "^hash=([0-9a-f]+)\n$" "\\1" tool_hash "${tool_out}")
string(LENGTH "${tool_hash}" length)
if(NOT length EQUAL 64)
    message(FATAL_ERROR "FAIL: separate-prefix-hash.cmake printed a hash of ${length} digits")
endif()
run_script(0 "hash=<${tool_hash}>" "${probe}" -DBUNDLE=ON)
run_script(0 "hash=<${tool_hash}>" "${probe}" -DBUNDLE=OFF)
foreach(system IN ITEMS Windows Linux Darwin)
    set(system_hashes "")
    foreach(bundle IN ITEMS ON OFF)
        execute_process(COMMAND "${CMAKE_COMMAND}" "-DSYSTEM=${system}" "-DBUNDLE=${bundle}"
                                -P "${probe}"
                        RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
        if(NOT status EQUAL 0 OR NOT "${out}${err}" MATCHES "hash=<([0-9a-f]+)>")
            message(FATAL_ERROR "FAIL: host probe for ${system}, ${bundle}:\n${out}${err}")
        endif()
        list(APPEND system_hashes "${CMAKE_MATCH_1}")
    endforeach()
    list(REMOVE_DUPLICATES system_hashes)
    list(LENGTH system_hashes count)
    if(NOT count EQUAL 1)
        message(FATAL_ERROR "FAIL: on ${system} the wxWidgets hash depends on DVV_BUNDLE_FFMPEG")
    endif()
endforeach()
run_script(1 "pass -DNAME=<entry> and -DTOOLCHAIN=<prefix folder name>" "${tool}" -DNAME=wxWidgets)

# deps/separate-prefix-finish.cmake: the last install command of an entry with a separate prefix
# copies its licence files (globs expanded, relative paths kept) into <sibling>/dvv-licences and
# then writes the marker, without a newline.
set(finish "${deps}/separate-prefix-finish.cmake")
set(source "${WORK_DIR}/finish/source")
set(sibling "${WORK_DIR}/finish/prefix-wx")
foreach(path IN ITEMS docs/licence.txt src/png/LICENSE licenses/a.txt licenses/b.txt)
    file(WRITE "${source}/${path}" "text of ${path}\n")
endforeach()
file(WRITE "${source}/licenses/c.md" "not a licence\n")
file(WRITE "${sibling}/dvv-licences/stale.txt" "old\n")
set(finish_args "-DSOURCE_DIR=${source}" "-DSIBLING=${sibling}" "-DHASH=${hash_zero}")
run_script(0 "" "${finish}" ${finish_args}
           "-DLICENSE_FILES=docs/licence.txt|src/png/LICENSE|licenses/*.txt")
file(GLOB_RECURSE copied LIST_DIRECTORIES false RELATIVE "${sibling}" "${sibling}/*")
list(SORT copied)
if(NOT copied STREQUAL "dvv-inputs.sha256;dvv-licences/docs/licence.txt;\
dvv-licences/licenses/a.txt;dvv-licences/licenses/b.txt;dvv-licences/src/png/LICENSE")
    message(FATAL_ERROR "FAIL: the finish script left '${copied}' in the sibling prefix")
endif()
expect_file_text("${sibling}/dvv-licences/licenses/b.txt" "^text of licenses/b\\.txt\n$")
file(READ "${sibling}/dvv-inputs.sha256" marker)
if(NOT marker STREQUAL hash_zero)
    message(FATAL_ERROR "FAIL: the marker holds '${marker}', not the hash without a newline")
endif()
# A missing licence file fails before the marker is written.
file(REMOVE "${sibling}/dvv-inputs.sha256")
run_script(1 "Licence file 'COPYING' not found in .*finish/source" "${finish}" ${finish_args}
           "-DLICENSE_FILES=docs/licence.txt|COPYING")
if(EXISTS "${sibling}/dvv-inputs.sha256")
    message(FATAL_ERROR "FAIL: the finish script wrote the marker after a failure")
endif()
run_script(1 "pass a 64-digit lower-case hex -DHASH" "${finish}" "-DSOURCE_DIR=${source}"
           "-DSIBLING=${sibling}" -DHASH=abc "-DLICENSE_FILES=docs/licence.txt")

message(STATUS "superbuild script tests passed")
