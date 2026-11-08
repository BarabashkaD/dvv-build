# Post-install step of Vulkan-ValidationLayers on Linux and Windows (deps/versions.cmake), called
# with -DSOURCE_DIR=<extracted archive> -DPREFIX=<install prefix> [-DSTRIP=<strip program, empty
# for none>] [-DPLATFORM=Windows|Linux] (default: the host's; the tests pass the other one).
# The archive is LunarG's Vulkan SDK, extracted without its top folder:
#   Windows  SOURCE_DIR/VkLayer_khronos_validation.dll and .json (the installer's Bin/ folder):
#            both into <prefix>/bin, where the manifest's .\<dll> finds the DLL.
#   Linux    SOURCE_DIR/x86_64/lib/libVkLayer_khronos_validation.so into <prefix>/lib, without its
#            debug sections when a strip program is found (strip --strip-debug), and the manifest
#            into <prefix>/share/vulkan/explicit_layer.d, library_path ../../../lib/<layer>.
# Then SOURCE_DIR keeps only the licence file the notices read: LunarG's LICENSE.txt on Linux, the
# layer's LICENSE.txt licence supplement on Windows (the installer payload has none). The rest of
# the SDK (about 2 GB on Linux) is removed. When the SDK is gone, the extract step has not run
# again, so the files installed from it are current; SOURCE_DIR then holds the licence file only,
# and anything else there is an SDK layout this script does not know.
cmake_minimum_required(VERSION 4.2)
foreach(required IN ITEMS SOURCE_DIR PREFIX)
    if(NOT ${required})
        message(FATAL_ERROR "Vulkan-ValidationLayers post-install: pass -D${required}=<directory>")
    endif()
endforeach()
if(NOT DEFINED PLATFORM)
    if(CMAKE_HOST_WIN32)
        set(PLATFORM Windows)
    else()
        set(PLATFORM Linux)
    endif()
endif()
if(NOT PLATFORM MATCHES "^(Windows|Linux)$")
    message(FATAL_ERROR "Vulkan-ValidationLayers post-install: PLATFORM must be Windows or Linux")
endif()

set(layer VkLayer_khronos_validation)
set(supplement vulkan-validationlayers/LICENSE.txt)
if(PLATFORM STREQUAL "Windows")
    set(sdk_file "${SOURCE_DIR}/${layer}.dll")
    set(keep vulkan-validationlayers)
    set(outputs "${PREFIX}/bin/${layer}.dll" "${PREFIX}/bin/${layer}.json"
                "${SOURCE_DIR}/${supplement}")
else()
    set(sdk_file "${SOURCE_DIR}/x86_64/lib/lib${layer}.so")
    set(keep LICENSE.txt)
    set(outputs "${PREFIX}/lib/lib${layer}.so"
                "${PREFIX}/share/vulkan/explicit_layer.d/${layer}.json"
                "${SOURCE_DIR}/LICENSE.txt")
endif()

if(NOT EXISTS "${sdk_file}")
    # Either the SDK was installed and removed (SOURCE_DIR holds the kept licence file only) or the
    # archive has a layout this script does not know: --force would extract it the same way again.
    file(GLOB entries LIST_DIRECTORIES true RELATIVE "${SOURCE_DIR}" "${SOURCE_DIR}/*")
    list(REMOVE_ITEM entries "${keep}")
    if(entries)
        list(JOIN entries ", " shown)
        message(FATAL_ERROR "Vulkan-ValidationLayers post-install: unexpected LunarG SDK layout in "
                            "${SOURCE_DIR} (no ${sdk_file}; found ${shown})")
    endif()
    set(missing "")
    foreach(output IN LISTS outputs)
        if(NOT EXISTS "${output}")
            list(APPEND missing "${output}")
        endif()
    endforeach()
    if(missing)
        message(FATAL_ERROR "Vulkan-ValidationLayers post-install: the LunarG SDK is not in "
                            "${SOURCE_DIR} and ${missing} is missing; run bootstrap with --force")
    endif()
    message(STATUS "Vulkan-ValidationLayers post-install: the validation layer is already "
                   "installed")
    return()
endif()

if(PLATFORM STREQUAL "Windows")
    if(NOT EXISTS "${SOURCE_DIR}/${layer}.json")
        message(FATAL_ERROR "Vulkan-ValidationLayers post-install: the SDK has no ${layer}.json")
    endif()
    file(COPY "${SOURCE_DIR}/${layer}.dll" "${SOURCE_DIR}/${layer}.json"
         DESTINATION "${PREFIX}/bin")
else()
    set(sdk "${SOURCE_DIR}/x86_64")
    set(manifest "${sdk}/share/vulkan/explicit_layer.d/${layer}.json")
    if(NOT EXISTS "${manifest}" OR NOT EXISTS "${SOURCE_DIR}/LICENSE.txt")
        message(FATAL_ERROR "Vulkan-ValidationLayers post-install: the SDK has no ${manifest} or "
                            "no LICENSE.txt")
    endif()
    file(COPY "${sdk}/lib/lib${layer}.so" DESTINATION "${PREFIX}/lib")
    # The SDK's layer carries its debug information (about 400 MB).
    if(NOT DEFINED STRIP)
        find_program(STRIP strip)
    endif()
    if(STRIP)
        execute_process(COMMAND "${STRIP}" --strip-debug "${PREFIX}/lib/lib${layer}.so"
                        RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
        if(NOT status EQUAL 0)
            message(FATAL_ERROR "Vulkan-ValidationLayers post-install: ${STRIP} --strip-debug "
                                "failed (${status}):\n${out}${err}")
        endif()
    else()
        message(STATUS "Vulkan-ValidationLayers post-install: no strip program: lib${layer}.so "
                       "keeps its debug sections")
    endif()
    # The manifest is <prefix>/share/vulkan/explicit_layer.d/<layer>.json.
    file(READ "${manifest}" text)
    if(NOT text MATCHES "\"library_path\"[ \t]*:[ \t]*\"[^\"]*\"")
        message(FATAL_ERROR "Vulkan-ValidationLayers post-install: no library_path in "
                            "${layer}.json")
    endif()
    string(REPLACE "${CMAKE_MATCH_0}" "\"library_path\": \"../../../lib/lib${layer}.so\""
           text "${text}")
    file(WRITE "${PREFIX}/share/vulkan/explicit_layer.d/${layer}.json" "${text}")
endif()

# SOURCE_DIR keeps only the licence file.
file(GLOB entries LIST_DIRECTORIES true "${SOURCE_DIR}/*")
foreach(entry IN LISTS entries)
    cmake_path(GET entry FILENAME name)
    if(NOT name STREQUAL keep)
        file(REMOVE_RECURSE "${entry}")
    endif()
endforeach()
if(PLATFORM STREQUAL "Windows")
    set(licences "${CMAKE_CURRENT_LIST_DIR}/../licenses/Vulkan-ValidationLayers-supplement")
    file(COPY "${licences}/${supplement}" DESTINATION "${SOURCE_DIR}/vulkan-validationlayers")
endif()
