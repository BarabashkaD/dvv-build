# Post-install step of vk-bootstrap (deps/versions.cmake), called with -DSOURCE_DIR=<extracted
# archive> -DPREFIX=<install prefix>. Installs src/VkBootstrap.cpp as
# <prefix>/src/vk-bootstrap/VkBootstrap.cpp for targets that compile it themselves.
cmake_minimum_required(VERSION 4.2)
foreach(required IN ITEMS SOURCE_DIR PREFIX)
    if(NOT ${required})
        message(FATAL_ERROR "vk-bootstrap post-install: pass -D${required}=<directory>")
    endif()
endforeach()
file(COPY "${SOURCE_DIR}/src/VkBootstrap.cpp" DESTINATION "${PREFIX}/src/vk-bootstrap")
