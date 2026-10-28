# Post-install step of Vulkan-ValidationLayers (deps/versions.cmake), called with
# -DSOURCE_DIR=<extracted archive> -DPREFIX=<install prefix>.
# The Linux layer manifest names the library without a directory, so the loader would also need
# LD_LIBRARY_PATH. This rewrites library_path relative to the manifest, so that
# VK_ADD_LAYER_PATH=<prefix>/share/vulkan/explicit_layer.d alone finds the layer. The Windows
# manifest lies next to the DLL in <prefix>/bin and works as installed.
cmake_minimum_required(VERSION 4.2)
if(NOT PREFIX)
    message(FATAL_ERROR "Vulkan-ValidationLayers post-install: pass -DPREFIX=<directory>")
endif()
set(layer VkLayer_khronos_validation)
if(EXISTS "${PREFIX}/bin/${layer}.json")
    return()
endif()
set(manifest "${PREFIX}/share/vulkan/explicit_layer.d/${layer}.json")
if(NOT EXISTS "${manifest}")
    message(FATAL_ERROR "Vulkan-ValidationLayers post-install: no ${layer}.json in the prefix")
endif()
file(READ "${manifest}" text)
if(NOT text MATCHES "\"library_path\"[ \t]*:[ \t]*\"([^\"]*)\"")
    message(FATAL_ERROR "Vulkan-ValidationLayers post-install: no library_path in ${layer}.json")
endif()
set(entry "${CMAKE_MATCH_0}")
cmake_path(GET CMAKE_MATCH_1 FILENAME library)
if(NOT EXISTS "${PREFIX}/lib/${library}")
    message(FATAL_ERROR "Vulkan-ValidationLayers post-install: ${library} is not in <prefix>/lib")
endif()
# The manifest is <prefix>/share/vulkan/explicit_layer.d/<layer>.json.
string(REPLACE "${entry}" "\"library_path\": \"../../../lib/${library}\"" text "${text}")
file(WRITE "${manifest}" "${text}")
