# Changelog

All notable changes to dvv-build. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow semantic versioning with the dvv rules: compatible = the same major and at least the
minimum version, also for 0.x; breaking changes only in a new major, after a deprecation. This file is
the release notes (there are no GitHub Releases).

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
