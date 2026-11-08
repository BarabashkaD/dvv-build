#!/bin/sh
# Prepares a dvv root: git hooks, commit identity and the third-party dependencies; the Linux and
# macOS counterpart of bootstrap.ps1.
# The dvv root is the folder that holds dvv-build: a developer folder with the libraries next to
# dvv-build, or the libs/ folder of the app. Points dvv-build, the repositories of repos.txt that
# exist next to it and the app (the folder above a libs/ root whose .gitmodules holds
# libs/dvv-build) at the shared git hooks, copies dvv-build's repository-local commit identity
# (git config --local; never the global one) to those without one,
# and builds the third-party dependencies into <root>/_third_party/<toolchain> and wxWidgets into
# <root>/_third_party/<toolchain>-wx next to it (build tree <root>/_build/tp-<toolchain>). The
# superbuild is skipped while the prefix stamp and the wxWidgets marker
# (<toolchain>-wx/dvv-inputs.sha256, tools/separate-prefix-hash.cmake) are current; within it,
# wxWidgets is skipped while its marker is. Missing repositories are skipped:
# tools/fetch-deps.cmake or git submodule update --init clones them. Nothing machine-specific is
# written into any repository.
#
# Usage: ./bootstrap.sh [--toolchain clang|appleclang] [--force] [--bundle-ffmpeg ON|OFF]
# --toolchain: clang (Clang 19, Linux; the default there) or appleclang (/usr/bin/clang++, macOS
# on Apple Silicon; the default there).
# --force: rebuild every dependency, wxWidgets included (removes the build tree and <toolchain>-wx).
# --bundle-ffmpeg (default ON): whether the rawreel packages ship custom_ffmpeg's LGPL libraries
# (superbuild option DVV_BUNDLE_FFMPEG; user decision U4). FFmpeg is installed either way.
set -eu

if [ "$(uname -s)" = Darwin ]; then toolchain=appleclang; else toolchain=clang; fi
force=0
bundle_ffmpeg=ON
while [ $# -gt 0 ]; do
    case "$1" in
        --toolchain) toolchain=$2; shift 2 ;;
        --force) force=1; shift ;;
        --bundle-ffmpeg) bundle_ffmpeg=$2; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
case "$(uname -s):$toolchain" in
    Darwin:appleclang) c_compiler=/usr/bin/clang; compiler=/usr/bin/clang++ ;;
    Darwin:*) echo "toolchain must be appleclang on macOS" >&2; exit 2 ;;
    *:clang) c_compiler=clang-19; compiler=clang++-19 ;;
    *) echo "toolchain must be clang (GCC is not supported)" >&2; exit 2 ;;
esac
bundle_ffmpeg=$(printf '%s' "$bundle_ffmpeg" | tr '[:lower:]' '[:upper:]')
case "$bundle_ffmpeg" in
    ON|OFF) ;;
    *) echo "--bundle-ffmpeg must be ON or OFF" >&2; exit 2 ;;
esac

# Build prerequisites, checked before anything is configured or built. macOS (Apple Silicon, macOS
# 27 SDK): Ninja and CMake; the compilers and SDK come with Xcode or its Command Line Tools, and
# every library is built from the pinned sources or archives (nothing from Homebrew is linked).
# Linux (spec §13.4): GTK 3 for wxWidgets (with its X11, XCB, XRandR and Wayland development
# packages), zlib and libpng.
superbuild_args=""
if [ "$(uname -s)" = Darwin ]; then
    for program in ninja cmake; do
        if ! command -v "$program" >/dev/null 2>&1; then
            echo "$program is missing. Install it with: brew install ninja cmake" >&2
            exit 1
        fi
    done
    sdk_version=$(xcrun --show-sdk-version 2>/dev/null || true)
    case "$sdk_version" in
        [0-9]*) ;;
        *) echo "No macOS SDK found (xcrun --show-sdk-version). Install the Command Line Tools:" \
               "xcode-select --install" >&2; exit 1 ;;
    esac
    if [ "${sdk_version%%.*}" -lt 27 ]; then
        echo "The macOS SDK $sdk_version is too old; Xcode 27 or its Command Line Tools (SDK 27)" \
            "are required." >&2
        exit 1
    fi
    superbuild_args="-DCMAKE_OSX_DEPLOYMENT_TARGET=27.0 -DCMAKE_OSX_ARCHITECTURES=arm64"
else
    apt_line="sudo apt-get install -y libgtk-3-dev pkgconf libx11-dev libxcb1-dev libxrandr-dev \
libwayland-dev zlib1g-dev libpng-dev xvfb xauth"
    missing=""
    if command -v pkg-config >/dev/null 2>&1; then
        for module in gtk+-3.0 x11 xcb xrandr wayland-client zlib libpng; do
            pkg-config --exists "$module" || missing="$missing $module"
        done
    else
        missing=" pkg-config"
    fi
    if [ -n "$missing" ]; then
        echo "Missing Linux development packages (pkg-config:$missing). Install them with:" >&2
        echo "  $apt_line" >&2
        exit 1
    fi
fi

dvv_build=$(CDPATH= cd -- "$(dirname -- "$0")" >/dev/null && pwd)
root=$(dirname "$dvv_build")
# Only dvv-build's repository-local identity is copied, never the global one: a copied identity
# sticks, because repositories that already have one are left alone.
user_name=$(git -C "$dvv_build" config --local user.name || true)
user_email=$(git -C "$dvv_build" config --local user.email || true)
if [ -z "$user_name" ] || [ -z "$user_email" ]; then
    echo "dvv-build has no repository-local commit identity, so none is copied; set it with" \
        "git -C \"$dvv_build\" config user.name/user.email (GitHub noreply) and re-run bootstrap."
fi

# Points a repository at the shared hooks (path relative to its work tree) and gives it the identity.
set_repo_config() {
    git -C "$1" config core.hooksPath "$2"
    if [ -n "$user_name" ] && ! git -C "$1" config --local user.name >/dev/null; then
        git -C "$1" config user.name "$user_name"
    fi
    if [ -n "$user_email" ] && ! git -C "$1" config --local user.email >/dev/null; then
        git -C "$1" config user.email "$user_email"
    fi
}

git -C "$dvv_build" config core.hooksPath tools/githooks
for repo in $(tr -d '\r' <"$dvv_build/repos.txt" | grep -v '^[[:space:]]*#'); do
    if [ -e "$root/$repo/.git" ]; then set_repo_config "$root/$repo" ../dvv-build/tools/githooks; fi
done
# The app: the root is its libs/ folder and its .gitmodules holds libs/dvv-build.
app=$(dirname "$root")
if [ "$(basename "$root")" = libs ] && [ -f "$app/.gitmodules" ] && [ -e "$app/.git" ] &&
    tr -d '\r' <"$app/.gitmodules" |
        grep -Eq '^[[:space:]]*path[[:space:]]*=[[:space:]]*libs/dvv-build[[:space:]]*$'; then
    set_repo_config "$app" libs/dvv-build/tools/githooks
fi
# Third-party superbuild, skipped while its inputs (deps/, the modules it includes and the FFmpeg
# bundling option) are unchanged.
# sha256sum is in /sbin on recent macOS; shasum is the fallback.
if command -v sha256sum >/dev/null 2>&1; then sha256="sha256sum"; else sha256="shasum -a 256"; fi
hash=$(cd "$dvv_build" && {
    find deps cmake/DvvThirdParty.cmake cmake/DvvSpdx.cmake -type f | LC_ALL=C sort | xargs $sha256
    echo "DVV_BUNDLE_FFMPEG=$bundle_ffmpeg"
} | $sha256 | cut -d' ' -f1)
prefix="$root/_third_party/$toolchain"
stamp="$prefix/versions.sha256"
# wxWidgets has its own prefix (CI caches it apart, so it can be missing or older than the prefix):
# the fast path also needs its marker to equal the hash the superbuild would write.
wx_prefix="$prefix-wx"
wx_hash=$(cmake -DNAME=wxWidgets "-DTOOLCHAIN=$toolchain" \
    -P "$dvv_build/tools/separate-prefix-hash.cmake")
wx_hash=${wx_hash#hash=}
# Exactly 64 hex digits (a newline is not one, so extra output lines fail here too): an empty hash
# would equal a missing marker.
case $wx_hash in
    *[!0-9a-f]* | '') wx_ok=0 ;;
    *) wx_ok=1 ;;
esac
if [ "$wx_ok" -eq 0 ] || [ "${#wx_hash}" -ne 64 ]; then
    echo "tools/separate-prefix-hash.cmake did not print 'hash=<64 hex digits>': '$wx_hash'" >&2
    exit 1
fi
wx_marker=""
if [ -f "$wx_prefix/dvv-inputs.sha256" ]; then wx_marker=$(cat "$wx_prefix/dvv-inputs.sha256"); fi
if [ "$force" -eq 0 ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$hash" ] &&
    [ "$wx_marker" = "$wx_hash" ]; then
    echo "Third-party dependencies for $toolchain are up to date."
    exit 0
fi
build="$root/_build/tp-$toolchain"
# The build tree holds the step stamps of every dependency: reusing it after --force or a deleted
# prefix would skip every step and install nothing. (A wxWidgets marker that does not match makes
# the superbuild remove wxWidgets' stamps itself.)
if [ "$force" -eq 1 ] || [ ! -f "$stamp" ]; then
    rm -rf "$build"
fi
if [ "$force" -eq 1 ]; then
    rm -rf "$wx_prefix"
fi
cmake -S "$dvv_build/deps" -B "$build" -G Ninja "-DCMAKE_C_COMPILER=$c_compiler" \
    "-DCMAKE_CXX_COMPILER=$compiler" "-DDVV_THIRD_PARTY_PREFIX=$prefix" \
    "-DDVV_BUNDLE_FFMPEG=$bundle_ffmpeg" "-DCMAKE_PROJECT_INCLUDE=$dvv_build/cmake/DvvEpBase.cmake" \
    $superbuild_args
cmake --build "$build" --config Release --parallel
printf '%s' "$hash" > "$stamp"
echo "Third-party dependencies for $toolchain installed."
