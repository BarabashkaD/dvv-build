# Changelog

All notable changes to dvv-build. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow semantic versioning with the dvv rules: compatible = the same major and at least the
minimum version, also for 0.x; breaking changes only in a new major, after a deprecation. This file is
the release notes (there are no GitHub Releases).

## [0.2.0] - 2026-11-07

macOS on Apple Silicon (macOS 27 or newer). The Windows and Linux builds, presets and notices are
unchanged.

### Added
- Presets `ninja-macos` (Debug and Release configurations, `ninja-macos-release`) and
  `ninja-macos-asan` in `cmake/DvvPresets.json` and `cmake/DvvAppPresets.json`, pinned to AppleClang
  (`/usr/bin/clang` and `/usr/bin/clang++` for C, C++, Objective-C and Objective-C++), arm64,
  deployment target 27.0; the test presets `ninja-macos-sanity` and `ninja-macos-small`, the macOS
  twins of `ninja-clang-sanity` and `ninja-clang-small`. There is no ThreadSanitizer preset on macOS.
- `DvvCompilerOptions.cmake` accepts Apple Clang with libc++ on macOS and rejects any other compiler
  or standard library there.
- The macOS third-party prefix `<root>/_third_party/appleclang` (`bootstrap.sh --toolchain
  appleclang`, the default on macOS): Slang, wxWidgets on the native macOS port (wxOSX),
  custom_ffmpeg 1.0.1 (`macos-arm64-shared-lgpl`, rpath `@loader_path`; Windows and Linux stay on
  1.0.0), the Vulkan loader built from source, KosmicKrisp (Mesa's Vulkan driver on Metal) from the
  LunarG SDK and `vulkaninfo`, with their licence texts and notices.
- `tools/check-vulkan-device.cmake` runs the prefix's `vulkaninfo` on the prefix's loader and the
  KosmicKrisp driver on macOS.
- `tools/sanity.sh` runs on macOS (the `ninja-macos` tree with `ninja-macos-sanity` / `-small`, the
  `appleclang` prefix, KosmicKrisp as the default Vulkan driver, uptime from `sysctl kern.boottime`,
  logs in `<root>/_build/sanity-macos/`).
- CI (`dvv-ci.yml`): the jobs `macos-appleclang` and `macos-appleclang-asan` on the `xcode-27` runner.
  The Vulkan device check never fails the job; the display tests are left out unless it finds a
  device and a desktop session. `DVV_REQUIRE_FFMPEG=1` as on Windows and Linux. A caller that
  requires the CI checks may add them.
- Licence supplements are platform-aware: `dvv_licence_supplement()` takes `PLATFORMS`, the
  platforms whose build contains the component; elsewhere the file is checked but not attached
  (custom_ffmpeg's libvpl `third-party-programs.txt` only on Windows and Linux).
- Privacy lint test: a `/Users/<name>/...` path is flagged.
- README: the macOS requirements, building on macOS, the macOS CI jobs and sanity on macOS; the
  examples name v0.2.0.

### Fixed
- The `dvv_build.dvv_deps` test passes on CMake 4.4: its leak check ignores `_FUNCTION_ARGNC`, which
  CMake 4.4 leaves behind after `function()` calls.
- No build-machine paths in the macOS third-party binaries: every superbuild project gets
  `-ffile-prefix-map` for its source, build and install folders (C, C++, Objective-C,
  Objective-C++), and the Vulkan loader is configured with `SYSCONFDIR=/etc`.

## [0.1.2] - 2026-10-29

### Added
- Branch-only dependency override: a `dvv-deps.txt` line may end with ` @<commit>` (40 lowercase hex
  digits) after the version, so a workstream branch can test against an untagged dependency commit.
  `fetch-deps.cmake` checks out that commit and still checks the minimum version; an overridden
  dependency's own overrides must be repeated in the library. The dvv-build line takes no override.
- `check-pins.cmake` rejects every override (in a library, in an application's own `dvv-deps.txt` and in
  each pinned library's), so main depends only on tagged versions; the lint job runs it as its last
  step, after the format and clang-tidy steps.
- Test presets `ninja-clang-sanity` and `ninja-clang-small`, the Linux twins of `vs2026-sanity` and
  `vs2026-small`.
- `sanity.ps1` / `sanity.sh`: `-Small`/`--small` (the small presets), `-Downstream`/`--downstream`
  (also every later repository in the sanity order) and `-Tests`/`--tests <regex>` (one repository,
  passed on as `ctest -R`). Without them the scripts behave as before.

### Changed
- CI: the Linux build and test step sets `DVV_REQUIRE_FFMPEG=1`, so a missing FFmpeg fails the FFmpeg
  tests instead of skipping them (as on Windows).
- README: the test tiers T0/T1/T2/CI, the new switches, "main depends on tags only" and the override.

## [0.1.1] - 2026-10-29

### Changed
- CI (`dvv-ci.yml`): Windows Debug and Release run as separate, parallel jobs, `windows-msvc` and
  the new `windows-msvc-release`; each runs the configure, build and test steps of its
  configuration. The Windows leg of an application run with the library tests takes about 44 min
  instead of 85-111 min. A caller that requires the CI checks should add `windows-msvc-release`.
- LICENSE: the copyright line names BarabashkaD.

### Fixed
- Privacy lint: a commit whose author is `noreply@github.com` is a finding with its own message;
  GitHub's address stays accepted as the committer of web and pull-request merge commits.

## [0.1.0] - 2026-10-28

First versioned release.

### Added
- CMake presets for libraries (`cmake/DvvPresets.json`) and applications
  (`cmake/DvvAppPresets.json`): Visual Studio 2026 and Ninja with Clang 19, Debug, Release,
  AddressSanitizer and ThreadSanitizer, build trees in `<root>/_build/<repo>/<preset>`.
- Shared compiler options (`cmake/DvvCompilerOptions.cmake`): C++23, warnings, path mapping;
  outside MSVC only Clang 19 or newer with libstdc++ 14 or newer (no GCC, no libc++).
- Dependency rules: `dvv-deps.txt` with minimum versions, read by `cmake/DvvDepsFile.cmake`;
  `dvv_dependencies()` (`cmake/DvvDeps.cmake`) checks and adds the dvv dependencies at configure.
- `bootstrap.ps1` and `bootstrap.sh`: git hooks and commit identity for the repositories of a dvv
  root, and the third-party superbuild with its licence gate into `<root>/_third_party/<toolchain>`
  (including the custom_ffmpeg LGPL release).
- Tools: `fetch-deps.cmake` (clones a library's dependencies at their minimum tags and checks the
  transitive minimums), `check-pins.cmake` (version references of a library or an application),
  the privacy lint with its pre-push hook, and the sanity cycles `sanity.ps1` and `sanity.sh`.
- The reusable CI workflow `dvv-ci.yml` for libraries, applications and dvv-build itself.
