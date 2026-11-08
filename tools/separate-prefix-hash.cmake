# Prints the marker that the third-party superbuild writes into the separate prefix of entry NAME
# (SEPARATE_PREFIX in deps/versions.cmake) on this host: dvv_third_party_separate_prefix_hash() of
# cmake/DvvThirdParty.cmake. bootstrap compares it with <prefix>-<suffix>/dvv-inputs.sha256, and CI
# uses it in the cache key of that prefix.
#   cmake -DNAME=wxWidgets -DTOOLCHAIN=<prefix folder name: msvc, clang, appleclang> \
#         -P tools/separate-prefix-hash.cmake
# Output: one line "hash=<64 hex digits>" on standard output.
cmake_minimum_required(VERSION 4.2)
if(NOT NAME OR NOT TOOLCHAIN)
    message(FATAL_ERROR "pass -DNAME=<entry> and -DTOOLCHAIN=<prefix folder name>")
endif()
include("${CMAKE_CURRENT_LIST_DIR}/../cmake/DvvThirdParty.cmake")
# versions.cmake declares the entries for CMAKE_SYSTEM_NAME, which a script has not set. The
# option's default in deps/CMakeLists.txt; it does not change any entry with a separate prefix.
set(CMAKE_SYSTEM_NAME "${CMAKE_HOST_SYSTEM_NAME}")
set(DVV_BUNDLE_FFMPEG ON)
include("${CMAKE_CURRENT_LIST_DIR}/../deps/versions.cmake")
dvv_third_party_separate_prefix_hash("${NAME}" "${TOOLCHAIN}" hash)
execute_process(COMMAND "${CMAKE_COMMAND}" -E echo "hash=${hash}")
