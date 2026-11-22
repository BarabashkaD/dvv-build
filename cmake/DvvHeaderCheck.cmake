# The header check: every public header of a library compiles on its own, with the library's
# compiler options. Each header gets a generated unit that holds one line, #include "<header>".
# The include uses quotes, not angle brackets: dvv_set_compiler_options gives MSVC
# /external:anglebrackets /external:W0, which would make the header under test external and hide its
# warnings. The unit's folder holds no header, so the quoted include finds the same file.
include_guard(GLOBAL)
include("${CMAKE_CURRENT_LIST_DIR}/DvvOsSources.cmake")

# dvv_add_header_check(<target> <include-root>): adds the OBJECT library <real target>_header_check
# (an ALIAS is resolved to its real target for the name), with one unit per header under the
# absolute <include-root> that dvv_os_headers keeps. It links <target> PRIVATE for its usage
# requirements and gets dvv_set_compiler_options, with no unity build. Every file under the root
# must be a .h file; the glob uses CONFIGURE_DEPENDS, so an added or deleted header joins or leaves
# the check at the next build.
function(dvv_add_header_check)
    if(NOT ARGC EQUAL 2)
        message(FATAL_ERROR "dvv_add_header_check: dvv_add_header_check(<target> <include-root>) "
                            "takes two arguments")
    endif()
    set(target "${ARGV0}")
    set(root "${ARGV1}")
    if(NOT COMMAND dvv_set_compiler_options)
        message(FATAL_ERROR "dvv_add_header_check: dvv_set_compiler_options is not defined; include "
                            "DvvCompilerOptions.cmake first")
    endif()
    if(NOT TARGET "${target}")
        message(FATAL_ERROR "dvv_add_header_check: '${target}' is not a target")
    endif()
    if(NOT IS_ABSOLUTE "${root}")
        message(FATAL_ERROR "dvv_add_header_check: ${root} is not an absolute path")
    endif()
    if(NOT IS_DIRECTORY "${root}")
        message(FATAL_ERROR "dvv_add_header_check: ${root} does not exist or is not a folder")
    endif()

    file(GLOB_RECURSE files CONFIGURE_DEPENDS LIST_DIRECTORIES false RELATIVE "${root}" "${root}/*")
    foreach(file IN LISTS files)
        if(NOT file MATCHES "\\.h$")
            message(FATAL_ERROR "dvv_add_header_check: ${file} under ${root} is not a .h file; delete "
                                "or rename it")
        endif()
    endforeach()
    if(NOT files)
        message(FATAL_ERROR "dvv_add_header_check: ${root} holds no .h file")
    endif()
    # Visual Studio checks the glob only inside the build (ZERO_CHECK), after MSBuild has loaded the
    # old project files, so an added or deleted header would join or leave the check one build late.
    # Adding a file to a folder, or deleting or renaming one, changes the folder's write time.
    # cmake --build checks these folders before it starts MSBuild and re-generates first.
    if(CMAKE_GENERATOR MATCHES "^Visual Studio")
        file(GLOB_RECURSE entries LIST_DIRECTORIES true "${root}/*")
        set(folders "${root}")
        foreach(entry IN LISTS entries)
            if(IS_DIRECTORY "${entry}")
                list(APPEND folders "${entry}")
            endif()
        endforeach()
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${folders})
    endif()

    get_target_property(real "${target}" ALIASED_TARGET)
    if(NOT real)
        set(real "${target}")
    endif()
    set(check "${real}_header_check")
    dvv_os_headers(headers ${files})
    if(NOT headers)
        message(FATAL_ERROR "dvv_add_header_check: ${root} (target ${target}) holds no .h file for "
                            "this platform")
    endif()
    set(units "")
    foreach(header IN LISTS headers)
        set(unit "${CMAKE_CURRENT_BINARY_DIR}/${check}/${header}.cpp")
        file(CONFIGURE OUTPUT "${unit}" CONTENT "#include \"@header@\"\n" @ONLY)
        list(APPEND units "${unit}")
    endforeach()
    add_library(${check} OBJECT ${units})
    target_link_libraries(${check} PRIVATE ${target})
    dvv_set_compiler_options(${check})
    set_target_properties(${check} PROPERTIES UNITY_BUILD OFF)
endfunction()
