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
    set(expected_supplied svtav1/third_party/fastfeat/LICENSE
                          svtav1/third_party/safestringlib/LICENSE libvpl/third-party-programs.txt)
    if(NOT supplied STREQUAL expected_supplied)
        message(FATAL_ERROR "custom_ffmpeg licence supplements for ${PLATFORM}: '${supplied}', "
                            "expected '${expected_supplied}'")
    endif()
    list(JOIN names ", " names)
    list(JOIN shipped ", " shipped)
    message(STATUS "${PLATFORM} (DVV_BUNDLE_FFMPEG=${BUNDLE}): ${names}; shipped: ${shipped}")
    return()
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
