# Writes a notices file. Called by deps/CMakeLists.txt with
#   -DOUTPUT=<file> -DENTRIES=<name|version|spdx|url|source dir|licence file|...;...>
#   [-DHEADER=<first line>] [-DMSVC_RUNTIME=ON]
#   [-DSUPPLEMENTS=<name|file|sha256|shown path|component|version|url;...>]
# A licence file is a path or a glob relative to the source directory; a glob must match.
# SUPPLEMENTS are the licence texts an entry's archive lacks (dvv_licence_supplement); each one is
# copied, with a heading naming its origin, after the licence files of the entry <name>, and its
# SHA256 is checked again here.
# MSVC_RUNTIME appends the paragraph for the Visual C++ runtime DLLs that the Windows package carries
# next to the executables (M4 design D17, D19).
cmake_minimum_required(VERSION 4.2)
if(NOT DEFINED HEADER)
    set(HEADER "Third-party software used by rawreel and the dvv libraries")
endif()
set(text "${HEADER}\n")
foreach(entry IN LISTS ENTRIES)
    string(REPLACE "|" ";" fields "${entry}")
    list(POP_FRONT fields name version spdx url source_dir)
    if(NOT fields)
        message(FATAL_ERROR "No licence file given for ${name}")
    endif()
    string(APPEND text "\n==============================================================\n"
                       "${name} ${version}\nLicence: ${spdx}\nSource: ${url}\n")
    foreach(pattern IN LISTS fields)
        if(pattern MATCHES "[*?[]")
            file(GLOB licence_files LIST_DIRECTORIES false "${source_dir}/${pattern}")
            list(SORT licence_files)
        elseif(EXISTS "${source_dir}/${pattern}" AND NOT IS_DIRECTORY "${source_dir}/${pattern}")
            set(licence_files "${source_dir}/${pattern}")
        else()
            set(licence_files "")
        endif()
        if(NOT licence_files)
            message(FATAL_ERROR "Licence file '${pattern}' of ${name} not found")
        endif()
        foreach(licence_file IN LISTS licence_files)
            file(RELATIVE_PATH shown "${source_dir}" "${licence_file}")
            file(READ "${licence_file}" licence)
            string(REGEX REPLACE "[ \t\r\n]+$" "" licence "${licence}")
            string(APPEND text "\n--- ${shown} ---\n\n${licence}\n")
        endforeach()
    endforeach()
    foreach(supplement IN LISTS SUPPLEMENTS)
        string(REPLACE "|" ";" parts "${supplement}")
        list(POP_FRONT parts owner file sha256 shown component component_version url)
        if(NOT owner STREQUAL name)
            continue()
        endif()
        if(NOT EXISTS "${file}" OR IS_DIRECTORY "${file}")
            message(FATAL_ERROR "Licence supplement '${shown}' of ${name} not found")
        endif()
        file(SHA256 "${file}" actual)
        if(NOT actual STREQUAL sha256)
            message(FATAL_ERROR "Licence supplement '${shown}' of ${name} does not match its "
                                "SHA256 pin")
        endif()
        file(READ "${file}" licence)
        string(REGEX REPLACE "[ \t\r\n]+$" "" licence "${licence}")
        string(APPEND text "\n--- ${shown} (supplement: not in the ${name} ${version} archive)"
                           " ---\nFrom ${component} ${component_version}: ${url}\n\n${licence}\n")
    endforeach()
endforeach()
if(MSVC_RUNTIME)
    string(APPEND text "\n==============================================================\n"
                       "Microsoft Visual C++ runtime\n"
                       "Files: vcruntime140.dll, vcruntime140_1.dll, msvcp140.dll and the other "
                       "Visual C++ runtime DLLs next to the executables\n"
                       "Licence: Microsoft Software License Terms for Microsoft Visual Studio "
                       "(Distributable Code)\n"
                       "Source: https://visualstudio.microsoft.com/license-terms/\n")
endif()
file(WRITE "${OUTPUT}" "${text}")
