# Builds a small wx console program against the third-party prefix with the dvv compiler settings
# (warnings as errors, C++23, NOMINMAX/WIN32_LEAN_AND_MEAN/UNICODE on MSVC): the same way rawreel-gui
# will consume wx. Driven by run-wx-consumer.cmake.
cmake_minimum_required(VERSION 4.2)
project(wx_consumer LANGUAGES CXX)
include("${DVV_CMAKE_DIR}/DvvCompilerOptions.cmake")
find_package(wxWidgets 3.3 CONFIG REQUIRED COMPONENTS core base)
add_executable(wx_consumer main.cpp)
target_link_libraries(wx_consumer PRIVATE wx::core wx::base)
dvv_set_compiler_options(wx_consumer)
