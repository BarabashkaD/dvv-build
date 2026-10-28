# Every third-party dependency with version, download URL, SHA256 and SPDX licence (spec §13.2).
# An entry may only depend on (DEPENDS) entries above it. Later milestones append their dependencies
# here. GitHub does not guarantee the bytes of "archive/refs/tags" tarballs; if one changes, the SHA256
# check fails the build, which is intended.

dvv_third_party(nlohmann_json
    VERSION 3.12.0
    URL https://github.com/nlohmann/json/releases/download/v3.12.0/json.tar.xz
    SHA256 42f6e95cad6ec532fd372391373363b62a14af6d771056dbfc86160e6dfff7aa
    SPDX MIT
    LINKAGE static
    SHIPPED
    LICENSE_FILES LICENSE.MIT
    CMAKE_ARGS -DJSON_BuildTests=OFF -DJSON_Install=ON)

dvv_third_party(doctest
    VERSION 2.5.3
    URL https://github.com/doctest/doctest/releases/download/v2.5.3/doctest-v2.5.3.tar.gz
    SHA256 eb4a39729d091e43d4d593888bf4d145ee9a0f0e13f7404484b6f2fb60d5d50f
    SPDX MIT
    LINKAGE static
    LICENSE_FILES LICENSE.txt
    CMAKE_ARGS -DDOCTEST_WITH_TESTS=OFF -DDOCTEST_WITH_MAIN_IN_STATIC_LIB=OFF)

# Vulkan (spec §5). Vulkan-Headers includes Vulkan-Hpp.
dvv_third_party(Vulkan-Headers
    VERSION 1.4.365
    URL https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/v1.4.365.tar.gz
    SHA256 ed832b3292cce324ebba6522fd2d3004bf1b797fa49bfbcad0b302ff23d56abc
    SPDX "Apache-2.0 OR MIT"
    LINKAGE static
    SHIPPED
    # LICENSE.md only names the licences; the text of the one used is in LICENSES/.
    LICENSE_FILES LICENSES/MIT.txt
    CMAKE_ARGS -DVULKAN_HEADERS_ENABLE_TESTS=OFF -DVULKAN_HEADERS_ENABLE_MODULE=OFF)

# Header-only; GPUOpen::VulkanMemoryAllocator carries no Vulkan headers of its own.
dvv_third_party(VulkanMemoryAllocator
    VERSION 3.4.0
    URL https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator/archive/refs/tags/v3.4.0.tar.gz
    SHA256 822aa850c6ce77346ae96a8a1d351d52e77e85929f35363849a0a4e638e0a2a1
    SPDX MIT
    LINKAGE static
    SHIPPED
    LICENSE_FILES LICENSE.txt
    CMAKE_ARGS -DVMA_ENABLE_INSTALL=ON)

# dvv-gpu compiles the installed src/vk-bootstrap/VkBootstrap.cpp itself: an MSVC Debug build
# cannot link the Release library. Without the two find_package switches vk-bootstrap would take
# the headers of an installed Vulkan SDK.
dvv_third_party(vk-bootstrap
    VERSION 1.4.365
    URL https://github.com/charles-lunarg/vk-bootstrap/archive/refs/tags/v1.4.365.tar.gz
    SHA256 35eef8e046ca0a63f2ffc180a52561081d71bd18d19395a45fb78eb095423b4b
    SPDX MIT
    LINKAGE static
    SHIPPED
    LICENSE_FILES LICENSE.txt
    DEPENDS Vulkan-Headers
    CMAKE_ARGS -DVK_BOOTSTRAP_TEST=OFF -DVK_BOOTSTRAP_INSTALL=ON
               -DCMAKE_DISABLE_FIND_PACKAGE_Vulkan=ON -DCMAKE_REQUIRE_FIND_PACKAGE_VulkanHeaders=ON
    POST_INSTALL post-install/vk-bootstrap.cmake)

# Slang shader compiler (spec §5), used at build time only: prebuilt release archives, installed as
# <prefix>/slang. The archives bundle LLVM code (NCSA), documentation (CC-BY-4.0) and glslang
# (partly GPL-3.0-or-later WITH Bison-exception-2.2); the expression lists everything they contain.
# The Linux archive for glibc 2.28 runs on older systems and lacks only slang-llvm, which SPIR-V
# output does not use. Its symbolic links survive only when it is extracted on Linux.
dvv_third_party(slang
    VERSION 2026.20
    URL https://github.com/shader-slang/slang/releases/download/v2026.20/slang-2026.20-windows-x86_64.zip
    SHA256 e6dd32bbddf1720ebb4e679d55e9635ce792865a5bd84f3d2cd9af28647c0174
    SPDX "Apache-2.0 WITH LLVM-exception AND Apache-2.0 AND MIT AND BSD-2-Clause AND BSD-3-Clause \
AND BSL-1.0 AND Unlicense AND GPL-3.0-or-later WITH Bison-exception-2.2 AND NCSA AND CC-BY-4.0"
    LINKAGE tool
    LICENSE_FILES LICENSE LICENSES/*.txt third-party-notices/*
    ONLY_ON Windows
    PREBUILT)

dvv_third_party(slang
    VERSION 2026.20
    URL https://github.com/shader-slang/slang/releases/download/v2026.20/slang-2026.20-linux-x86_64-glibc-2.28.tar.gz
    SHA256 84ebd777968caceea26b21bfd014341078be6047be6c5a963a69f984f896cebd
    SPDX "Apache-2.0 WITH LLVM-exception AND Apache-2.0 AND MIT AND BSD-2-Clause AND BSD-3-Clause \
AND BSL-1.0 AND Unlicense AND GPL-3.0-or-later WITH Bison-exception-2.2 AND NCSA AND CC-BY-4.0"
    LINKAGE tool
    LICENSE_FILES LICENSE LICENSES/*.txt third-party-notices/*
    ONLY_ON Linux
    PREBUILT)

# Vulkan validation layer (spec §5, §12) and what it is built from: loaded by the Vulkan loader in
# Debug builds and tests only, never shipped. The versions are the set Vulkan-ValidationLayers
# 1.4.365 pins in scripts/known_good.json. Vulkan-Utility-Libraries, SPIRV-Headers and SPIRV-Tools
# are linked into the layer, so they have its linkage (runtime), not tool.
dvv_third_party(Vulkan-Utility-Libraries
    VERSION 1.4.365
    URL https://github.com/KhronosGroup/Vulkan-Utility-Libraries/archive/refs/tags/v1.4.365.tar.gz
    SHA256 257a8069bac42663471af2eda04901fd195c44eb92badab55124001215151857
    SPDX Apache-2.0
    LINKAGE runtime
    LICENSE_FILES LICENSES/Apache-2.0.txt
    DEPENDS Vulkan-Headers
    CMAKE_ARGS -DBUILD_TESTS=OFF)

# The known-good commit 496543121ce6. Its *.md documents are CC-BY-4.0 and are not installed.
dvv_third_party(SPIRV-Headers
    VERSION vulkan-sdk-1.4.363.0
    URL https://github.com/KhronosGroup/SPIRV-Headers/archive/refs/tags/vulkan-sdk-1.4.363.0.tar.gz
    SHA256 5b3a0d099f5c7649e29c0938476c462e71d66ad89a0bde42fa1ba3eb476956c9
    SPDX MIT
    LINKAGE runtime
    LICENSE_FILES LICENSE
    CMAKE_ARGS -DSPIRV_HEADERS_ENABLE_TESTS=OFF -DSPIRV_HEADERS_ENABLE_INSTALL=ON)

# The known-good commit ef96ed763b43. SPIRV-Headers_SOURCE_DIR may name the prefix, because only its
# include/ directory is used.
dvv_third_party(SPIRV-Tools
    VERSION 2026.4
    URL https://github.com/KhronosGroup/SPIRV-Tools/archive/refs/tags/v2026.4.tar.gz
    SHA256 92df4c377603f086c3d2a1eb2bd9b8f883a73ca890fb939d78a0cecdcc01686c
    SPDX Apache-2.0
    LINKAGE runtime
    LICENSE_FILES LICENSE
    DEPENDS SPIRV-Headers
    CMAKE_ARGS -DSPIRV-Headers_SOURCE_DIR=<INSTALL_DIR> -DSPIRV_SKIP_TESTS=ON
               -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_WERROR=OFF)

# Needs Python 3 to build. UPDATE_DEPS would clone every dependency at configure time. Bundled in
# layers/external: parallel_hashmap (Apache-2.0), xxhash.h (BSD-2-Clause), inplace_function.h
# (BSL-1.0) and VMA (MIT). On Linux the layer is built with its XCB, Xlib (+XRandR) and Wayland WSI
# support (pkg-config modules xcb, x11, xrandr and wayland-client), so it validates surfaces and
# swapchains; Windows always has Win32 WSI. The WSI options are explicit ON, so a build tree
# configured without them is reconfigured. The post-install step lets the Linux manifest find its
# library.
dvv_third_party(Vulkan-ValidationLayers
    VERSION 1.4.365
    URL https://github.com/KhronosGroup/Vulkan-ValidationLayers/archive/refs/tags/v1.4.365.tar.gz
    SHA256 2212c1f9dd3658704929168858ff7bec0935c4e87cee5aed6b3d9735af4929ad
    SPDX "Apache-2.0 AND BSD-2-Clause AND BSL-1.0 AND MIT"
    LINKAGE runtime
    LICENSE_FILES LICENSE.txt LICENSES/*.txt
    DEPENDS Vulkan-Headers Vulkan-Utility-Libraries SPIRV-Headers SPIRV-Tools
    CMAKE_ARGS -DUPDATE_DEPS=OFF -DBUILD_TESTS=OFF -DBUILD_WERROR=OFF -DUSE_MIMALLOC=OFF
               -DBUILD_WSI_XCB_SUPPORT=ON -DBUILD_WSI_XLIB_SUPPORT=ON
               -DBUILD_WSI_XLIB_XRANDR_SUPPORT=ON -DBUILD_WSI_WAYLAND_SUPPORT=ON
    POST_INSTALL post-install/Vulkan-ValidationLayers.cmake)

# wxWidgets (spec §2, §10.2), static. MSVC builds Debug and Release (Debug builds of rawreel link the
# /MDd libraries); Debug objects carry their debug information (/Z7, no separate PDB, so a Debug
# consumer link shows no LNK4099), Release objects none. Regex, XML, image formats other than PNG,
# web, media and GL parts are off: not needed through v1, and they keep the licence small. wxcore
# always contains a JPEG-derived colour quantizer (IJG), an ImageMagick/libXpm-derived XPM decoder
# (X11) and Unicode CLDR-derived language tables (Unicode-DFS-2016); nanosvg is bundled (Zlib).
# wxUSE_APPLE_IEEE is off: its extended.c has a licence without an SPDX id.
# The genex is escaped once, because ExternalProject evaluates its arguments in the superbuild:
# wx receives $<$<CONFIG:Debug>:Embedded>.
dvv_third_party(wxWidgets
    VERSION 3.3.4
    URL https://github.com/wxWidgets/wxWidgets/releases/download/v3.3.4/wxWidgets-3.3.4.tar.bz2
    SHA256 815c16cafa4fcbfcf25c5c0a3418309c62257b8a3b6f91d85a1367a134f98c98
    SPDX "LGPL-2.0-or-later WITH WxWindows-exception-3.1 AND IJG AND X11 AND Unicode-DFS-2016 \
AND Zlib AND libpng-2.0"
    LINKAGE static
    SHIPPED
    LICENSE_FILES docs/licence.txt docs/lgpl.txt src/jpeg/README src/common/xpmdecod.cpp
                  misc/languages/data/unicode/unicode-license.txt 3rdparty/nanosvg/LICENSE.txt
                  src/zlib/LICENSE src/png/LICENSE
    ONLY_ON Windows
    CONFIGS Debug Release
    CMAKE_ARGS -DwxBUILD_TOOLKIT=msw -DwxBUILD_SHARED=OFF -DwxBUILD_USE_STATIC_RUNTIME=OFF
               -DwxBUILD_SAMPLES=OFF -DwxBUILD_TESTS=OFF -DwxBUILD_DEMOS=OFF -DwxBUILD_INSTALL=ON
               -DwxBUILD_CXX_STANDARD=17
               -DwxUSE_ZLIB=builtin -DwxUSE_LIBPNG=builtin -DwxUSE_LIBJPEG=OFF -DwxUSE_LIBTIFF=OFF
               -DwxUSE_LIBWEBP=OFF -DwxUSE_LUNASVG=OFF -DwxUSE_NANOSVG=builtin -DwxUSE_REGEX=OFF
               -DwxUSE_EXPAT=OFF -DwxUSE_XML=OFF -DwxUSE_XRC=OFF -DwxUSE_RICHTEXT=OFF
               -DwxUSE_STC=OFF -DwxUSE_WEBVIEW=OFF -DwxUSE_MEDIACTRL=OFF -DwxUSE_OPENGL=OFF
               -DwxUSE_WEBREQUEST=OFF -DwxUSE_SECRETSTORE=OFF -DwxUSE_APPLE_IEEE=OFF
               "-DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT=$<1:$><$<1:$><CONFIG:Debug$<ANGLE-R>:Embedded$<ANGLE-R>")

# Linux: Release only (no debug ABI split in libstdc++), GTK 3, the system's zlib and libpng. Options
# that wx would otherwise detect from installed -dev packages are pinned, so CI runners (which have
# more of them) build the same library as WSL.
# wxUSE_WAYLAND is off: rawreel runs GTK on X11 (GDK_BACKEND=x11, Wayland is v1.x), and wx's
# Wayland code compiles MIT-licensed wayland-scanner output, partly generated from the system's
# wayland-protocols.
dvv_third_party(wxWidgets
    VERSION 3.3.4
    URL https://github.com/wxWidgets/wxWidgets/releases/download/v3.3.4/wxWidgets-3.3.4.tar.bz2
    SHA256 815c16cafa4fcbfcf25c5c0a3418309c62257b8a3b6f91d85a1367a134f98c98
    SPDX "LGPL-2.0-or-later WITH WxWindows-exception-3.1 AND IJG AND X11 AND Unicode-DFS-2016 \
AND Zlib"
    LINKAGE static
    SHIPPED
    LICENSE_FILES docs/licence.txt docs/lgpl.txt src/jpeg/README src/common/xpmdecod.cpp
                  misc/languages/data/unicode/unicode-license.txt 3rdparty/nanosvg/LICENSE.txt
    ONLY_ON Linux
    CMAKE_ARGS -DwxBUILD_TOOLKIT=gtk3 -DwxBUILD_SHARED=OFF
               -DwxBUILD_SAMPLES=OFF -DwxBUILD_TESTS=OFF -DwxBUILD_DEMOS=OFF -DwxBUILD_INSTALL=ON
               -DwxBUILD_CXX_STANDARD=17
               -DwxUSE_ZLIB=sys -DwxUSE_LIBPNG=sys -DwxUSE_LIBJPEG=OFF -DwxUSE_LIBTIFF=OFF
               -DwxUSE_LIBWEBP=OFF -DwxUSE_LUNASVG=OFF -DwxUSE_NANOSVG=builtin -DwxUSE_REGEX=OFF
               -DwxUSE_EXPAT=OFF -DwxUSE_XML=OFF -DwxUSE_XRC=OFF -DwxUSE_RICHTEXT=OFF
               -DwxUSE_STC=OFF -DwxUSE_WEBVIEW=OFF -DwxUSE_MEDIACTRL=OFF -DwxUSE_OPENGL=OFF
               -DwxUSE_WEBREQUEST=OFF -DwxUSE_SECRETSTORE=OFF -DwxUSE_APPLE_IEEE=OFF
               -DwxUSE_LIBSDL=OFF -DwxUSE_LIBNOTIFY=OFF -DwxUSE_LIBMSPACK=OFF
               -DwxUSE_LIBGNOMEVFS=OFF -DwxUSE_GLCANVAS_EGL=OFF -DwxUSE_SPELLCHECK=OFF
               -DwxUSE_LIBLZMA=OFF -DwxUSE_WEBREQUEST_CURL=OFF
               -DwxUSE_XTEST=OFF -DwxUSE_APPINDICATOR=OFF -DwxUSE_DETECT_SM=OFF -DwxUSE_WAYLAND=OFF)

# FFmpeg (spec §2, §13.2; M4 design D3, §9): the custom_ffmpeg "lgpl" shared release, loaded at run
# time and never linked. dvv-components compiles against its headers (through dvv_ffmpeg_sdk,
# written by deps/CMakeLists.txt); its six run-time libraries ship in the Windows package's ffmpeg/
# folder only with DVV_BUNDLE_FFMPEG (user decision U4); its ffmpeg and ffprobe programs serve the
# tests as an oracle. The Linux archive is pinned for the clang prefix (headers for the lint and the
# Linux sanity build); v1.0 has no Linux package (user decision U-WIN; Linux packaging is v1.x).
# Contents: FFmpeg (LGPL-2.1-or-later), LAME (LGPL-2.0-or-later), libvpx, libwebp, Opus, Ogg, Vorbis
# (BSD-3-Clause), SVT-AV1 (BSD-3-Clause-Clear, with the AOM patent licence), dav1d (BSD-2-Clause),
# zlib (Zlib), libvpl, AMF and ffnvcodec headers (MIT); on Linux also libva and libdrm (MIT). Patent
# grants (AOM, the libvpx and libwebp PATENTS files) are not licence expressions; they are licence
# files, so they reach the notices. The release's build attestation was verified when these were
# pinned (M4 Task 0) and is verified again by rawreel's release workflow.
# Each archive has one top folder (dropped on extraction) whose <os>-x64/shared/lgpl/ holds bin/,
# include/, lib/ and share/; the licence files are share/licenses/<component>/<file>.
# The test scripts include this file without DVV_BUNDLE_FFMPEG, which counts as ON.
if(NOT DEFINED DVV_BUNDLE_FFMPEG OR DVV_BUNDLE_FFMPEG)
    set(custom_ffmpeg_shipped SHIPPED)
else()
    set(custom_ffmpeg_shipped "")
endif()
dvv_third_party(custom_ffmpeg
    VERSION 1.0.0
    URL https://github.com/BarabashkaD/custom_ffmpeg/releases/download/v1.0.0/custom_ffmpeg-1.0.0-windows-x64-shared-lgpl.zip
    SHA256 ab8ff75ec9cb8d4ff032569e269b990621fd8b8f67d9a585261f131e6d5d25d5
    SPDX "LGPL-2.1-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND BSD-2-Clause \
AND BSD-3-Clause-Clear AND MIT AND Zlib"
    LINKAGE runtime
    LICENSE_FILES windows-x64/shared/lgpl/share/licenses/*/*
    ONLY_ON Windows
    PREBUILT
    ${custom_ffmpeg_shipped})

dvv_third_party(custom_ffmpeg
    VERSION 1.0.0
    URL https://github.com/BarabashkaD/custom_ffmpeg/releases/download/v1.0.0/custom_ffmpeg-1.0.0-linux-x64-shared-lgpl.tar.xz
    SHA256 34ec4f5b1dc0187cfa3268cd5b164f46a10f021f8dc1f6130ff215ef772b8a11
    SPDX "LGPL-2.1-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND BSD-2-Clause \
AND BSD-3-Clause-Clear AND MIT AND Zlib"
    LINKAGE runtime
    LICENSE_FILES linux-x64/shared/lgpl/share/licenses/*/*
    ONLY_ON Linux
    PREBUILT
    ${custom_ffmpeg_shipped})

# Licence texts that custom_ffmpeg's LICENSES.md names but its archives do not contain, taken
# unchanged from the commits its build-info.txt names (SVT-AV1 4.2.0 @ 9292ec8e3 = tag v4.2.0,
# libvpl 2.17 @ d77f9195c = tag v2.17.0). SVT-AV1's encoder library compiles in fastfeat
# (BSD-3-Clause) and safestringlib (MIT). libvpl's third-party-programs.txt covers its googletest
# and Open Model Zoo code, which are in its tests and examples, not in the dispatcher, so the SPDX
# expression above does not change.
dvv_licence_supplement(custom_ffmpeg
    FILE svtav1/third_party/fastfeat/LICENSE
    COMPONENT SVT-AV1
    VERSION 4.2.0
    URL https://gitlab.com/AOMediaCodec/SVT-AV1/-/raw/9292ec8e32bce26f781f277ec8739b53426c4300/third_party/fastfeat/LICENSE
    SHA256 043dcfd059386f9facd376351b2bd79325778744aa442177390cdfcca54babed)
dvv_licence_supplement(custom_ffmpeg
    FILE svtav1/third_party/safestringlib/LICENSE
    COMPONENT SVT-AV1
    VERSION 4.2.0
    URL https://gitlab.com/AOMediaCodec/SVT-AV1/-/raw/9292ec8e32bce26f781f277ec8739b53426c4300/third_party/safestringlib/LICENSE
    SHA256 c0f99a208799ca20c9ccf31a30533d49334eb458dca5a3d14f9afe3e884e5d7d)
dvv_licence_supplement(custom_ffmpeg
    FILE libvpl/third-party-programs.txt
    COMPONENT libvpl
    VERSION 2.17.0
    URL https://raw.githubusercontent.com/intel/libvpl/d77f9195cf495b937631607333288fd917ae8939/third-party-programs.txt
    SHA256 e3c92992b1df02b467ac086d7d3730f4c1fc2c2a1f2c520657c4c9f2085305a3)

# LAME 3.100 source tarball (M4 design D27): LAME is inside custom_ffmpeg's libraries; the tarball is
# pinned only for rawreel's third-party sources archive and is never downloaded by the superbuild,
# built or shipped in a package.
dvv_source_pin(lame
    VERSION 3.100
    URL https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz
    SHA256 ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e)
