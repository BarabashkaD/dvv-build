# Third-party dependency declarations (spec §13.2).
#
# dvv_third_party(<name> VERSION <v> URL <url> SHA256 <hash> SPDX <expression>
#                 LINKAGE static|runtime|tool LICENSE_FILES <path or glob in archive>...
#                 [ONLY_ON Windows|Linux|Darwin] [DEPENDS <name>...] [CONFIGS Debug|Release...]
#                 [PREBUILT | CMAKE_ARGS <args>...] [POST_INSTALL <script>] [SHIPPED])
# Records the dependency in global properties and fails configuration when its SPDX expression is
# not allowed for its linkage. Every declaration passes the licence gate on every platform; ONLY_ON
# only decides where it is built.
#   LICENSE_FILES  copied into THIRD_PARTY_NOTICES.txt; a glob must match at least one file.
#   DEPENDS        dependencies declared earlier that must be installed first.
#   CONFIGS        configurations built and installed, in this order (default Release). Only a
#                  multi-config generator (Visual Studio) can build more than Release; not with
#                  PREBUILT.
#   PREBUILT       nothing is built: the archive's content is installed under <prefix>/<name>. A
#                  PREBUILT entry with the URL and SHA256 of an entry it DEPENDS on shares that
#                  entry's archive (dvv_third_party_shared_archive): nothing is downloaded or
#                  extracted for it, and its licence files are looked up in that entry's folder.
#   SHIPPED        the entry's code or files are in a rawreel package: only shipped entries go
#                  into THIRD_PARTY_NOTICES.txt (M4 design D19). Not with LINKAGE tool.
#   CMAKE_ARGS     extra configure arguments; <INSTALL_DIR> stands for the install prefix.
#   POST_INSTALL   CMake script, relative to the declaring file, run after the install as
#                  cmake -DSOURCE_DIR=<extracted archive> -DPREFIX=<install prefix>
#                  -DBINARY_DIR=<the entry's build directory> -P <script>.
include_guard(GLOBAL)
include("${CMAKE_CURRENT_LIST_DIR}/DvvSpdx.cmake")

set(DVV_THIRD_PARTY_PLATFORMS Windows Linux Darwin)

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
#                        SHA256 <hash> [PLATFORMS Windows|Linux|Darwin...])
# A licence text that entry <name>'s archive needs but does not contain, kept in the repository at
# licenses/<name>-supplement/<path> next to the declaring file, taken unchanged from <url> (the
# upstream file of <component> <v>) and pinned by its SHA256. A notice collected from the source
# tree <url> (copyright lines spread over many files) says in its own text how it was collected.
# Fails configuration when <name> is not declared before it, the file is missing or its SHA256
# differs. Appends "<absolute file>|<hash>|<path>|<component>|<v>|<url>" to the global property
# DVV_THIRD_PARTY_<name>_SUPPLEMENTS, where the notices copy the text after the entry's licence
# files. PLATFORMS (default: all) names the platforms whose build of <name> contains <component>;
# elsewhere the file is still checked but not appended.
function(dvv_licence_supplement name)
    cmake_parse_arguments(PARSE_ARGV 1 arg "" "FILE;COMPONENT;VERSION;URL;SHA256" "PLATFORMS")
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
    foreach(platform IN LISTS arg_PLATFORMS)
        if(NOT platform IN_LIST DVV_THIRD_PARTY_PLATFORMS)
            message(FATAL_ERROR "dvv_licence_supplement(${name}): PLATFORMS must name Windows, "
                                "Linux or Darwin, not '${platform}'")
        endif()
    endforeach()
    if(arg_PLATFORMS AND NOT CMAKE_SYSTEM_NAME IN_LIST arg_PLATFORMS)
        return()
    endif()
    set_property(GLOBAL APPEND PROPERTY "DVV_THIRD_PARTY_${name}_SUPPLEMENTS"
        "${file}|${arg_SHA256}|${arg_FILE}|${arg_COMPONENT}|${arg_VERSION}|${arg_URL}")
endfunction()

# dvv_third_party_common_args(<out_var>): the configure arguments every project the superbuild
# builds gets: install prefix and search path <INSTALL_DIR>, Release, the superbuild's C and C++
# compilers; with Visual Studio parallel compilation within a project; on Apple the deployment
# target and the architectures (CMAKE_OSX_DEPLOYMENT_TARGET, CMAKE_OSX_ARCHITECTURES, both
# required), since a project built without them targets the SDK's macOS version, the Objective-C
# compilers, and -ffile-prefix-map for the project's source, build and install folders in the C,
# C++, Objective-C and Objective-C++ flags.
function(dvv_third_party_common_args out_var)
    # Every project finds the ones installed before it in the prefix. Every project gets both
    # compilers, and a C++-only project need not report the unused C one.
    set(args
        --no-warn-unused-cli
        "-DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>"
        "-DCMAKE_PREFIX_PATH=<INSTALL_DIR>"
        "-DCMAKE_BUILD_TYPE=Release"
        "-DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}"
        "-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}")
    if(CMAKE_GENERATOR MATCHES "^Visual Studio")
        # MSBuild otherwise compiles the files of one project one after another.
        list(APPEND args "-DCMAKE_VS_GLOBALS=UseMultiToolTask=true")
    endif()
    if(APPLE)
        if(NOT CMAKE_OSX_DEPLOYMENT_TARGET OR NOT CMAKE_OSX_ARCHITECTURES)
            message(FATAL_ERROR "CMAKE_OSX_DEPLOYMENT_TARGET and CMAKE_OSX_ARCHITECTURES must be "
                                "set on Apple (bootstrap.sh passes 27.0 and arm64)")
        endif()
        # Objective-C(++) (wxWidgets' Cocoa code) uses the same compilers, not one found in PATH.
        list(APPEND args "-DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}"
                         "-DCMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}"
                         "-DCMAKE_OBJC_COMPILER=${CMAKE_C_COMPILER}"
                         "-DCMAKE_OBJCXX_COMPILER=${CMAKE_CXX_COMPILER}")
        # The project's source, build and install folders are mapped out of __FILE__ and debug
        # information (ExternalProject substitutes the placeholders per project), so the shipped
        # wxWidgets objects and the loader carry no machine path.
        set(maps "-ffile-prefix-map=<SOURCE_DIR>/= -ffile-prefix-map=<BINARY_DIR>/= "
                 "-ffile-prefix-map=<INSTALL_DIR>/=")
        string(CONCAT maps ${maps})
        foreach(language IN ITEMS C CXX OBJC OBJCXX)
            list(APPEND args "-DCMAKE_${language}_FLAGS=${maps}")
        endforeach()
    endif()
    set(${out_var} "${args}" PARENT_SCOPE)
endfunction()

# dvv_third_party_shared_archive(<name> <out_var>): for a PREBUILT entry, the first entry of its
# DEPENDS with the same URL and SHA256, whose extracted archive it shares; empty otherwise.
function(dvv_third_party_shared_archive name out_var)
    set(shared "")
    foreach(key IN ITEMS PREBUILT URL SHA256 DEPENDS)
        get_property(${key} GLOBAL PROPERTY "DVV_THIRD_PARTY_${name}_${key}")
    endforeach()
    if(PREBUILT)
        foreach(dependency IN LISTS DEPENDS)
            get_property(dependency_url GLOBAL PROPERTY "DVV_THIRD_PARTY_${dependency}_URL")
            get_property(dependency_sha256 GLOBAL PROPERTY "DVV_THIRD_PARTY_${dependency}_SHA256")
            if(dependency_url STREQUAL URL AND dependency_sha256 STREQUAL SHA256)
                set(shared "${dependency}")
                break()
            endif()
        endforeach()
    endif()
    set(${out_var} "${shared}" PARENT_SCOPE)
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
