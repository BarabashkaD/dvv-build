# dvv-build

The shared build infrastructure of the `dvv` libraries and of the applications that use them: CMake
presets, the shared compiler options (`DvvCompilerOptions.cmake`), the dependency rules
(`dvv-deps.txt`, `DvvDeps.cmake`), the bootstrap scripts, the
third-party superbuild with its licence gate, the per-OS file selection (`DvvOsSources.cmake`), the
tools (`fetch-deps`, `check-pins`, privacy lint, `os-blocks`, `tidy-files`, sanity cycles) and the
reusable CI workflow. dvv-build is versioned (`VERSION`) and tagged like the libraries.

## Repositories

| Repository | Content |
|---|---|
| dvv-build | presets, dependency rules, bootstrap, third-party superbuild and licence gate, tools, CI |
| dvv-base | errors, tasks and executors, logger, lifetime registry and leak check, JSON, URIs, paths, UTF-8 and ASCII text |
| dvv-registry | component registry, capabilities, modules and their options |
| dvv-platform | window handles, dynamic libraries, file reading and writing, crash handler |
| dvv-gpu | Vulkan 1.4 core: devices, buffers and images, submission, Slang shaders, compute pipelines, presentation |
| dvv-media | pixel-format catalogue, custom JSON formats, frames and the frame store, synthetic, raw and Y4M sources |
| dvv-components | `dvv_add_component()`, the FFmpeg run-time binding, the `ffmpeg` and `lavfi` sources |

`repos.txt` lists the six libraries in dependency order. rawreel, the video viewer, is an
application that uses all of them as submodules.

## The dvv root

Every build happens in a *dvv root*: the folder that holds `dvv-build`. Build output stays outside
the repositories:

```text
<root>/
  dvv-build/                  this repository
  dvv-<x>/ ...                the dvv libraries (a library alone: the library and its dependencies)
  _third_party/<toolchain>/   installed third-party dependencies (created by bootstrap)
  _third_party/<toolchain>-wx/  wxWidgets, apart so that CI caches it on its own (by bootstrap)
  _build/<repo>/<preset>/     build trees (created by the CMake presets)
  _build/tp-<toolchain>/      the superbuild tree (created by bootstrap)
```

- **Library** (lib layout): the root is the folder holding the library; `dvv-build` and the
  dependencies are its siblings. Its `CMakePresets.json` includes `../dvv-build/cmake/DvvPresets.json`.
- **Application** (app layout): the root is `<app>/libs`, which holds `dvv-build` and every library
  as submodules, one copy each (relative URLs `../dvv-<x>`, no `.git` suffix). Its `CMakePresets.json`
  includes `libs/dvv-build/cmake/DvvAppPresets.json`. `check-pins` expects every submodule at
  `libs/dvv-<name>`.

Windows paths stay within 259 characters only when the dvv root is at most 68 characters long (an
application's clone path: at most 63, the root being `<app>/libs`; the builds go up to 191
characters deep below the root, `DVV_PATH_DEPTH` in `bootstrap.ps1`, measured for an application
folder of 7 characters such as `rawreel`); bootstrap checks it.

## Dependencies: `dvv-deps.txt`

Each library and application lists its dvv dependencies in `dvv-deps.txt`, in dependency order:

```text
# dvv dependencies: <repository> <minimum version>, dependency order (read by dvv-build).
dvv-build 0.6.0
dvv-base 0.6.0
dvv-platform 0.4.0
```

- `dvv-build <version>` appears exactly once, anywhere in the file; `dvv-<x> <version>` once per
  dependency; a line that starts with `#` is a comment. A branch may add ` @<commit>` to a
  dependency's line (see "Changing a library"). `cmake/DvvDepsFile.cmake` is the one reader (CI reads the
  `dvv-build` line with bash by the same rules before dvv-build is checked out).
- `dvv_dependencies()` (`cmake/DvvDeps.cmake`) checks at every configure that each dependency is
  present in the root and meets its minimum, and makes it available; the dependencies build without
  their tests unless `DVV_TEST_DEPENDENCIES` is set.
- **Transitive minimums:** a repository's minimum for X is on the same 0.minor as, and at least,
  the minimum for X of each of its dvv dependencies, and it lists every dvv library its
  dependencies list. `fetch-deps` checks this and names the line to raise or the release to use.

## Versions

- Semantic versions, `v<major>.<minor>.<patch>` tags. Compatible means the same 0.minor and at
  least the minimum version: 0.6.2 meets the minimum 0.6.0, 0.7.0 does not. The package version
  files use `SameMinorVersion`.
- A replaced or unused API is removed in the next 0.x minor, with no deprecation period; that
  release's CHANGELOG names each removal and its replacement.
- A pushed tag is never moved; a fix is a new patch release.
- Each repository's `CHANGELOG.md` is its release notes; the libraries and dvv-build have no
  GitHub Releases.

## Names

| suffix | the one role | examples that fit (snapshot) |
|---|---|---|
| Options | inputs of a create/open/load call, given once; defaults inside the struct | SessionOptions, ContextOptions, FfmpegLoadOptions; GpuInstanceOptions |
| Config | a section of a persisted, user-editable file (applications only) | rawreel IoConfig, LogConfig |
| Params | values fed to one computation or pass, possibly per frame | ColourParams (the resolved colour for the maths), CompositeParams; PresentFrameParams |
| Desc | an immutable description used to create or interpret a resource, frame or layout ("Descriptor" only for Vulkan descriptor sets) | FrameDesc, PlaneDesc, BufferDesc; PixelFormatDesc |
| Info | read-only facts about an existing thing, reported at run time or declared in a static catalog | GpuInfo, SourceInfo, ComponentInfo, rawreel CommandInfo; detail::LibraryInfo, ContainerInfo |
| Request | an ask that another part answers or resolves later; never the resolved answer | SourceRequest (an asynchronous open), ViewRequest (resolved by the renderer) |
| Choice | a selection made among alternatives, by the user or by a resolver | rawreel FormatChoice, ColourChoice, StandardChoice; ValidationChoice |
| Spec | a value that selects or identifies (a key part, a query as written) | ViewSpec, ColourSpec |
| Hint | advisory knowledge a resolver may use or override (Guess: a provider's own inference, handed to its own open()) | FormatHint, FileHint, Bt601Hint; FormatGuess |
| Context | the environment handed to one call or one dialog (executors, store, what the callee may use); the GPU `ExecutionContext` is the glossary's exception | OpenContext, ProduceContext, ConvertContext, rawreel FormatDialogContext |
| Entry | one element of a list or table that its container owns | ProviderEntry, dvv-base SinkEntry, rawreel LogEntry, ZoomMenuEntry; LibraryEntry |
| Record | one item a store writes or updates in place | LogRecord, TypeRecord |
| Status / Stats | Status = a snapshot of state or availability handed out; Stats = counters | SessionStatus, FfmpegStatus, ComponentStatus, rawreel VulkanStatus; TierStats, TypeStats |
| State | mutable state an object keeps for itself (not handed out as a snapshot) | rawreel DisplayState, LoaderState, the GUI `*State` types |
| Report | a value assembled to be printed | rawreel VersionReport, BenchReport |
| Settings, Facts | not used (prose says "Options for" an Options struct, not "Settings for") | - |

A type named after a user-facing file format keeps the format's name, whatever its suffix. `ClipDescription` is the parsed "clip description" sidecar that the rawreel README documents.

Glossary:
- registry: a set of registered entries looked up by id. Two types fit: `ComponentRegistry` (plug-ins by id) and `LifetimeRegistry` (managed objects registered at creation, by `ObjectId`). The Vulkan instance is `GpuInstance`.
- component: a registered plug-in (dvv-registry, dvv-components) or a pixel channel (dvv-media `ComponentKind`, `ComponentDesc`). Both are domain terms, always qualified by namespace.
- context: the per-call environment of the Context row. `gpu::ExecutionContext` is the GPU device context, a domain term of GPU APIs, and a `ConvertContext` holds one as `gpu`.
- key: a lookup key (`FrameKey`). `CreationKey` is the C++ passkey idiom, a domain term of the language.
- module option: a named text value a module receives at load (dvv-registry `dvv::ModuleValues`, option name to text). It is not the `Params` suffix.
- descriptor: only a Vulkan descriptor set. A pixel format is a `PixelFormatDesc`, returned by `formatDesc()`, and the registry's static node is a "registration node".
- lease: a scoped, move-only access right released by its owner (dvv-media).
- log record and log entry: a dvv-base `LogRecord` is one message as written. A rawreel `LogEntry` is the log store's own copy of one, with a sequence number (Record and Entry rows).
- window system and surface: a window system is named by the window system (Win32, Xlib, Cocoa), and a surface by its graphics API (Metal).
- OS words: a portable mode is named by what it does on every OS. An OS mechanism's name is used only where only that OS has it.
- `<name>_<backend>` file pairs: one name, one suffix per OS or backend (viewport_window.h with `viewport_<os>`).

Misfits (names that break a rule and are kept): Metal/Cocoa; `PlayerConfig`, `SessionStatus::inflight`; the loader's `LibraryInfo`.

## Per-OS code

Per-OS code lives in files with a suffix: `<stem>_<suffix>.cpp`, `.mm` or `.h`. The suffix names the
OS, the window system or the toolkit backend. `cmake/DvvOsSources.cmake` holds the three lists, one
per platform, and `dvv_os_sources` selects the files of the platform being built:

```cmake
include(DvvOsSources)
dvv_os_sources(<target> [OPTIONAL] <stem>...)
```

- Windows (`WIN32`): `win32`, `msw`.
- macOS (`APPLE`): `posix`, `macos`, `metal`, `cocoa`.
- Other (Linux and the rest): `posix`, `linux`, `xlib`, `gtk`.
- `stub` is the fallback, used when the platform has no file for a stem.

A platform builds every file of its list that exists for the stem (`posix` and `macos` layer on
macOS). A stem with no file and no stub, and a call without a stem, fail at configure time;
`OPTIONAL` allows a stem that only some platforms have. `.mm` files are compiled with `-fobjc-arc`.
The queries `dvv_os_all_suffixes`, `dvv_os_suffixes_for` and `dvv_os_suffixes` return the lists.

A shared file (no per-OS suffix) may hold an OS `#if` block of at most 5 lines, with a comment and
the same types on every branch. A block of only includes, pragmas and `#error` lines is free at any
length; a `#define` is code. Each layer has one selector vocabulary: CMake selects by `WIN32`,
`APPLE` or other, the gui C++ by the wxWidgets toolkit macro, all other C++ by the OS macro.

The gate counts a condition as an OS group when it names `_WIN32`, `__APPLE__`, `__linux__`, `TARGET_OS_*`, `__WXMSW__`, `__WXOSX__*` or `__WXGTK__`; other conditions (for example `_MSC_VER`, `__unix__`) are not OS groups.

`tools/os-blocks.cmake` is the gate (the lint step "OS blocks"). It checks only the length; the
comment, the same types and the selector vocabulary are review items. In the tracked `*.h`, `*.cpp`
and `*.mm` files outside `tests/` that have no per-OS suffix, it counts the OS `#if` blocks over 5
lines that hold code, and compares the counts with `os-blocks.txt` in the repository (one row per
file with its block count). The baseline may only shrink; a missing file is an empty baseline.
It skips character literals and raw string literals (any prefix, across lines) when it looks for code
lines, and fails when git quotes a tracked path (the message says to rename it).
`cmake -DREPO=<repo dir> -DMODE=write -P dvv-build/tools/os-blocks.cmake` rewrites it.

Windows-only and macOS-only files are not tidied, because Tidy runs on Linux.
`tools/tidy-files.cmake` builds Tidy's file list from the compile database of `ninja-clang`, so a
repository's preset keeps `CMAKE_EXPORT_COMPILE_COMMANDS` on.
`tidy-files` fails when git quotes a tracked path, and when a tracked path or a compile-database path
contains `;`; a path with `[` or `]` is listed like any other.

## Prerequisites

- Windows: Visual Studio 2026 (C++ workload), PowerShell 7, Git, Python 3; for the GPU tests a
  driver with Vulkan 1.4. The tools (CMake 4.3, Ninja, clang-format and clang-tidy 19) are
  installed with pip from dvv-build's `tools/requirements.txt` right after cloning it (see below).
  Configuring the third-party superbuild needs CMake 4.3.2 or newer on Windows (it reads LunarG's
  Vulkan SDK installer); the pinned CMake qualifies.
- Linux (Ubuntu 24.04, also in WSL 2): Clang 19 with libstdc++ 14 is the only supported toolchain
  (no GCC, no libc++; `DvvCompilerOptions.cmake` checks it). Git, Python 3 and

  ```sh
  sudo apt install clang-19 libclang-rt-19-dev libstdc++-14-dev libgtk-3-dev pkgconf libx11-dev \
    libxcb1-dev libxrandr-dev libwayland-dev zlib1g-dev libpng-dev mesa-vulkan-drivers libvulkan1
  ```

  `bootstrap.sh` checks these first. The GPU tests use lavapipe, Mesa's CPU Vulkan driver. Under
  WSL 2 the GUI and display tests use WSLg's X display; `xvfb xauth` add a virtual display.
  Ubuntu's Python refuses a system-wide `pip install` (PEP 668) and apt's CMake is too old, so
  install the tools (with the pip line below, after cloning dvv-build) into a virtual environment
  and activate it in every shell that builds:

  ```sh
  sudo apt install python3-venv
  python3 -m venv ~/.venvs/dvv
  . ~/.venvs/dvv/bin/activate
  ```
- macOS 27 or newer on Apple Silicon: Xcode 27 (its Apple Clang and libc++ are the only supported
  toolchain; `DvvCompilerOptions.cmake` checks it), Homebrew and Git. `brew install ninja` and a
  Python 3 for the tools. The GPU tests run on KosmicKrisp (Mesa's Vulkan driver on Metal), which
  bootstrap installs into the prefix together with the Vulkan loader, `vulkaninfo` and the
  validation layer; no Vulkan SDK install is needed. A build tree can run its tests on another
  driver with `-DDVV_TEST_VK_DRIVER_FILES=<ICD manifest>` (CI uses it for lavapipe). The tools (CMake 4, clang-format and
  clang-tidy 19) come from pip as on Linux, into a virtual environment that is active in every
  shell that builds.

## Building a library alone

`<base>` is the account holding the dvv repositories, e.g. `https://github.com/<owner>`.

```powershell
git clone <base>/dvv-gpu
git clone --branch v0.6.0 <base>/dvv-build      # the dvv-build line of dvv-gpu/dvv-deps.txt
git -C dvv-build config user.name <GitHub handle>
git -C dvv-build config user.email <GitHub noreply e-mail>
python -m pip install -r dvv-build/tools/requirements.txt
cmake -DREPO=dvv-gpu -P dvv-build/tools/fetch-deps.cmake
./dvv-build/bootstrap.ps1
cd dvv-gpu
cmake --workflow --preset vs2026                 # or vs2026-asan (AddressSanitizer)
```

On Linux: `./dvv-build/bootstrap.sh`, then `cmake --workflow --preset ninja-clang` (it also
builds and tests Release; also `ninja-clang-asan` and `ninja-clang-tsan`).

On macOS: `./dvv-build/bootstrap.sh` (the toolchain defaults to `appleclang`, prefix
`<root>/_third_party/appleclang`), then `cmake --workflow --preset ninja-macos` (it also builds and
tests Release; also `ninja-macos-asan`; there is no ThreadSanitizer preset).

- `fetch-deps` clones each missing dependency next to the library at tag `v<minimum>` (depth 1)
  from `DVV_GIT_BASE_URL` (`-D` or environment) or else from the library's origin without its last
  path part. An existing dependency is checked, never updated. `REPO` is the library's folder name
  in the root, not a path.
- `bootstrap` gives dvv-build, the libraries next to it and the app (when the root is `<app>/libs`)
  the shared git hooks and **dvv-build's repository-local commit identity** (only that one, never
  the global one, and only to repositories without their own), so set it in dvv-build first. It
  then builds the third-party dependencies into `<root>/_third_party/<toolchain>` and wxWidgets into
  `<root>/_third_party/<toolchain>-wx` (the first run takes several minutes; later runs say "up to
  date" while the prefix stamp and the wxWidgets marker `dvv-inputs.sha256` are current; the
  superbuild skips wxWidgets while its marker matches and removes the root-level
  `lib/cmake/wxWidgets*` package that dvv-build 0.2.0 installed). `-Toolchain msvc|clang`, `-Force`
  removes the build tree and the wxWidgets prefix and rebuilds (when upgrading a 0.2.0 root,
  delete `_third_party/<toolchain>` once first). The downloaded archives stay in
  `<root>/_build/downloads` and are used again while their SHA256 matches the pin; a failed build
  is run again up to three times in all, after 1 and 5 minutes (download servers answer 503 or 504
  at times),
  `-BundleFfmpeg OFF` builds application packages without FFmpeg (bash: `--toolchain`, `--force`,
  `--bundle-ffmpeg`; `--toolchain` is `clang` or `appleclang`, the default on macOS).
- The Vulkan validation layer is LunarG's prebuilt one from the Vulkan SDK 1.4.363.1 on all three
  systems. The presets' `CMAKE_PREFIX_PATH` holds both folders,
  `<root>/_third_party/<toolchain>;<root>/_third_party/<toolchain>-wx`; a consumer that sets its own
  `CMAKE_PREFIX_PATH` must add the `-wx` sibling.
- custom_ffmpeg's LGPL shared release is installed into `_third_party/<toolchain>/custom_ffmpeg`.
  FFmpeg is never linked; CMake projects find it with `find_package(dvv_ffmpeg_sdk CONFIG REQUIRED)`,
  which sets `DVV_FFMPEG_PROGRAM`, `DVV_FFMPEG_RUNTIME_DIR` and the target `dvv::ffmpeg_headers`.
  The release data of custom_ffmpeg and LAME, `DVV_BUNDLE_FFMPEG` and the shipped entries are in
  `_third_party/<toolchain>/dvv-third-party-state.cmake`.
  The prefix holds `THIRD_PARTY_NOTICES.txt` (what packages ship) and `THIRD_PARTY_NOTICES-all.txt`
  (every dependency, never shipped). Licence texts missing from custom_ffmpeg's archives are kept in
  `deps/licenses/custom_ffmpeg-supplement/`, pinned by SHA256 in `deps/versions.cmake`.

## Building an application

```powershell
git clone --recursive <base>/<app>
git -C <app>/libs/dvv-build config user.name <GitHub handle>
git -C <app>/libs/dvv-build config user.email <GitHub noreply e-mail>
python -m pip install -r <app>/libs/dvv-build/tools/requirements.txt
./<app>/libs/dvv-build/bootstrap.ps1
cd <app>
cmake --workflow --preset vs2026
```

The submodule commits are the pins; `dvv_dependencies()` checks every library's minimums against
them. `cmake -DREPO=. -DMODE=app -P libs/dvv-build/tools/check-pins.cmake` in `<app>` checks that
each pin is the commit of tag `v<its version>` on its origin, that the submodule URLs are relative
and that the workflows' `dvv-ci.yml@v<X>` is the pinned dvv-build version.

## Changing a library

Inside an application, `libs/dvv-<x>` is the library's own repository, detached at its tag:

1. `cd <app>/libs/dvv-<x>`, `git switch -c fix/<topic>`, edit. The presets build it with its
   siblings in `libs/` as its dependencies (at the app's pins).
2. Run its tests and the application's.
3. Raise `project(VERSION)` and add a `CHANGELOG.md` entry; commit, merge to main, tag `v<version>`,
   push main and the tag. Its CI must be green.
4. In the application: `git add libs/dvv-<x>` and commit `build: pin dvv-<x> <version>`. **A pin
   bump is merged only with a green run that includes the lib tests** (the application's CI runs
   them on every push). Raise the application's `dvv-deps.txt` minimum only when it needs the new
   version. A patch release may be pinned without touching the minimum. A new 0.minor needs the
   application's minimum raised to that line, and the minimum of every pinned library that depends
   on it raised to the same line. Each such library then needs a release of its own.

A dvv-build change follows the same flow, with the same rule for a new 0.minor. A library's
`dvv-build` line in `dvv-deps.txt` and the `@v<X>` of its `ci.yml` move together; `check-pins` (lib
mode) checks it: `cmake -DREPO=dvv-<x> -DMODE=lib -P dvv-build/tools/check-pins.cmake` in the dvv
root, where `REPO` is the path of the repository folder.

**Main depends on tags only.** On `main`, every `dvv-deps.txt` minimum and every application pin
is a released tag: `check-pins` fails on an application pin that is not the commit of tag
`v<version>` of that library (it asks the library's origin with `git ls-remote`, so it also works
in CI's shallow checkout without tags), and on any branch-only override (lib and app mode).

**Branch-only override (joint testing).** To test a library branch against an unreleased commit of
a dependency, add ` @<commit>` (the full 40-digit lowercase hash, pushed to the dependency's
origin) after the version on that dependency's line:

```text
dvv-base 0.6.0 @0123456789abcdef0123456789abcdef01234567
```

`fetch-deps` then fetches exactly that commit instead of tag `v<minimum>` and checks that its
version still meets the minimum; an existing folder must be checked out at that commit. The
`dvv-build` line takes no override: a library branch tests against an unreleased dvv-build by calling
`dvv-ci.yml@<dvv-build branch or commit>` instead (CI checks dvv-build out at the workflow's own
commit; `check-pins` fails the same way). Notes:

- The commit can only be one that is pushed to the dependency's origin.
- Configure (`DvvDeps`) uses the dependency's folder as it is, so in the side-by-side layout the
  local build follows the clone's current checkout; only `fetch-deps` checks the commit.
- An override in a dependency's own `dvv-deps.txt` must be repeated: `fetch-deps` fails until the
  library's line for that repository carries the same ` @<commit>`.
- An application does not use the override: it moves its `libs/<name>` submodule instead, and
  `check-pins` (app mode) rejects an override in the application's `dvv-deps.txt` and in a pinned
  library's `dvv-deps.txt`.

While an override is present, the lint job runs the privacy lint and clang-format as usual and fails
at its last step, `check-pins`, so the pull request cannot go green: tag the dependency, raise the
minimum and remove the override ("back on tags before merge").

## CI

`.github/workflows/dvv-ci.yml` is the reusable workflow (Windows MSVC, Linux Clang and macOS Apple Clang
builds with AddressSanitizer variants, Linux also ThreadSanitizer, a lint job and a clang-tidy job). On
Windows, Debug and Release run as separate jobs (`windows-msvc`, `windows-msvc-release`):

```yaml
concurrency:                      # newer PR pushes cancel older runs; a running main run finishes
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
jobs:
  ci:
    uses: <owner>/dvv-build/.github/workflows/dvv-ci.yml@v0.6.0   # = the dvv-build line
    with:
      repo: dvv-gpu
```

- Library (lib layout): reads the `dvv-build` line, checks out dvv-build at the commit of the called
  `dvv-ci.yml` (`job.workflow_sha`, which is tag `v<X>` for `@v<X>`; the line's tag where
  `job.workflow_sha` is absent), runs `fetch-deps` with `DVV_GIT_BASE_URL` = the caller's account,
  so the libraries' minimum versions are tested. Lint: privacy lint, OS blocks, clang-format (`*.h`, `*.cpp`, `*.mm`), then `check-pins`
  (lib mode); tidy: clang-tidy on the files of the Linux Clang compile database. A fork needs
  the dvv repositories under its own account. A fork of dvv-build sets `DVV_CI_IMAGE_OWNER` to pull
  the upstream image, or mirrors the image under its own account with the same digest. A fork PR that
  changes the image is published by a maintainer.
- Linux image: the Linux build jobs and tidy run in `ghcr.io/<owner>/dvv-build-ci`, pinned by digest in `dvv-ci.yml`.
  The image holds the packages of `ci-image/packages.txt` from a pinned Ubuntu snapshot, and the
  Python 3.13 build of setup-python with the tools of `tools/requirements.txt`. The image is public.
  The inputs of the image are the tracked files of `ci-image/`, `tools/requirements.txt`,
  `tools/ci-image-inputs.cmake` and the publish workflow `.github/workflows/ci-image.yml`.
  A changed input needs a new image (`ci-image.yml`) and its digest in `dvv-ci.yml`. Package versions
  tagged `inputs-*` are never deleted. Their steps use `$GITHUB_WORKSPACE` and `$RUNNER_TEMP`, not the
  `github.workspace` and `runner.temp` expressions. The lint job runs on the host (setup-python and
  the tools of `tools/requirements.txt` from PyPI): pulling the image took longer than the job.
- Application: `app: true` (submodules checked out recursively; `check-pins` in app mode), and
  `test-dependencies: true` to run every library's tests at the pins.
- dvv-build's own `ci.yml` runs the script tests on Windows and Linux (`tools`) and the reusable
  workflow on dvv-build itself (`self`).
- macOS GPU tests: the `macos` jobs run them on the prefix's KosmicKrisp when the runner's Metal
  device can run it. GitHub's `xcode-27` runners cannot, so `tools/select-vulkan-driver.cmake`
  installs Mesa's lavapipe from Homebrew's `mesa` bottle instead (CI only, never in the prefix or a
  package; unpinned; Linux CI's lavapipe comes from the CI image) and the tests run on it through
  `DVV_TEST_VK_DRIVER_FILES`, required and with synchronization validation as on Linux. The display
  tests run only on KosmicKrisp with a desktop session. A prefix without KosmicKrisp, a failed
  `brew install mesa` (three attempts) or a lavapipe without a Vulkan 1.4 device fails the job, and
  a check fails it when the loader loads any other driver or layer. A bad Homebrew bottle: set the
  repository variable `DVV_MACOS_SOFTWARE_GPU` to `off` (or `false`, `0`, `no`; Settings, Secrets and
  variables, Actions, Variables) and the GPU tests skip on macOS until a fix is released.

The third-party prefix comes from two caches per toolchain `<tc>`:

- wxWidgets, `<root>/_third_party/<tc>-wx`, keyed on the first 16 hex digits of its inputs marker
  (`tools/separate-prefix-hash.cmake`) and of a hash of the compiler version (Linux `clang-19
  --version`; Windows the Visual Studio build version and the newest MSVC tools folder; macOS the Xcode
  and SDK versions);
- the rest, `<root>/_third_party/<tc>`, keyed on `deps/**`, `cmake/DvvThirdParty.cmake` and
  `cmake/DvvSpdx.cmake` (the inputs of bootstrap's up-to-date stamp).

On Linux, the wxWidgets and prefix keys also end with the first 16 hex digits of the CI image's
environment hash.

A prime job per OS (`prime-windows`, `prime-linux`, `prime-macos`) looks both keys up without
downloading and stops when both exist; otherwise it restores what exists, bootstraps and saves what
was missing. Such a prime job also restores a third cache, the downloaded archives
(`<root>/_build/downloads`, keyed on the `URL` and `SHA256` lines of `deps/versions.cmake`, falling
back to an older entry): an archive is used only when its SHA256 matches the pin, so it downloads
only what the pins changed. The build jobs of that OS and the tidy job (after `prime-linux`) start
after it, restore the wxWidgets and prefix entries, never save, and take bootstrap's fast path. The
lint job waits for no prime job.

## Tests

The GPU tests (label `gpu`) need a Vulkan 1.4 device; without one they exit with 77 and CTest
reports them as skipped. CTest uses the validation layer that bootstrap installs into the prefix
(LunarG's prebuilt layer from the Vulkan SDK 1.4.363.1, not a source build), and every GPU test
fails on a validation message. Display tests (label `display`, and `gui` for application
self-tests) need a desktop. Environment settings:

| Variable | Values | Effect |
|---|---|---|
| `DVV_REQUIRE_GPU` | `1` | a missing device or display fails the tests instead of skipping them |
| `DVV_VK_VALIDATION` | `off`, `on`, `sync` | validation mode; default `on` in Debug when the layer is present, else `off` |
| `DVV_VK_VALIDATION_REQUIRED` | `0`, `1` | `1`: a missing validation layer is an error |
| `DVV_REQUIRE_FFMPEG` | `1` | a missing FFmpeg fails the FFmpeg tests (label `ffmpeg`) instead of skipping them |
| `DVV_TEST_DEPENDENCIES` | empty or `ON` | also build and run the tests of the dvv dependencies |

Test tiers (Windows, PowerShell 7; `<root>` is the folder that holds the changed checkout):

| Tier | When | Runs | Command |
|---|---|---|---|
| T0 | after each change | the changed repository: `sanity`, or only the relevant tests | `pwsh <root>/dvv-build/tools/sanity.ps1 -Repo <repo>`; for the relevant tests `ctest --preset vs2026 -R <regex>` in a built tree, or `pwsh <root>/dvv-build/tools/sanity.ps1 -Repo <repo> -Tests <regex>` (builds first) |
| T1 | before each commit | `small` (all but label `package`) in the changed repository and the application, `sanity` in the repositories between them; clang-format on the changed files; the privacy lint | `pwsh <root>/dvv-build/tools/sanity.ps1 -Repo <repo> -Downstream -Small`, then `cmake "-DREPO=<repo>" -DMODE=commits -P <root>/dvv-build/tools/privacy-lint.cmake` |
| T2 | when a task is mostly done, and at milestone ends | the full workflows: Windows, Linux with sanitizers, clang-tidy; a package dry run for packaging or release changes | `cmake --workflow --preset vs2026` (Debug and Release) and `vs2026-asan`; on Linux `ninja-clang`, `ninja-clang-asan`, `ninja-clang-tsan` |
| CI | every push and pull request | the prime jobs, the full matrix and the lint and tidy jobs | `.github/workflows/dvv-ci.yml` (see CI) |

For T0, the test names select the area: `-R "^dvv_build\."` (dvv-build), `-R "\.compile_fail\."`
(factory and registry changes) or a library's `dvv_<x>.` prefix. In a built tree,
`ctest --preset vs2026 -L <label>` selects by the labels `gpu`, `display`, `gui`, `ffmpeg` and
`package` (not available through `-Tests`). A change in a library's public header or behaviour also
needs `-Downstream`.

`sanity.ps1` checks dvv-build, the libraries of `repos.txt` next to it and the application (when
the root is `<app>/libs`). For each one it builds the `vs2026` tree incrementally and runs
`ctest --preset vs2026-sanity` with the GPU settings above (dvv-build: only its `dvv_build.*`
tests). Without `-Repo` it checks the repositories with uncommitted or unpushed changes, or all of
them when none has. Only the selected repositories are built. It prints one PASS or FAIL line per
repository with its build and test times (logs in `<root>/_build/sanity/`) and exits with 1 on a
failure. Switches:

- `-Downstream`: also every present repository after the first selected one (the order of
  `repos.txt`, then the application), so the users of a changed library are rebuilt and tested.
- `-Small`: `vs2026-small` instead of `vs2026-sanity` in the selected repositories and the
  application; the repositories `-Downstream` adds between them keep `vs2026-sanity`.
- `-Tests <regex>`: needs exactly one repository given with `-Repo`; there it tests with
  `vs2026-small` and `ctest -R <regex>` (in dvv-build the regex replaces the `^dvv_build\.`
  filter). Repositories added by `-Downstream` keep their usual preset and get no `-R`. An empty
  regex is an error.
- `-NoGui`: leaves out the `display` tests.

On Linux (bash, tools environment active) the same cycle is
`<root>/dvv-build/tools/sanity.sh [--repo <name>,...] [--gui] [--small] [--downstream] [--tests <regex>]`:
the `ninja-clang` tree with the test presets `ninja-clang-sanity` and `ninja-clang-small`
(`--tests` follows the same rule as `-Tests`, with `ninja-clang-small`);
`VK_DRIVER_FILES` defaults to the lavapipe ICD. The `display` tests run only with `--gui` and an X
display in `DISPLAY` (WSLg under WSL 2, or `xvfb-run -a -s "-screen 0 1920x1080x24"` as in CI). Logs
go to `<root>/_build/sanity-linux/`.

On macOS it is the same script and switches with the `ninja-macos` tree, the test presets
`ninja-macos-sanity` and `ninja-macos-small`, the `appleclang` prefix and the prefix's KosmicKrisp
ICD as the default `VK_DRIVER_FILES`; `--gui` needs a desktop session instead of `DISPLAY`, and the
logs go to `<root>/_build/sanity-macos/`. The T2 workflows on macOS are `ninja-macos` and
`ninja-macos-asan`.

## Checks

dvv-build's own tests (`cmake --workflow --preset vs2026` in dvv-build runs them all, prefix
`dvv_build.`; CI's `tools` job runs the script tests directly from the repository root):

| Test | Command | Checks |
|---|---|---|
| `dvv_build.spdx` | `cmake -P tests/spdx/test_spdx.cmake` | `cmake/DvvSpdx.cmake` |
| `dvv_build.third_party_gate` | `cmake -P tests/spdx/test_third_party_gate.cmake` | the licence gate of the superbuild |
| `dvv_build.third_party_versions` | `cmake -P tests/deps/test_versions.cmake` | every declaration in `deps/versions.cmake` passes the gate; the per-platform and shipped sets |
| `dvv_build.superbuild_scripts` | `cmake -DWORK_DIR=<dir> -P tests/deps/test_superbuild_scripts.cmake` | the scripts the superbuild runs (`deps/*.cmake`) |
| `dvv_build.check_vulkan_device` | `cmake -DWORK_DIR=<dir> -P tests/ci/test_check_vulkan_device.cmake` | `tools/check-vulkan-device.cmake` |
| `dvv_build.ci_image_inputs` | `cmake -DWORK_DIR=<dir> -P tests/ci/test_ci_image_inputs.cmake` | `tools/ci-image-inputs.cmake` |
| `dvv_build.check_ci_image` | `cmake -DWORK_DIR=<dir> -P tests/ci/test_check_ci_image.cmake` | `tools/check-ci-image.cmake` on saved facts |
| `dvv_build.privacy_lint` | `cmake -DWORK_DIR=<dir> -P tests/privacy/test_privacy_lint.cmake` | `tools/privacy-lint.cmake` |
| `dvv_build.presets_consistency` | `cmake -P tests/cmake/test_presets_consistency.cmake` | lib and app preset files describe the same presets |
| `dvv_build.presets_consistency_drift` | `cmake -DWORK_DIR=<dir> -P tests/cmake/test_presets_consistency_drift.cmake` | that check fails on an edited copy |
| `dvv_build.dvv_deps` | `cmake -DWORK_DIR=<dir> -DGENERATOR=Ninja -P tests/cmake/test_dvv_deps.cmake` | `dvv_dependencies()` in lib and app layouts |
| `dvv_build.fetch_deps` | `cmake -DWORK_DIR=<dir> -P tests/tools/test_fetch_deps.cmake` | `tools/fetch-deps.cmake` (local bare repositories) |
| `dvv_build.check_pins` | `cmake -DWORK_DIR=<dir> -P tests/tools/test_check_pins.cmake` | `tools/check-pins.cmake` (local bare repositories) |
| `dvv_build.os_suffixes` | `cmake -P tests/cmake/test_os_suffixes.cmake` | the suffix lists, the union, `dvv_os_suffixes_for` and `dvv_os_suffixes` |
| `dvv_build.os_sources` | `cmake -DWORK_DIR=<dir> -DGENERATOR=Ninja -DMAKE_PROGRAM=<ninja> -DCXX=<compiler> -P tests/cmake/test_os_sources.cmake` | `dvv_os_sources` in fixture projects (selection, layering, stub, `OPTIONAL`, `.mm`) |
| `dvv_build.os_blocks` | `cmake -DWORK_DIR=<dir> -P tests/tools/test_os_blocks.cmake` | `tools/os-blocks.cmake` (fixture git repositories) |
| `dvv_build.tidy_files` | `cmake -DWORK_DIR=<dir> -P tests/tools/test_tidy_files.cmake` | `tools/tidy-files.cmake` (fixture compile databases) |
| `dvv_build.wx_consumer` | CTest only (label `package`) | a wxWidgets consumer builds and runs against the prefix |
| `dvv_build.ffmpeg_sdk` | CTest only (label `package`) | a `dvv_ffmpeg_sdk` consumer builds, its `ffmpeg` is an LGPL build, and `dvv-third-party-state.cmake` holds the release data |

The privacy lint, `cmake -DREPO=<repo dir> -DMODE=commits -P dvv-build/tools/privacy-lint.cmake`
(`MODE=tree` for the work tree), also runs in the pre-push hook (`MODE=prepush`) and in CI.
