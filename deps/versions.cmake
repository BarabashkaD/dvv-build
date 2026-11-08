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

# The macOS archive for Apple Silicon includes slang-llvm, like the Windows one.
dvv_third_party(slang
    VERSION 2026.20
    URL https://github.com/shader-slang/slang/releases/download/v2026.20/slang-2026.20-macos-aarch64.tar.gz
    SHA256 07fa8833fdbb343c3674c84fdd885910f495f3daaaa0c732b32980151e8b58c4
    SPDX "Apache-2.0 WITH LLVM-exception AND Apache-2.0 AND MIT AND BSD-2-Clause AND BSD-3-Clause \
AND BSL-1.0 AND Unlicense AND GPL-3.0-or-later WITH Bison-exception-2.2 AND NCSA AND CC-BY-4.0"
    LINKAGE tool
    LICENSE_FILES LICENSE LICENSES/*.txt third-party-notices/*
    ONLY_ON Darwin
    PREBUILT)

# macOS (spec U-MAC2): the Vulkan loader is built from source and shipped in the app bundle (on
# Windows and Linux the system's loader is used). Its install name is @rpath/libvulkan.1.dylib.
# loader/cJSON.c is MIT (the notice is in cJSON.h); the other compiled files are Apache-2.0
# (REUSE.toml). It also installs loader/vulkan.framework, which nothing uses. SYSCONFDIR=/etc: the
# loader would otherwise search <prefix>/etc of the build machine (CMAKE_INSTALL_FULL_SYSCONFDIR).
dvv_third_party(Vulkan-Loader
    VERSION 1.4.365
    URL https://github.com/KhronosGroup/Vulkan-Loader/archive/refs/tags/v1.4.365.tar.gz
    SHA256 df0358f57c1936e4abd262a7327ba1f80ffb424dbbdcbcb01bb9288511f31eef
    SPDX "Apache-2.0 AND MIT"
    LINKAGE runtime
    SHIPPED
    LICENSE_FILES LICENSE.txt loader/cJSON.h
    ONLY_ON Darwin
    DEPENDS Vulkan-Headers
    CMAKE_ARGS -DBUILD_TESTS=OFF -DUPDATE_DEPS=OFF -DBUILD_WERROR=OFF -DSYSCONFDIR=/etc)

# KosmicKrisp (spec U-MAC2), Mesa's Vulkan driver on Metal, from the LunarG Vulkan SDK for macOS
# (the zip holds the SDK's installer application). The post-install step runs the installer into
# the build tree and copies the driver lib/libvulkan_kosmickrisp.dylib, its manifest
# share/vulkan/icd.d/libkosmickrisp_icd.json (library_path ../../../lib/<driver>),
# bin/vulkaninfo and the validation layer (entry Vulkan-ValidationLayers); the SDK's MoltenVK is
# never installed. The SDK has no licence text of its own components; Licenses/LICENSE.txt
# (LunarG's statement) is copied from the installed SDK; the MIT text and the copyright notices
# from Mesa (the commit VERSIONS.txt names) are supplements below.
# The expression lists everything compiled into the driver: Mesa (MIT), Berkeley SoftFloat
# (BSD-3-Clause), xxHash (BSD-2-Clause), the non-endorsement clause of Mesa's util/hash_table.c
# and set.c (X11) and BLAKE3 (its upstream choice of licences).
dvv_third_party(kosmickrisp
    VERSION 1.4.363.1
    URL https://sdk.lunarg.com/sdk/download/1.4.363.1/mac/vulkan_sdk.zip
    SHA256 a65c707cf0a32bf8c2ca6b9af1985b7af61dbadfc19b352dae51a323f3a547a6
    SPDX "MIT AND BSD-3-Clause AND BSD-2-Clause AND X11 AND \
(CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception)"
    LINKAGE runtime
    SHIPPED
    LICENSE_FILES Licenses/LICENSE.txt
    ONLY_ON Darwin
    PREBUILT
    POST_INSTALL post-install/kosmickrisp.cmake)

# vulkaninfo from the same SDK (Vulkan-Tools), a test tool for tools/check-vulkan-device.cmake,
# never shipped. It shares kosmickrisp's archive, whose post-install step installs it; its licence
# text from Vulkan-Tools (the commit VERSIONS.txt names) is a supplement below. It opens the loader
# as libvulkan.dylib by its bare name, so it runs with DYLD_LIBRARY_PATH=<prefix>/lib.
dvv_third_party(vulkaninfo
    VERSION 1.4.363.1
    URL https://sdk.lunarg.com/sdk/download/1.4.363.1/mac/vulkan_sdk.zip
    SHA256 a65c707cf0a32bf8c2ca6b9af1985b7af61dbadfc19b352dae51a323f3a547a6
    SPDX Apache-2.0
    LINKAGE tool
    LICENSE_FILES Licenses/LICENSE.txt
    ONLY_ON Darwin
    DEPENDS kosmickrisp
    PREBUILT)

dvv_licence_supplement(kosmickrisp
    FILE mesa/licenses/MIT
    COMPONENT Mesa
    VERSION 269a955c89
    URL https://gitlab.freedesktop.org/aitor/mesa/-/raw/269a955c898df283fc36f4827643769068cf3d29/licenses/MIT
    SHA256 323c587d0ccf10e376f8bf9a7f31fb4ca6078105194b42e0b1e0ee2bc9bde71f)
# MIT needs the copyright notices as well: collected from the sources at that commit (the file
# says how), with the unchanged notices of the files under other terms compiled into the driver.
# COPYRIGHTS.txt is derived from the sources at the pinned Mesa commit and must be regenerated
# (procedure in its header: grep of the copyright lines, nm of the shipped dylib for Part 2)
# whenever the KosmicKrisp pin changes.
dvv_licence_supplement(kosmickrisp
    FILE mesa/COPYRIGHTS.txt
    COMPONENT Mesa
    VERSION 269a955c89
    URL https://gitlab.freedesktop.org/aitor/mesa/-/tree/269a955c898df283fc36f4827643769068cf3d29
    SHA256 8da71d48d56554e78cf6053b35045d3febe7dec049a4c60fb046bbfe66e56e5e)
dvv_licence_supplement(vulkaninfo
    FILE vulkan-tools/LICENSE.txt
    COMPONENT Vulkan-Tools
    VERSION 6fe2055cf2
    URL https://raw.githubusercontent.com/KhronosGroup/Vulkan-Tools/6fe2055cf2fa921d52a4c6a31528cfc279a6977f/LICENSE.txt
    SHA256 cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30)

# Vulkan validation layer (spec §5, §12): loaded by the Vulkan loader in Debug builds and tests
# only, never shipped. LunarG's prebuilt layer from the Vulkan SDK 1.4.363.1 (U-CI1), not a source
# build: the source build and its SPIRV-Tools took most of a cold CI prefix. The SDK pins layer
# commit 317cff060893 with SPIRV-Tools ef96ed763b43 and SPIRV-Headers 496543121ce6 (its
# VERSIONS.txt); the last two and Vulkan-Utility-Libraries are linked into the layer, bundled in
# its source are parallel_hashmap (Apache-2.0), xxhash.h (BSD-2-Clause), inplace_function.h
# (BSL-1.0) and VMA (MIT). The Windows build also embeds mimalloc (MIT). Linux: the SDK tarball (one
# top folder 1.4.363.1, dropped on extraction); Windows: the SDK installer, whose first payload
# segment (Bin/, the top folder dropped) CMake's libarchive reads; the installer is never run. The
# post-install step installs only the layer and its manifest and removes the rest of the SDK. The
# archives hold no licence text of the layer: Linux has LunarG's statement LICENSE.txt, Windows
# nothing (its post-install step keeps the layer's LICENSE.txt supplement); the texts are the
# supplements below.
dvv_third_party(Vulkan-ValidationLayers
    VERSION 1.4.363.1
    URL https://sdk.lunarg.com/sdk/download/1.4.363.1/linux/vulkan_sdk.tar.xz
    SHA256 b7867d8ca658563813af666f34b93db87f1b1c7d9d69d97e924c210c7ba33eb8
    SPDX "Apache-2.0 AND BSD-2-Clause AND BSL-1.0 AND MIT"
    LINKAGE runtime
    LICENSE_FILES LICENSE.txt
    ONLY_ON Linux
    PREBUILT
    POST_INSTALL post-install/Vulkan-ValidationLayers.cmake)

dvv_third_party(Vulkan-ValidationLayers
    VERSION 1.4.363.1
    URL https://sdk.lunarg.com/sdk/download/1.4.363.1/windows/vulkan_sdk.exe
    SHA256 c02932bd9a968b22d404536108adaacac908c081cd6b0113f5bfefc523dd0a6a
    SPDX "Apache-2.0 AND BSD-2-Clause AND BSL-1.0 AND MIT"
    LINKAGE runtime
    LICENSE_FILES vulkan-validationlayers/LICENSE.txt
    ONLY_ON Windows
    PREBUILT
    POST_INSTALL post-install/Vulkan-ValidationLayers.cmake)

# macOS: the layer of the SDK kosmickrisp installs; kosmickrisp's post-install step copies it.
dvv_third_party(Vulkan-ValidationLayers
    VERSION 1.4.363.1
    URL https://sdk.lunarg.com/sdk/download/1.4.363.1/mac/vulkan_sdk.zip
    SHA256 a65c707cf0a32bf8c2ca6b9af1985b7af61dbadfc19b352dae51a323f3a547a6
    SPDX "Apache-2.0 AND BSD-2-Clause AND BSL-1.0 AND MIT"
    LINKAGE runtime
    LICENSE_FILES Licenses/LICENSE.txt
    ONLY_ON Darwin
    DEPENDS kosmickrisp
    PREBUILT)

# The layer's licence texts from the commits the SDK names. On Windows LICENSE.txt is the entry's
# licence file (kept by the post-install step), so it is not attached a second time there.
dvv_licence_supplement(Vulkan-ValidationLayers
    FILE vulkan-validationlayers/LICENSE.txt
    COMPONENT Vulkan-ValidationLayers
    VERSION 317cff0608
    URL https://raw.githubusercontent.com/KhronosGroup/Vulkan-ValidationLayers/317cff060893783f96d4174f50491e6374eb3714/LICENSE.txt
    SHA256 db3010170b904cb7212ef6abd2336f316bf735060eeeca23f1a737f459cc73e4
    PLATFORMS Linux Darwin)
dvv_licence_supplement(Vulkan-ValidationLayers
    FILE vulkan-validationlayers/LICENSES/Apache-2.0.txt
    COMPONENT Vulkan-ValidationLayers
    VERSION 317cff0608
    URL https://raw.githubusercontent.com/KhronosGroup/Vulkan-ValidationLayers/317cff060893783f96d4174f50491e6374eb3714/LICENSES/Apache-2.0.txt
    SHA256 074e6e32c86a4c0ef8b3ed25b721ca23aca83df277cd88106ef7177c354615ff)
dvv_licence_supplement(Vulkan-ValidationLayers
    FILE vulkan-validationlayers/LICENSES/BSD-2-Clause.txt
    COMPONENT Vulkan-ValidationLayers
    VERSION 317cff0608
    URL https://raw.githubusercontent.com/KhronosGroup/Vulkan-ValidationLayers/317cff060893783f96d4174f50491e6374eb3714/LICENSES/BSD-2-Clause.txt
    SHA256 017b5ee48f680e82cba79141c7895a1f02b856df2512225f5c427fe36765ef0b)
dvv_licence_supplement(Vulkan-ValidationLayers
    FILE vulkan-validationlayers/LICENSES/BSL-1.0.txt
    COMPONENT Vulkan-ValidationLayers
    VERSION 317cff0608
    URL https://raw.githubusercontent.com/KhronosGroup/Vulkan-ValidationLayers/317cff060893783f96d4174f50491e6374eb3714/LICENSES/BSL-1.0.txt
    SHA256 84c6ef3ea9e3254a54d0acf5d3e0c61ae011b8fef7dd6940591cf060e6380a8f)
dvv_licence_supplement(Vulkan-ValidationLayers
    FILE vulkan-validationlayers/LICENSES/LLVM-exception.txt
    COMPONENT Vulkan-ValidationLayers
    VERSION 317cff0608
    URL https://raw.githubusercontent.com/KhronosGroup/Vulkan-ValidationLayers/317cff060893783f96d4174f50491e6374eb3714/LICENSES/LLVM-exception.txt
    SHA256 e34c58338bd89d43e709e226610d8f32b3e3c47f4ad9a99a8dc1d4ac7842488e)
dvv_licence_supplement(Vulkan-ValidationLayers
    FILE vulkan-validationlayers/LICENSES/MIT.txt
    COMPONENT Vulkan-ValidationLayers
    VERSION 317cff0608
    URL https://raw.githubusercontent.com/KhronosGroup/Vulkan-ValidationLayers/317cff060893783f96d4174f50491e6374eb3714/LICENSES/MIT.txt
    SHA256 b05785f9f18e6716bab63424b11454513b9943a222595b70411009202fc592b5)
dvv_licence_supplement(Vulkan-ValidationLayers
    FILE spirv-tools/LICENSE
    COMPONENT SPIRV-Tools
    VERSION ef96ed763b
    URL https://raw.githubusercontent.com/KhronosGroup/SPIRV-Tools/ef96ed763b43b59b33b31b362f09a02b729fa1c9/LICENSE
    SHA256 cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30)
dvv_licence_supplement(Vulkan-ValidationLayers
    FILE spirv-headers/LICENSE
    COMPONENT SPIRV-Headers
    VERSION 496543121c
    URL https://raw.githubusercontent.com/KhronosGroup/SPIRV-Headers/496543121ce6419f23d6fa5d7194ba66c36212d2/LICENSE
    SHA256 ea43b1de38a6f90c488800d66dec1ed671e68cda530266bc96951fb5b6307613)
# mimalloc: the version the layer's scripts/known_good.json pins for its Windows build (the
# Windows layer's debug information names mimalloc 3.5); the Linux and macOS layers contain none.
dvv_licence_supplement(Vulkan-ValidationLayers
    FILE mimalloc/LICENSE
    COMPONENT mimalloc
    VERSION 3.5.3
    URL https://raw.githubusercontent.com/microsoft/mimalloc/d4881d338125e1cb7c47ba4cfb398d6f7c0c8d45/LICENSE
    SHA256 82ade5d7d9b029044b5fbbc326207fc47c2d44ee4dd71e8a559c36d728217de9
    PLATFORMS Windows)

# wxWidgets (spec §2, §10.2), static. MSVC builds Debug and Release (Debug builds of rawreel link the
# /MDd libraries); Debug objects carry their debug information (/Z7, no separate PDB, so a Debug
# consumer link shows no LNK4099), Release objects none. Regex, XML, image formats other than PNG,
# web, media and GL parts are off: not needed through v1, and they keep the licence small. wxcore
# always contains a JPEG-derived colour quantizer (IJG), an ImageMagick/libXpm-derived XPM decoder
# (X11) and Unicode CLDR-derived language tables (Unicode-DFS-2016); nanosvg is bundled (Zlib).
# wxUSE_APPLE_IEEE is off: its extended.c has a licence without an SPDX id.
# Every wx entry installs into its own prefix <prefix>-wx (SEPARATE_PREFIX), which CI caches apart
# and the superbuild skips while its marker matches (deps/CMakeLists.txt).
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
    SEPARATE_PREFIX wx
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
    SEPARATE_PREFIX wx
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

# macOS: Release only (as Linux: the Ninja superbuild builds one configuration), Cocoa, the bundled
# zlib and libpng (as Windows; nothing from Homebrew), the Windows options without the MSVC ones.
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
    ONLY_ON Darwin
    SEPARATE_PREFIX wx
    CMAKE_ARGS -DwxBUILD_TOOLKIT=osx_cocoa -DwxBUILD_SHARED=OFF
               -DwxBUILD_SAMPLES=OFF -DwxBUILD_TESTS=OFF -DwxBUILD_DEMOS=OFF -DwxBUILD_INSTALL=ON
               -DwxBUILD_CXX_STANDARD=17
               -DwxUSE_ZLIB=builtin -DwxUSE_LIBPNG=builtin -DwxUSE_LIBJPEG=OFF -DwxUSE_LIBTIFF=OFF
               -DwxUSE_LIBWEBP=OFF -DwxUSE_LUNASVG=OFF -DwxUSE_NANOSVG=builtin -DwxUSE_REGEX=OFF
               -DwxUSE_EXPAT=OFF -DwxUSE_XML=OFF -DwxUSE_XRC=OFF -DwxUSE_RICHTEXT=OFF
               -DwxUSE_STC=OFF -DwxUSE_WEBVIEW=OFF -DwxUSE_MEDIACTRL=OFF -DwxUSE_OPENGL=OFF
               -DwxUSE_WEBREQUEST=OFF -DwxUSE_SECRETSTORE=OFF -DwxUSE_APPLE_IEEE=OFF)

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

# macOS (spec U-MAC10): v1.0.1, whose shared libraries carry the rpath @loader_path (Windows and
# Linux stay on v1.0.0). The archive has no libvpl, AMF or ffnvcodec.
dvv_third_party(custom_ffmpeg
    VERSION 1.0.1
    URL https://github.com/BarabashkaD/custom_ffmpeg/releases/download/v1.0.1/custom_ffmpeg-1.0.1-macos-arm64-shared-lgpl.tar.xz
    SHA256 a852d6c99da521992dc74c369c65af74a382679a982c54f06da9918d8e05a910
    SPDX "LGPL-2.1-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND BSD-2-Clause \
AND BSD-3-Clause-Clear AND MIT AND Zlib"
    LINKAGE runtime
    LICENSE_FILES macos-arm64/shared/lgpl/share/licenses/*/*
    ONLY_ON Darwin
    PREBUILT
    ${custom_ffmpeg_shipped})

# Licence texts that custom_ffmpeg's LICENSES.md names but its archives do not contain, taken
# unchanged from the commits its build-info.txt names (SVT-AV1 4.2.0 @ 9292ec8e3 = tag v4.2.0,
# libvpl 2.17 @ d77f9195c = tag v2.17.0). SVT-AV1's encoder library compiles in fastfeat
# (BSD-3-Clause) and safestringlib (MIT). libvpl's third-party-programs.txt covers its googletest
# and Open Model Zoo code, which are in its tests and examples, not in the dispatcher, so the SPDX
# expression above does not change. libvpl is in the Windows and Linux builds only (LICENSES.md),
# so its supplement is not attached on macOS. The macOS 1.0.1 build has the same SVT-AV1 commit.
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
    SHA256 e3c92992b1df02b467ac086d7d3730f4c1fc2c2a1f2c520657c4c9f2085305a3
    PLATFORMS Windows Linux)

# LAME 3.100 source tarball (M4 design D27): LAME is inside custom_ffmpeg's libraries; the tarball is
# pinned only for rawreel's third-party sources archive and is never downloaded by the superbuild,
# built or shipped in a package.
dvv_source_pin(lame
    VERSION 3.100
    URL https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz
    SHA256 ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e)
