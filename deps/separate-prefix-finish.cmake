# Last install command of an entry with SEPARATE_PREFIX (deps/CMakeLists.txt): copies the entry's
# licence files into <sibling>/dvv-licences (globs expanded, relative paths kept), where the
# notices read them while the entry is skipped, and then writes the marker
# <sibling>/dvv-inputs.sha256 (the hash, no newline). The marker comes last, so a sibling prefix
# with a marker is complete.
#   cmake -DSOURCE_DIR=<entry source> -DSIBLING=<separate prefix> -DHASH=<64 hex>
#         -DLICENSE_FILES=<path or glob>|<path or glob>... -P separate-prefix-finish.cmake
cmake_minimum_required(VERSION 4.2)
foreach(required IN ITEMS SOURCE_DIR SIBLING LICENSE_FILES)
    if(NOT ${required})
        message(FATAL_ERROR "separate-prefix-finish: pass -D${required}")
    endif()
endforeach()
string(LENGTH "${HASH}" length)
if(NOT HASH MATCHES "^[0-9a-f]+$" OR NOT length EQUAL 64)
    message(FATAL_ERROR "separate-prefix-finish: pass a 64-digit lower-case hex -DHASH")
endif()

set(licences "${SIBLING}/dvv-licences")
file(REMOVE "${SIBLING}/dvv-inputs.sha256")
file(REMOVE_RECURSE "${licences}")
string(REPLACE "|" ";" patterns "${LICENSE_FILES}")
foreach(pattern IN LISTS patterns)
    file(GLOB files LIST_DIRECTORIES false RELATIVE "${SOURCE_DIR}" "${SOURCE_DIR}/${pattern}")
    if(NOT files)
        message(FATAL_ERROR "separate-prefix-finish: Licence file '${pattern}' not found in "
                            "${SOURCE_DIR}")
    endif()
    foreach(file IN LISTS files)
        configure_file("${SOURCE_DIR}/${file}" "${licences}/${file}" COPYONLY)
    endforeach()
endforeach()
file(WRITE "${SIBLING}/dvv-inputs.sha256" "${HASH}")
