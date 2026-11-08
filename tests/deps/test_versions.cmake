# Every declaration in deps/versions.cmake passes the licence gate and the declaration checks, and
# the set built on each platform is listed, with the shipped entries for DVV_BUNDLE_FFMPEG ON and
# OFF. Run: cmake -P tests/deps/test_versions.cmake
cmake_minimum_required(VERSION 4.2)
include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/DvvThirdParty.cmake")

if(DEFINED PLATFORM)
    set(CMAKE_SYSTEM_NAME "${PLATFORM}")
    set(DVV_BUNDLE_FFMPEG "${BUNDLE}")
    include("${CMAKE_CURRENT_LIST_DIR}/../../deps/versions.cmake")
    get_property(names GLOBAL PROPERTY DVV_THIRD_PARTY_NAMES)
    set(unique_names ${names})
    list(REMOVE_DUPLICATES unique_names)
    list(LENGTH names count)
    list(LENGTH unique_names unique_count)
    if(NOT count EQUAL unique_count)
        message(FATAL_ERROR "a name is declared twice for ${PLATFORM}: ${names}")
    endif()
    # Every entry built here is pinned: a version, an https URL and a SHA256 of 64 hex digits.
    foreach(name IN LISTS names)
        foreach(key IN ITEMS VERSION URL SHA256)
            get_property(${key} GLOBAL PROPERTY "DVV_THIRD_PARTY_${name}_${key}")
        endforeach()
        if(VERSION STREQUAL "" OR NOT URL MATCHES "^https://[^ ]+$" OR
           NOT SHA256 MATCHES "^[0-9a-f]+$")
            message(FATAL_ERROR "${name} for ${PLATFORM} is not pinned: version '${VERSION}', "
                                "URL '${URL}', SHA256 '${SHA256}'")
        endif()
        string(LENGTH "${SHA256}" hash_length)
        if(NOT hash_length EQUAL 64)
            message(FATAL_ERROR "${name} for ${PLATFORM}: SHA256 '${SHA256}' is not 64 digits")
        endif()
    endforeach()
    # macOS (spec U-MAC2, U-MAC10): the loader is built from source, KosmicKrisp, vulkaninfo and the
    # validation layer come from the LunarG SDK.
    if(PLATFORM STREQUAL "Darwin")
        set(expected_names nlohmann_json doctest Vulkan-Headers VulkanMemoryAllocator vk-bootstrap
                           slang Vulkan-Loader kosmickrisp vulkaninfo Vulkan-ValidationLayers
                           wxWidgets custom_ffmpeg)
        if(NOT names STREQUAL expected_names)
            message(FATAL_ERROR "names for Darwin: '${names}', expected '${expected_names}'")
        endif()
        foreach(entry IN ITEMS "slang|PREBUILT|TRUE" "kosmickrisp|PREBUILT|TRUE"
                               "vulkaninfo|PREBUILT|TRUE" "Vulkan-Loader|PREBUILT|FALSE"
                               "wxWidgets|CONFIGS|Release")
            string(REPLACE "|" ";" entry "${entry}")
            list(GET entry 0 name)
            list(GET entry 1 key)
            list(GET entry 2 expected)
            get_property(value GLOBAL PROPERTY "DVV_THIRD_PARTY_${name}_${key}")
            if(NOT "${value}" STREQUAL "${expected}")
                message(FATAL_ERROR "${name} ${key} for Darwin: '${value}', expected '${expected}'")
            endif()
        endforeach()
        get_property(url GLOBAL PROPERTY DVV_THIRD_PARTY_slang_URL)
        if(NOT url MATCHES "/slang-2026\\.20-macos-aarch64\\.tar\\.gz$")
            message(FATAL_ERROR "slang for Darwin: ${url}")
        endif()
        get_property(args GLOBAL PROPERTY DVV_THIRD_PARTY_wxWidgets_CMAKE_ARGS)
        foreach(arg IN ITEMS -DwxBUILD_TOOLKIT=osx_cocoa -DwxBUILD_SHARED=OFF -DwxUSE_ZLIB=builtin
                             -DwxUSE_LIBPNG=builtin)
            if(NOT arg IN_LIST args)
                message(FATAL_ERROR "wxWidgets for Darwin lacks ${arg}: ${args}")
            endif()
        endforeach()
        if(args MATCHES "MSVC|STATIC_RUNTIME")
            message(FATAL_ERROR "wxWidgets for Darwin has an MSVC-only option: ${args}")
        endif()
        # The loader searches the system's /etc, never the build machine's prefix.
        get_property(args GLOBAL PROPERTY DVV_THIRD_PARTY_Vulkan-Loader_CMAKE_ARGS)
        if(NOT "-DSYSCONFDIR=/etc" IN_LIST args)
            message(FATAL_ERROR "Vulkan-Loader for Darwin lacks -DSYSCONFDIR=/etc: ${args}")
        endif()
        foreach(name IN ITEMS kosmickrisp vulkaninfo)
            get_property(${name}_url GLOBAL PROPERTY "DVV_THIRD_PARTY_${name}_URL")
            get_property(${name}_sha256 GLOBAL PROPERTY "DVV_THIRD_PARTY_${name}_SHA256")
        endforeach()
        if(NOT kosmickrisp_url STREQUAL vulkaninfo_url OR
           NOT kosmickrisp_sha256 STREQUAL vulkaninfo_sha256)
            message(FATAL_ERROR "kosmickrisp and vulkaninfo come from different SDK archives")
        endif()
        get_property(url GLOBAL PROPERTY DVV_THIRD_PARTY_custom_ffmpeg_URL)
        get_property(version GLOBAL PROPERTY DVV_THIRD_PARTY_custom_ffmpeg_VERSION)
        if(NOT version STREQUAL "1.0.1" OR
           NOT url MATCHES "/v1\\.0\\.1/custom_ffmpeg-1\\.0\\.1-macos-arm64-shared-lgpl\\.tar\\.xz$")
            message(FATAL_ERROR "custom_ffmpeg for Darwin: ${version} ${url}")
        endif()
        # The SDK carries no licence text of KosmicKrisp (Mesa) or vulkaninfo (Vulkan-Tools). MIT
        # needs the copyright notices too: KosmicKrisp's are collected from the Mesa sources.
        foreach(entry IN ITEMS "kosmickrisp|mesa/licenses/MIT,mesa/COPYRIGHTS.txt"
                               "vulkaninfo|vulkan-tools/LICENSE.txt")
            string(REPLACE "|" ";" entry "${entry}")
            list(GET entry 0 name)
            list(GET entry 1 expected)
            string(REPLACE "," ";" expected "${expected}")
            get_property(supplements GLOBAL PROPERTY "DVV_THIRD_PARTY_${name}_SUPPLEMENTS")
            set(supplied "")
            foreach(supplement IN LISTS supplements)
                string(REPLACE "|" ";" parts "${supplement}")
                list(GET parts 2 shown)
                list(APPEND supplied "${shown}")
            endforeach()
            if(NOT supplied STREQUAL expected)
                message(FATAL_ERROR "${name} licence supplements: '${supplied}', expected "
                                    "'${expected}'")
            endif()
        endforeach()
        # KosmicKrisp's expression lists everything compiled into the driver: Mesa (MIT), Berkeley
        # SoftFloat, xxHash, the X11-style clause of util/hash_table.c and set.c, and BLAKE3.
        get_property(spdx GLOBAL PROPERTY DVV_THIRD_PARTY_kosmickrisp_SPDX)
        set(expected_spdx "MIT AND BSD-3-Clause AND BSD-2-Clause AND X11 AND \
(CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception)")
        if(NOT spdx STREQUAL expected_spdx)
            message(FATAL_ERROR "kosmickrisp SPDX: '${spdx}', expected '${expected_spdx}'")
        endif()
        # The collected notices name the driver's own holders, the shared Mesa code's and the
        # non-MIT parts compiled into the driver, with their licence texts.
        get_property(supplements GLOBAL PROPERTY DVV_THIRD_PARTY_kosmickrisp_SUPPLEMENTS)
        list(GET supplements 1 supplement)
        string(REPLACE "|" ";" parts "${supplement}")
        list(GET parts 0 file)
        file(READ "${file}" text)
        foreach(expected IN ITEMS "\nCopyright 2025 LunarG, Inc\\.\n" "\nCopyright 2025 Google LLC\n"
                                  "\nCopyright © 2015 Intel Corporation\n"
                                  "\nCopyright 2008 VMware, Inc\\.\n"
                                  "The Regents of the\n \\* University of California"
                                  "Copyright \\(C\\) 2012-2023 Yann Collet"
                                  "BSD 2-Clause License" "BLAKE3" "not be used in advertising")
            if(NOT text MATCHES "${expected}")
                message(FATAL_ERROR "mesa/COPYRIGHTS.txt lacks '${expected}'")
            endif()
        endforeach()
    endif()
    # The validation layer is LunarG's prebuilt from the SDK 1.4.363.1 on every platform (U-CI1); on
    # macOS it shares kosmickrisp's archive, whose post-install step installs it. Its licence texts
    # are supplements: the SDK archives carry only LunarG's statement (Linux, macOS) or nothing
    # (Windows, where the post-install step keeps the layer's LICENSE.txt). Only the Windows build
    # embeds mimalloc. The source build's own dependencies are gone.
    foreach(platform IN LISTS DVV_THIRD_PARTY_PLATFORMS)
        get_property(declared GLOBAL PROPERTY "DVV_THIRD_PARTY_DECLARED_${platform}")
        foreach(name IN ITEMS SPIRV-Tools SPIRV-Headers Vulkan-Utility-Libraries)
            if(name IN_LIST declared)
                message(FATAL_ERROR "${name} is declared for ${platform}")
            endif()
        endforeach()
    endforeach()
    set(layer_supplements vulkan-validationlayers/LICENSE.txt
        vulkan-validationlayers/LICENSES/Apache-2.0.txt
        vulkan-validationlayers/LICENSES/BSD-2-Clause.txt
        vulkan-validationlayers/LICENSES/BSL-1.0.txt
        vulkan-validationlayers/LICENSES/LLVM-exception.txt
        vulkan-validationlayers/LICENSES/MIT.txt spirv-tools/LICENSE spirv-headers/LICENSE)
    set(layer_post_install "/deps/post-install/Vulkan-ValidationLayers\\.cmake$")
    set(layer_shared "")
    set(layer_depends "")
    if(PLATFORM STREQUAL "Linux")
        set(layer_url https://sdk.lunarg.com/sdk/download/1.4.363.1/linux/vulkan_sdk.tar.xz)
        set(layer_sha256 b7867d8ca658563813af666f34b93db87f1b1c7d9d69d97e924c210c7ba33eb8)
        set(layer_licence_files LICENSE.txt)
    elseif(PLATFORM STREQUAL "Windows")
        set(layer_url https://sdk.lunarg.com/sdk/download/1.4.363.1/windows/vulkan_sdk.exe)
        set(layer_sha256 c02932bd9a968b22d404536108adaacac908c081cd6b0113f5bfefc523dd0a6a)
        set(layer_licence_files vulkan-validationlayers/LICENSE.txt)
        list(REMOVE_AT layer_supplements 0)
        list(APPEND layer_supplements mimalloc/LICENSE)
    else()
        set(layer_url https://sdk.lunarg.com/sdk/download/1.4.363.1/mac/vulkan_sdk.zip)
        set(layer_sha256 a65c707cf0a32bf8c2ca6b9af1985b7af61dbadfc19b352dae51a323f3a547a6)
        set(layer_licence_files Licenses/LICENSE.txt)
        set(layer_post_install "^$")
        set(layer_shared kosmickrisp)
        set(layer_depends kosmickrisp)
    endif()
    foreach(entry IN ITEMS "PREBUILT|TRUE" "VERSION|1.4.363.1" "URL|${layer_url}"
                           "SHA256|${layer_sha256}" "LINKAGE|runtime" "SHIPPED|FALSE"
                           "SPDX|Apache-2.0 AND BSD-2-Clause AND BSL-1.0 AND MIT"
                           "LICENSE_FILES|${layer_licence_files}" "DEPENDS|${layer_depends}")
        string(FIND "${entry}" "|" bar)
        string(SUBSTRING "${entry}" 0 ${bar} key)
        math(EXPR bar "${bar} + 1")
        string(SUBSTRING "${entry}" ${bar} -1 expected)
        get_property(value GLOBAL PROPERTY "DVV_THIRD_PARTY_Vulkan-ValidationLayers_${key}")
        if(NOT "${value}" STREQUAL "${expected}")
            message(FATAL_ERROR "Vulkan-ValidationLayers ${key} for ${PLATFORM}: '${value}', "
                                "expected '${expected}'")
        endif()
    endforeach()
    get_property(value GLOBAL PROPERTY DVV_THIRD_PARTY_Vulkan-ValidationLayers_POST_INSTALL)
    if(NOT value MATCHES "${layer_post_install}")
        message(FATAL_ERROR "Vulkan-ValidationLayers POST_INSTALL for ${PLATFORM}: '${value}'")
    endif()
    dvv_third_party_shared_archive(Vulkan-ValidationLayers shared)
    if(NOT shared STREQUAL layer_shared)
        message(FATAL_ERROR "Vulkan-ValidationLayers for ${PLATFORM} shares the archive of "
                            "'${shared}', expected '${layer_shared}'")
    endif()
    get_property(supplements GLOBAL PROPERTY DVV_THIRD_PARTY_Vulkan-ValidationLayers_SUPPLEMENTS)
    set(supplied "")
    foreach(supplement IN LISTS supplements)
        string(REPLACE "|" ";" parts "${supplement}")
        list(GET parts 2 shown)
        list(APPEND supplied "${shown}")
    endforeach()
    if(NOT supplied STREQUAL layer_supplements)
        message(FATAL_ERROR "Vulkan-ValidationLayers licence supplements for ${PLATFORM}: "
                            "'${supplied}', expected '${layer_supplements}'")
    endif()
    # The entries whose code ships in a rawreel package (M4 design D19); custom_ffmpeg only when
    # bundled (user decision U4).
    set(shipped "")
    foreach(name IN LISTS names)
        get_property(is_shipped GLOBAL PROPERTY "DVV_THIRD_PARTY_${name}_SHIPPED")
        if(is_shipped)
            list(APPEND shipped "${name}")
        endif()
    endforeach()
    set(expected_shipped Vulkan-Headers VulkanMemoryAllocator nlohmann_json vk-bootstrap wxWidgets)
    if(PLATFORM STREQUAL "Darwin")
        list(APPEND expected_shipped Vulkan-Loader kosmickrisp)
    endif()
    if(BUNDLE)
        list(APPEND expected_shipped custom_ffmpeg)
    endif()
    list(SORT shipped)
    list(SORT expected_shipped)
    if(NOT shipped STREQUAL expected_shipped)
        message(FATAL_ERROR "shipped for ${PLATFORM} (DVV_BUNDLE_FFMPEG=${BUNDLE}): ${shipped}, "
                            "expected ${expected_shipped}")
    endif()
    # Source archives pinned for rawreel's third-party sources archive (M4 design D27).
    get_property(pins GLOBAL PROPERTY DVV_SOURCE_PIN_NAMES)
    if(NOT pins STREQUAL "lame")
        message(FATAL_ERROR "source pins for ${PLATFORM}: '${pins}', expected 'lame'")
    endif()
    # The licence texts custom_ffmpeg's archives lack. Including versions.cmake has already failed
    # if one of the files is missing or does not match its SHA256 pin.
    get_property(supplements GLOBAL PROPERTY DVV_THIRD_PARTY_custom_ffmpeg_SUPPLEMENTS)
    set(supplied "")
    foreach(supplement IN LISTS supplements)
        string(REPLACE "|" ";" parts "${supplement}")
        list(GET parts 2 shown)
        list(APPEND supplied "${shown}")
    endforeach()
    # libvpl is in the Windows and Linux builds only (custom_ffmpeg's LICENSES.md).
    set(expected_supplied svtav1/third_party/fastfeat/LICENSE
                          svtav1/third_party/safestringlib/LICENSE)
    if(NOT PLATFORM STREQUAL "Darwin")
        list(APPEND expected_supplied libvpl/third-party-programs.txt)
    endif()
    if(NOT supplied STREQUAL expected_supplied)
        message(FATAL_ERROR "custom_ffmpeg licence supplements for ${PLATFORM}: '${supplied}', "
                            "expected '${expected_supplied}'")
    endif()
    list(JOIN names ", " names)
    list(JOIN shipped ", " shipped)
    message(STATUS "${PLATFORM} (DVV_BUNDLE_FFMPEG=${BUNDLE}): ${names}; shipped: ${shipped}")
    return()
endif()

if(NOT DVV_THIRD_PARTY_PLATFORMS STREQUAL "Windows;Linux;Darwin")
    message(FATAL_ERROR "FAIL: DVV_THIRD_PARTY_PLATFORMS is '${DVV_THIRD_PARTY_PLATFORMS}'")
endif()
foreach(platform IN LISTS DVV_THIRD_PARTY_PLATFORMS)
    foreach(bundle IN ITEMS ON OFF)
        execute_process(COMMAND "${CMAKE_COMMAND}" "-DPLATFORM=${platform}" "-DBUNDLE=${bundle}"
                                -P "${CMAKE_CURRENT_LIST_FILE}"
                        RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
        if(NOT status EQUAL 0)
            message(FATAL_ERROR "FAIL: deps/versions.cmake for ${platform} "
                                "(DVV_BUNDLE_FFMPEG=${bundle}):\n${out}${err}")
        endif()
        string(STRIP "${out}" out)
        message("${out}")
    endforeach()
endforeach()
message(STATUS "versions tests passed")
