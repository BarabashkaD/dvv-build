# The per-OS file rule: per-OS code lives in <stem>_<suffix>.{cpp,mm,h}. The suffix names the OS,
# the window system or the toolkit backend. A platform may build several suffixes ("layered" files).
# The header queries dvv_os_headers and dvv_os_headers_for pick a platform's headers from a list.
# Including this file defines variables and functions only (no target command), so a project and
# `cmake -P` can both include it.
set(DVV_OS_SUFFIXES_WIN32 win32 msw)
set(DVV_OS_SUFFIXES_APPLE posix macos metal cocoa)
set(DVV_OS_SUFFIXES_OTHER posix linux xlib gtk)
set(DVV_OS_SUFFIX_FALLBACK stub)

# dvv_os_all_suffixes(<out-var>): the union of the three lists plus the fallback, de-duplicated.
function(dvv_os_all_suffixes out)
    set(all ${DVV_OS_SUFFIXES_WIN32} ${DVV_OS_SUFFIXES_APPLE} ${DVV_OS_SUFFIXES_OTHER}
            ${DVV_OS_SUFFIX_FALLBACK})
    list(REMOVE_DUPLICATES all)
    set(${out} "${all}" PARENT_SCOPE)
endfunction()

# dvv_os_suffixes_for(<WIN32|APPLE|OTHER> <out-var>): one platform's list.
function(dvv_os_suffixes_for platform out)
    if(NOT platform MATCHES "^(WIN32|APPLE|OTHER)$")
        message(FATAL_ERROR "dvv_os_suffixes_for: unknown platform '${platform}' (WIN32, APPLE or OTHER)")
    endif()
    set(${out} "${DVV_OS_SUFFIXES_${platform}}" PARENT_SCOPE)
endfunction()

# _dvv_os_platform(<out-var>): this build's platform (WIN32, APPLE or OTHER), from CMAKE_SYSTEM_NAME
# (never the host system). Private to this module.
function(_dvv_os_platform out)
    if(NOT DEFINED CMAKE_SYSTEM_NAME)
        message(FATAL_ERROR "dvv_os_suffixes needs a project (CMAKE_SYSTEM_NAME is not set)")
    endif()
    if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
        set(${out} WIN32 PARENT_SCOPE)
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
        set(${out} APPLE PARENT_SCOPE)
    else()
        set(${out} OTHER PARENT_SCOPE)
    endif()
endfunction()

# dvv_os_suffixes(<out-var>): this build's list, from CMAKE_SYSTEM_NAME (never the host system).
function(dvv_os_suffixes out)
    _dvv_os_platform(platform)
    dvv_os_suffixes_for(${platform} list)
    set(${out} "${list}" PARENT_SCOPE)
endfunction()

# dvv_os_headers_for(<WIN32|APPLE|OTHER> <out-var> <header>...): the given headers this platform uses,
# in the given order. A header's stem is its path without ".h" and without a trailing _<suffix> (a
# suffix of dvv_os_all_suffixes), so metal.h and posix_clock.h have no suffix. Kept: a header with no
# suffix, a <stem>_<suffix>.h of the platform, and a <stem>_stub.h when the list holds no
# <stem>_<suffix>.h of the platform. Any other per-OS header is dropped. No file-system access.
# The suffix match is case-sensitive.
function(dvv_os_headers_for platform out)
    dvv_os_suffixes_for(${platform} suffixes)
    dvv_os_all_suffixes(all_suffixes)
    set(headers ${ARGN})
    set(kept "")
    foreach(header IN LISTS headers)
        if(NOT header MATCHES "^(.+)\\.h$")
            message(FATAL_ERROR "dvv_os_headers_for: '${header}' is not a .h file")
        endif()
        set(path "${CMAKE_MATCH_1}")
        set(stem "${path}")
        set(suffix "")
        foreach(candidate IN LISTS all_suffixes)
            if(path MATCHES "^(.+)_${candidate}$")
                set(stem "${CMAKE_MATCH_1}")
                set(suffix "${candidate}")
            endif()
        endforeach()
        if(suffix STREQUAL "" OR suffix IN_LIST suffixes)
            list(APPEND kept "${header}")
        elseif(suffix STREQUAL DVV_OS_SUFFIX_FALLBACK)
            set(layered FALSE)
            foreach(own IN LISTS suffixes)
                if("${stem}_${own}.h" IN_LIST headers)
                    set(layered TRUE)
                endif()
            endforeach()
            if(NOT layered)
                list(APPEND kept "${header}")
            endif()
        endif()
    endforeach()
    set(${out} "${kept}" PARENT_SCOPE)
endfunction()

# dvv_os_headers(<out-var> <header>...): dvv_os_headers_for this build's platform.
function(dvv_os_headers out)
    _dvv_os_platform(platform)
    dvv_os_headers_for(${platform} list ${ARGN})
    set(${out} "${list}" PARENT_SCOPE)
endfunction()

# dvv_os_sources(<target> [OPTIONAL] <stem>...): adds each stem's per-OS files to <target> as PRIVATE
# sources. A stem is a path without extension, relative to CMAKE_CURRENT_SOURCE_DIR; a call without a
# stem is an error. Per stem:
#   1. every existing <stem>_<suffix>.cpp and .mm for this build's suffixes, in list order (a suffix
#      with both a .cpp and a .mm is an error);
#   2. if any exist, all of them are added ("layered" files);
#   3. else <stem>_stub.cpp, if it exists;
#   4. else an error, or nothing with OPTIONAL;
#   5. in every case an error if no file exists for any suffix of any platform (a misspelt stem).
# Each .mm gets -fobjc-arc. Per-OS headers are not added.
function(dvv_os_sources target)
    cmake_parse_arguments(PARSE_ARGV 1 ARG "OPTIONAL" "" "")
    if(NOT ARG_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "dvv_os_sources: no stem given (dvv_os_sources(<target> [OPTIONAL] <stem>...))")
    endif()
    _dvv_os_platform(platform)
    dvv_os_suffixes(suffixes)
    dvv_os_all_suffixes(all_suffixes)

    foreach(stem IN LISTS ARG_UNPARSED_ARGUMENTS)
        set(base "${CMAKE_CURRENT_SOURCE_DIR}/${stem}")
        set(found "")
        foreach(suffix IN LISTS suffixes)
            set(cpp "${base}_${suffix}.cpp")
            set(mm "${base}_${suffix}.mm")
            if(EXISTS "${cpp}" AND EXISTS "${mm}")
                message(FATAL_ERROR "${stem}_${suffix}: both .cpp and .mm")
            endif()
            foreach(file IN ITEMS "${cpp}" "${mm}")
                if(EXISTS "${file}")
                    list(APPEND found "${file}")
                endif()
            endforeach()
        endforeach()
        if(NOT found AND EXISTS "${base}_${DVV_OS_SUFFIX_FALLBACK}.cpp")
            set(found "${base}_${DVV_OS_SUFFIX_FALLBACK}.cpp")
        endif()

        if(NOT found AND NOT ARG_OPTIONAL)
            message(FATAL_ERROR "${stem}: no file for ${platform} and no ${stem}_${DVV_OS_SUFFIX_FALLBACK}.cpp")
        endif()

        set(anywhere FALSE)
        foreach(suffix IN LISTS all_suffixes)
            if(EXISTS "${base}_${suffix}.cpp" OR EXISTS "${base}_${suffix}.mm")
                set(anywhere TRUE)
            endif()
        endforeach()
        if(NOT anywhere)
            message(FATAL_ERROR "${stem}: matches no per-OS file on any platform")
        endif()

        if(found)
            target_sources(${target} PRIVATE ${found})
            foreach(file IN LISTS found)
                if(file MATCHES "\\.mm$")
                    if(NOT CMAKE_OBJCXX_COMPILER_LOADED)
                        cmake_path(GET file FILENAME name)
                        message(FATAL_ERROR "${name}: enable OBJCXX before dvv_os_sources")
                    endif()
                    set_property(SOURCE "${file}" TARGET_DIRECTORY ${target}
                                 APPEND PROPERTY COMPILE_OPTIONS -fobjc-arc)
                endif()
            endforeach()
        endif()
    endforeach()
endfunction()
