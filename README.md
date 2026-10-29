# dvv-build

The shared build infrastructure of the `dvv` libraries and of the applications that use them: CMake
presets, the shared compiler options (`DvvCompilerOptions.cmake`), the dependency rules
(`dvv-deps.txt`, `DvvDeps.cmake`), the bootstrap scripts, the
third-party superbuild with its licence gate, the tools (`fetch-deps`, `check-pins`, privacy lint,
sanity cycles) and the reusable CI workflow. dvv-build is versioned (`VERSION`) and tagged like the
libraries.

## Repositories

| Repository | Content |
|---|---|
| dvv-build | presets, dependency rules, bootstrap, third-party superbuild and licence gate, tools, CI |
| dvv-base | errors, tasks and executors, logger, lifetime registry and leak check, JSON, URIs, paths |
| dvv-registry | component registry, capabilities, parameter schemas, component kind check |
| dvv-platform | native windows, Vulkan surfaces, dynamic libraries, `FileReader` |
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
dvv-build 0.1.1
dvv-base 0.1.0
dvv-platform 0.1.0
```

- `dvv-build <version>` appears exactly once, anywhere in the file; `dvv-<x> <version>` once per
  dependency; a line that starts with `#` is a comment. `cmake/DvvDepsFile.cmake` is the one reader (CI reads the
  `dvv-build` line with bash by the same rules before dvv-build is checked out).
- `dvv_dependencies()` (`cmake/DvvDeps.cmake`) checks at every configure that each dependency is
  present in the root and meets its minimum, and makes it available; the dependencies build without
  their tests unless `DVV_TEST_DEPENDENCIES` is set.
- **Transitive minimums:** a repository's minimum for X is at least the minimum for X of each of
  its dvv dependencies, and it lists every dvv library its dependencies list. `fetch-deps` checks
  this and names the line to raise.

## Versions

- Semantic versions, `v<major>.<minor>.<patch>` tags. Compatible means the same major and at least
  the minimum version, **also for 0.x** (unlike the usual SemVer 0.x habit where a minor may break);
  the package version files use `SameMajorVersion`.
- A breaking change comes only with a new major; anything removed is deprecated first.
- A pushed tag is never moved; a fix is a new patch release.
- Each repository's `CHANGELOG.md` is its release notes; the libraries and dvv-build have no
  GitHub Releases.

## Prerequisites

- Windows: Visual Studio 2026 (C++ workload), PowerShell 7, Git, Python 3; for the GPU tests a
  driver with Vulkan 1.4. The tools (CMake 4.3, Ninja, clang-format and clang-tidy 19) are
  installed with pip from dvv-build's `tools/requirements.txt` right after cloning it (see below).
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

## Building a library alone

`<base>` is the account holding the dvv repositories, e.g. `https://github.com/<owner>`.

```powershell
git clone <base>/dvv-gpu
git clone --branch v0.1.1 <base>/dvv-build      # the dvv-build line of dvv-gpu/dvv-deps.txt
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

- `fetch-deps` clones each missing dependency next to the library at tag `v<minimum>` (depth 1)
  from `DVV_GIT_BASE_URL` (`-D` or environment) or else from the library's origin without its last
  path part. An existing dependency is checked, never updated. `REPO` is the library's folder name
  in the root, not a path.
- `bootstrap` gives dvv-build, the libraries next to it and the app (when the root is `<app>/libs`)
  the shared git hooks and **dvv-build's repository-local commit identity** (only that one, never
  the global one, and only to repositories without their own), so set it in dvv-build first. It
  then builds the third-party dependencies into `<root>/_third_party/<toolchain>` (the first run
  takes 10 to 20 minutes; later runs say "up to date"). `-Toolchain msvc|clang`, `-Force` rebuilds,
  `-BundleFfmpeg OFF` builds application packages without FFmpeg (bash: `--toolchain`, `--force`,
  `--bundle-ffmpeg`).
- custom_ffmpeg's LGPL shared release is installed into `_third_party/<toolchain>/custom_ffmpeg`.
  FFmpeg is never linked; CMake projects find it with `find_package(dvv_ffmpeg_sdk CONFIG REQUIRED)`.
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
   version.

A dvv-build change follows the same flow. A library's `dvv-build` line in `dvv-deps.txt` and the
`@v<X>` of its `ci.yml` move together; `check-pins` (lib mode) checks it:
`cmake -DREPO=dvv-<x> -DMODE=lib -P dvv-build/tools/check-pins.cmake` in the dvv root, where `REPO`
is the path of the repository folder.

## CI

`.github/workflows/dvv-ci.yml` is the reusable workflow (Windows MSVC and Linux Clang builds with
AddressSanitizer and ThreadSanitizer variants, and a lint job). On Windows, Debug and Release run as
separate jobs (`windows-msvc`, `windows-msvc-release`):

```yaml
concurrency:                      # newer PR pushes cancel older runs; a running main run finishes
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
jobs:
  ci:
    uses: <owner>/dvv-build/.github/workflows/dvv-ci.yml@v0.1.1   # = the dvv-build line
    with:
      repo: dvv-gpu
```

- Library (lib layout): reads the `dvv-build` line, checks out dvv-build at that tag, runs
  `fetch-deps` with `DVV_GIT_BASE_URL` = the caller's account, so the libraries' minimum versions
  are tested. Lint: privacy lint, `check-pins` (lib mode), clang-format, clang-tidy. A fork needs
  the dvv repositories under its own account.
- Application: `app: true` (submodules checked out recursively; `check-pins` in app mode), and
  `test-dependencies: true` to run every library's tests at the pins.
- dvv-build's own `ci.yml` runs the script tests on Windows and Linux (`tools`) and the reusable
  workflow on dvv-build itself (`self`).

The build jobs restore the third-party prefix from a cache keyed on `deps/**`,
`cmake/DvvThirdParty.cmake` and `cmake/DvvSpdx.cmake`, and save it right after bootstrap.

## Tests

The GPU tests (label `gpu`) need a Vulkan 1.4 device; without one they exit with 77 and CTest
reports them as skipped. CTest uses the validation layer built by bootstrap, and every GPU test
fails on a validation message. Display tests (label `display`, and `gui` for application
self-tests) need a desktop. Environment settings:

| Variable | Values | Effect |
|---|---|---|
| `DVV_REQUIRE_GPU` | `1` | a missing device or display fails the tests instead of skipping them |
| `DVV_VK_VALIDATION` | `off`, `on`, `sync` | validation mode; default `on` in Debug when the layer is present, else `off` |
| `DVV_VK_VALIDATION_REQUIRED` | `0`, `1` | `1`: a missing validation layer is an error |
| `DVV_REQUIRE_FFMPEG` | `1` | a missing FFmpeg fails the FFmpeg tests (label `ffmpeg`) instead of skipping them |
| `DVV_TEST_DEPENDENCIES` | empty or `ON` | also build and run the tests of the dvv dependencies |

Three test cycles (Windows, PowerShell 7):

| Cycle | When | Command |
|---|---|---|
| Sanity | after any change | `pwsh <root>/dvv-build/tools/sanity.ps1 [-Repo <name>,...] [-NoGui]` |
| Small | once per task | `cmake --build --preset vs2026`, then `ctest --preset vs2026-small` (all but label `package`) |
| Full | releases | `cmake --workflow --preset vs2026` (Debug and Release); `cmake --workflow --preset vs2026-asan` |

`sanity.ps1` checks dvv-build, the libraries of `repos.txt` next to it and the application (when
the root is `<app>/libs`). For each one it builds the `vs2026` tree incrementally and runs
`ctest --preset vs2026-sanity` with the GPU settings above (dvv-build: only its `dvv_build.*`
tests). Without `-Repo` it checks the repositories with uncommitted or unpushed changes, or all of
them when none has. Only the selected repositories are built, so name the users of a changed lower
repository too. It prints one PASS or FAIL line per repository (logs in `<root>/_build/sanity/`)
and exits with 1 on a failure. `-NoGui` leaves out the `display` tests.

On Linux (bash, tools environment active) the same cycle is
`<root>/dvv-build/tools/sanity.sh [--repo <name>,...] [--gui]`: the `ninja-clang` preset and
`ctest --preset ninja-clang -L sanity`; `VK_DRIVER_FILES` defaults to the lavapipe ICD. The
`display` tests run only with `--gui` and an X display in `DISPLAY` (WSLg under WSL 2, or
`xvfb-run -a -s "-screen 0 1920x1080x24"` as in CI). Logs go to `<root>/_build/sanity-linux/`.

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
| `dvv_build.privacy_lint` | `cmake -DWORK_DIR=<dir> -P tests/privacy/test_privacy_lint.cmake` | `tools/privacy-lint.cmake` |
| `dvv_build.presets_consistency` | `cmake -P tests/cmake/test_presets_consistency.cmake` | lib and app preset files describe the same presets |
| `dvv_build.presets_consistency_drift` | `cmake -DWORK_DIR=<dir> -P tests/cmake/test_presets_consistency_drift.cmake` | that check fails on an edited copy |
| `dvv_build.dvv_deps` | `cmake -DWORK_DIR=<dir> -DGENERATOR=Ninja -P tests/cmake/test_dvv_deps.cmake` | `dvv_dependencies()` in lib and app layouts |
| `dvv_build.fetch_deps` | `cmake -DWORK_DIR=<dir> -P tests/tools/test_fetch_deps.cmake` | `tools/fetch-deps.cmake` (local bare repositories) |
| `dvv_build.check_pins` | `cmake -DWORK_DIR=<dir> -P tests/tools/test_check_pins.cmake` | `tools/check-pins.cmake` (local bare repositories) |
| `dvv_build.wx_consumer` | CTest only (label `package`) | a wxWidgets consumer builds and runs against the prefix |
| `dvv_build.ffmpeg_sdk` | CTest only (label `package`) | a `dvv_ffmpeg_sdk` consumer builds, and its `ffmpeg` is an LGPL build |

The privacy lint, `cmake -DREPO=<repo dir> -DMODE=commits -P dvv-build/tools/privacy-lint.cmake`
(`MODE=tree` for the work tree), also runs in the pre-push hook (`MODE=prepush`) and in CI.
