# Short ExternalProject trees for the third-party superbuild. Part of dvv-build.
# bootstrap passes this file as -DCMAKE_PROJECT_INCLUDE=<dvv-build>/cmake/DvvEpBase.cmake, so every
# dependency builds in <build>/Build/<name> (sources in Source/<name>, stamps in Stamp/<name>) instead
# of <build>/<name>-prefix/src/<name>-build. This keeps the Windows paths short without editing deps/.
set_property(DIRECTORY PROPERTY EP_BASE "${CMAKE_BINARY_DIR}")
