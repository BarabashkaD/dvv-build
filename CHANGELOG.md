# Changelog

All notable changes to dvv-build. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow semantic versioning with the dvv rules: compatible = the same major and at least the
minimum version, also for 0.x; breaking changes only in a new major, after a deprecation. This file is
the release notes (there are no GitHub Releases).

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
