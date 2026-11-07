# Post-install step of kosmickrisp (deps/versions.cmake), called with -DSOURCE_DIR=<extracted
# archive> -DPREFIX=<install prefix> -DBINARY_DIR=<build directory>.
# The archive is the LunarG Vulkan SDK for macOS: a Qt installer application, extracted without its
# top folder (SOURCE_DIR/Contents/MacOS/vulkansdk-macOS-<version>). This runs it headless into
# BINARY_DIR/sdk with only the component com.lunarg.vulkan.core (never com.lunarg.vulkan.usr, which
# installs into /usr/local), then copies into the prefix only
#   lib/libvulkan_kosmickrisp.dylib                  the KosmicKrisp driver,
#   share/vulkan/icd.d/libkosmickrisp_icd.json       its manifest, library_path relative to it,
#   bin/vulkaninfo                                   the test tool (entry vulkaninfo),
# and replaces SOURCE_DIR's content with the SDK's Licenses/LICENSE.txt and VERSIONS.txt, which the
# notices of kosmickrisp and vulkaninfo read. The installer and the installed SDK (2.6 GB) are
# removed. When the installer is gone, the extract step has not run again, so the files installed
# from it are current.
cmake_minimum_required(VERSION 4.2)
foreach(required IN ITEMS SOURCE_DIR PREFIX BINARY_DIR)
    if(NOT ${required})
        message(FATAL_ERROR "kosmickrisp post-install: pass -D${required}=<directory>")
    endif()
endforeach()

set(driver libvulkan_kosmickrisp.dylib)
set(manifest libkosmickrisp_icd.json)
set(outputs "${PREFIX}/lib/${driver}" "${PREFIX}/share/vulkan/icd.d/${manifest}"
            "${PREFIX}/bin/vulkaninfo" "${SOURCE_DIR}/Licenses/LICENSE.txt"
            "${SOURCE_DIR}/VERSIONS.txt")

file(GLOB installer LIST_DIRECTORIES false "${SOURCE_DIR}/Contents/MacOS/vulkansdk-macOS-*")
list(LENGTH installer count)
if(count EQUAL 0)
    set(missing "")
    foreach(output IN LISTS outputs)
        if(NOT EXISTS "${output}")
            list(APPEND missing "${output}")
        endif()
    endforeach()
    if(missing)
        message(FATAL_ERROR "kosmickrisp post-install: the SDK installer is not in ${SOURCE_DIR} "
                            "and ${missing} is missing; run bootstrap with --force")
    endif()
    message(STATUS "kosmickrisp post-install: KosmicKrisp is already installed")
    return()
elseif(NOT count EQUAL 1)
    message(FATAL_ERROR "kosmickrisp post-install: expected one SDK installer, found ${installer}")
endif()

# The installer refuses a non-empty target folder.
set(root "${BINARY_DIR}/sdk")
file(REMOVE_RECURSE "${root}")
execute_process(COMMAND "${installer}" --root "${root}" --accept-licenses --default-answer
                        --confirm-command install com.lunarg.vulkan.core
                RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT status EQUAL 0)
    message(FATAL_ERROR "kosmickrisp post-install: the Vulkan SDK installer failed (${status}):\n"
                        "${out}${err}")
endif()

set(sdk "${root}/macOS")
foreach(file IN ITEMS "${sdk}/lib/${driver}" "${sdk}/share/vulkan/icd.d/${manifest}"
                      "${sdk}/bin/vulkaninfo" "${root}/Licenses/LICENSE.txt" "${root}/VERSIONS.txt")
    if(NOT EXISTS "${file}")
        message(FATAL_ERROR "kosmickrisp post-install: the installed SDK has no ${file}")
    endif()
endforeach()

file(COPY "${sdk}/lib/${driver}" DESTINATION "${PREFIX}/lib")
file(COPY "${sdk}/bin/vulkaninfo" DESTINATION "${PREFIX}/bin")
# The manifest is <prefix>/share/vulkan/icd.d/<manifest>, the driver <prefix>/lib/<driver>.
file(READ "${sdk}/share/vulkan/icd.d/${manifest}" text)
if(NOT text MATCHES "\"library_path\"[ \t]*:[ \t]*\"[^\"]*\"")
    message(FATAL_ERROR "kosmickrisp post-install: no library_path in ${manifest}")
endif()
string(REPLACE "${CMAKE_MATCH_0}" "\"library_path\": \"../../../lib/${driver}\"" text "${text}")
file(WRITE "${PREFIX}/share/vulkan/icd.d/${manifest}" "${text}")

file(REMOVE_RECURSE "${SOURCE_DIR}/Contents")
file(COPY "${root}/Licenses/LICENSE.txt" DESTINATION "${SOURCE_DIR}/Licenses")
file(COPY "${root}/VERSIONS.txt" DESTINATION "${SOURCE_DIR}")
file(REMOVE_RECURSE "${root}")
