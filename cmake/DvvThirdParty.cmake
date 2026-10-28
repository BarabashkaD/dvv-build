# Third-party dependency declarations (spec §13.2).
#
# dvv_third_party(<name> VERSION <v> URL <url> SHA256 <hash> SPDX <expression>
#                 LINKAGE static|runtime|tool LICENSE_FILES <path or glob in archive>...
#                 [ONLY_ON Windows|Linux] [DEPENDS <name>...] [CONFIGS Debug|Release...]
#                 [PREBUILT | CMAKE_ARGS <args>...] [POST_INSTALL <script>] [SHIPPED])
# Records the dependency in global properties and fails configuration when its SPDX expression is
# not allowed for its linkage. Every declaration passes the licence gate on every platform; ONLY_ON
# only decides where it is built.
#   LICENSE_FILES  copied into THIRD_PARTY_NOTICES.txt; a glob must match at least one file.
#   DEPENDS        dependencies declared earlier that must be installed first.
#   CONFIGS        configurations built and installed, in this order (default Release). Only a
#                  multi-config generator (Visual Studio) can build more than Release; not with
#                  PREBUILT.
#   PREBUILT       nothing is built: the archive's content is installed under <prefix>/<name>.
#   SHIPPED        the entry's code or files are in a rawreel package: only shipped entries go
#                  into THIRD_PARTY_NOTICES.txt (M4 design D19). Not with LINKAGE tool.
#   CMAKE_ARGS     extra configure arguments; <INSTALL_DIR> stands for the install prefix.
#   POST_INSTALL   CMake script, relative to the declaring file, run after the install as
#                  cmake -DSOURCE_DIR=<extracted archive> -DPREFIX=<install prefix> -P <script>.
include_guard(GLOBAL)
include("${CMAKE_CURRENT_LIST_DIR}/DvvSpdx.cmake")

set(DVV_THIRD_PARTY_PLATFORMS Windows Linux)

function(dvv_third_party name)
    cmake_parse_arguments(PARSE_ARGV 1 arg "PREBUILT;SHIPPED"
                          "VERSION;URL;SHA256;SPDX;LINKAGE;ONLY_ON;POST_INSTALL"
                          "LICENSE_FILES;DEPENDS;CMAKE_ARGS;CONFIGS")
    foreach(required IN ITEMS VERSION URL SHA256 SPDX LINKAGE LICENSE_FILES)
        if(NOT arg_${required})
            message(FATAL_ERROR "dvv_third_party(${name}): ${required} is required")
        endif()
    endforeach()
    if(arg_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "dvv_third_party(${name}): unexpected '${arg_UNPARSED_ARGUMENTS}'")
    endif()
    if(NOT arg_SHA256 MATCHES "^[0-9a-f]+$")
        message(FATAL_ERROR "dvv_third_party(${name}): SHA256 must be lower-case hex")
    endif()
    string(LENGTH "${arg_SHA256}" hash_length)
    if(NOT hash_length EQUAL 64)
        message(FATAL_ERROR "dvv_third_party(${name}): SHA256 must have 64 hex digits")
    endif()
    if(arg_PREBUILT AND arg_CMAKE_ARGS)
        message(FATAL_ERROR "dvv_third_party(${name}): PREBUILT takes no CMAKE_ARGS")
    endif()
    if(arg_PREBUILT AND arg_CONFIGS)
        message(FATAL_ERROR "dvv_third_party(${name}): PREBUILT takes no CONFIGS")
    endif()
    foreach(config IN LISTS arg_CONFIGS)
        if(NOT config MATCHES "^(Debug|Release)$")
            message(FATAL_ERROR "dvv_third_party(${name}): CONFIGS takes Debug and Release only, "
                                "not '${config}'")
        endif()
    endforeach()
    if(NOT arg_CONFIGS)
        set(arg_CONFIGS Release)
    endif()
    if(arg_SHIPPED AND arg_LINKAGE STREQUAL "tool")
        message(FATAL_ERROR "dvv_third_party(${name}): SHIPPED needs LINKAGE static or runtime "
                            "(a tool is never shipped)")
    endif()
    # The extract step replaces <prefix>/<name> as a whole: it must not wipe a shared folder.
    if(arg_PREBUILT AND name MATCHES "^(bin|lib|lib64|include|share|src|cmake|etc|libexec)$")
        message(FATAL_ERROR "dvv_third_party(${name}): a PREBUILT name must not be a prefix folder")
    endif()
    if(arg_ONLY_ON)
        if(NOT arg_ONLY_ON IN_LIST DVV_THIRD_PARTY_PLATFORMS)
            message(FATAL_ERROR "dvv_third_party(${name}): ONLY_ON must be one of "
                                "${DVV_THIRD_PARTY_PLATFORMS}")
        endif()
        set(platforms "${arg_ONLY_ON}")
    else()
        set(platforms ${DVV_THIRD_PARTY_PLATFORMS})
    endif()
    if(arg_POST_INSTALL)
        cmake_path(ABSOLUTE_PATH arg_POST_INSTALL BASE_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
                   NORMALIZE)
        if(NOT EXISTS "${arg_POST_INSTALL}")
            message(FATAL_ERROR "dvv_third_party(${name}): POST_INSTALL script not found")
        endif()
    endif()

    dvv_spdx_evaluate("${arg_SPDX}" "${arg_LINKAGE}" allowed reason)
    if(NOT allowed)
        message(FATAL_ERROR "Licence gate: ${name} ${arg_VERSION} (${arg_SPDX}) rejected: ${reason}")
    endif()

    # A name is declared at most once per platform; dependencies must be declared earlier for
    # every platform this declaration is built on.
    foreach(platform IN LISTS platforms)
        get_property(declared GLOBAL PROPERTY "DVV_THIRD_PARTY_DECLARED_${platform}")
        if(name IN_LIST declared)
            message(FATAL_ERROR "dvv_third_party(${name}): declared twice for ${platform}")
        endif()
        foreach(dependency IN LISTS arg_DEPENDS)
            if(NOT dependency IN_LIST declared)
                message(FATAL_ERROR "dvv_third_party(${name}): DEPENDS ${dependency} is not "
                                    "declared before it for ${platform}")
            endif()
        endforeach()
        set_property(GLOBAL APPEND PROPERTY "DVV_THIRD_PARTY_DECLARED_${platform}" "${name}")
    endforeach()

    if(arg_ONLY_ON AND NOT arg_ONLY_ON STREQUAL CMAKE_SYSTEM_NAME)
        return()
    endif()
    set_property(GLOBAL APPEND PROPERTY DVV_THIRD_PARTY_NAMES "${name}")
    foreach(key IN ITEMS VERSION URL SHA256 SPDX LINKAGE LICENSE_FILES DEPENDS PREBUILT CMAKE_ARGS
                         POST_INSTALL CONFIGS SHIPPED)
        set_property(GLOBAL PROPERTY "DVV_THIRD_PARTY_${name}_${key}" "${arg_${key}}")
    endforeach()
endfunction()

# dvv_source_pin(<name> VERSION <v> URL <url> SHA256 <hash>)
# A source archive that is pinned but never downloaded, built or shipped by the superbuild (M4
# design D27: the LAME tarball of rawreel's third-party sources archive). Records the global
# properties DVV_SOURCE_PIN_<name>_VERSION, _URL and _SHA256 and appends <name> to
# DVV_SOURCE_PIN_NAMES; a name is pinned once.
function(dvv_source_pin name)
    cmake_parse_arguments(PARSE_ARGV 1 arg "" "VERSION;URL;SHA256" "")
    if(arg_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "dvv_source_pin(${name}): unexpected '${arg_UNPARSED_ARGUMENTS}'")
    endif()
    foreach(required IN ITEMS VERSION URL SHA256)
        if(NOT arg_${required})
            message(FATAL_ERROR "dvv_source_pin(${name}): ${required} is required")
        endif()
    endforeach()
    if(NOT arg_SHA256 MATCHES "^[0-9a-f]+$")
        message(FATAL_ERROR "dvv_source_pin(${name}): SHA256 must be 64 lower-case hex digits")
    endif()
    string(LENGTH "${arg_SHA256}" hash_length)
    if(NOT hash_length EQUAL 64)
        message(FATAL_ERROR "dvv_source_pin(${name}): SHA256 must be 64 lower-case hex digits")
    endif()
    get_property(pinned GLOBAL PROPERTY DVV_SOURCE_PIN_NAMES)
    if(name IN_LIST pinned)
        message(FATAL_ERROR "dvv_source_pin(${name}): pinned twice")
    endif()
    set_property(GLOBAL APPEND PROPERTY DVV_SOURCE_PIN_NAMES "${name}")
    foreach(key IN ITEMS VERSION URL SHA256)
        set_property(GLOBAL PROPERTY "DVV_SOURCE_PIN_${name}_${key}" "${arg_${key}}")
    endforeach()
endfunction()

# dvv_licence_supplement(<name> FILE <path> COMPONENT <component> VERSION <v> URL <url>
#                        SHA256 <hash>)
# A licence text that entry <name>'s archive needs but does not contain, kept in the repository at
# licenses/<name>-supplement/<path> next to the declaring file, taken unchanged from <url> (the
# upstream file of <component> <v>) and pinned by its SHA256. Fails configuration when <name> is
# not declared before it, the file is missing or its SHA256 differs. Appends
# "<absolute file>|<hash>|<path>|<component>|<v>|<url>" to the global property
# DVV_THIRD_PARTY_<name>_SUPPLEMENTS; the notices copy the text after the entry's licence files.
function(dvv_licence_supplement name)
    cmake_parse_arguments(PARSE_ARGV 1 arg "" "FILE;COMPONENT;VERSION;URL;SHA256" "")
    if(arg_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "dvv_licence_supplement(${name}): unexpected "
                            "'${arg_UNPARSED_ARGUMENTS}'")
    endif()
    foreach(required IN ITEMS FILE COMPONENT VERSION URL SHA256)
        if(NOT arg_${required})
            message(FATAL_ERROR "dvv_licence_supplement(${name}): ${required} is required")
        endif()
        if(arg_${required} MATCHES "[|;]")
            message(FATAL_ERROR "dvv_licence_supplement(${name}): ${required} must not contain "
                                "'|' or ';'")
        endif()
    endforeach()
    if(NOT arg_SHA256 MATCHES "^[0-9a-f]+$")
        message(FATAL_ERROR "dvv_licence_supplement(${name}): SHA256 must be 64 lower-case hex "
                            "digits")
    endif()
    string(LENGTH "${arg_SHA256}" hash_length)
    if(NOT hash_length EQUAL 64)
        message(FATAL_ERROR "dvv_licence_supplement(${name}): SHA256 must be 64 lower-case hex "
                            "digits")
    endif()
    if(IS_ABSOLUTE "${arg_FILE}" OR arg_FILE MATCHES "(^|/)\\.\\.(/|$)|\\\\")
        message(FATAL_ERROR "dvv_licence_supplement(${name}): FILE must be a relative path with "
                            "'/' and without '..'")
    endif()
    set(declared "")
    foreach(platform IN LISTS DVV_THIRD_PARTY_PLATFORMS)
        get_property(on_platform GLOBAL PROPERTY "DVV_THIRD_PARTY_DECLARED_${platform}")
        list(APPEND declared ${on_platform})
    endforeach()
    if(NOT name IN_LIST declared)
        message(FATAL_ERROR "dvv_licence_supplement(${name}): ${name} is not declared before it")
    endif()
    set(file "${CMAKE_CURRENT_LIST_DIR}/licenses/${name}-supplement/${arg_FILE}")
    if(NOT EXISTS "${file}" OR IS_DIRECTORY "${file}")
        message(FATAL_ERROR "dvv_licence_supplement(${name}): licenses/${name}-supplement/"
                            "${arg_FILE} not found")
    endif()
    file(SHA256 "${file}" actual)
    if(NOT actual STREQUAL arg_SHA256)
        message(FATAL_ERROR "dvv_licence_supplement(${name}): licenses/${name}-supplement/"
                            "${arg_FILE} has SHA256 ${actual}, pinned ${arg_SHA256}")
    endif()
    set_property(GLOBAL APPEND PROPERTY "DVV_THIRD_PARTY_${name}_SUPPLEMENTS"
        "${file}|${arg_SHA256}|${arg_FILE}|${arg_COMPONENT}|${arg_VERSION}|${arg_URL}")
endfunction()

# dvv_third_party_build_configs(<name> <multi_config> <out_var>): the configurations to build and
# install for <name>, in order. A single-config generator builds Release only, so a declaration
# with other CONFIGS fails configuration there.
function(dvv_third_party_build_configs name multi_config out_var)
    get_property(configs GLOBAL PROPERTY "DVV_THIRD_PARTY_${name}_CONFIGS")
    if(NOT multi_config AND NOT configs STREQUAL "Release")
        list(JOIN configs " " shown)
        message(FATAL_ERROR "dvv_third_party(${name}): CONFIGS ${shown} needs a multi-config "
                            "generator (Visual Studio); a single-config generator builds Release only")
    endif()
    set(${out_var} ${configs} PARENT_SCOPE)
endfunction()
