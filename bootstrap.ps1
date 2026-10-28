#Requires -Version 7

<#
.SYNOPSIS
    Prepares a dvv root: git hooks, commit identity and the third-party dependencies.
.DESCRIPTION
    The dvv root is the folder that holds dvv-build: a developer folder with the libraries next to
    dvv-build, or the libs/ folder of the app. Points dvv-build, the repositories of repos.txt that
    exist next to it and the app (the folder above a libs/ root whose .gitmodules holds
    libs/dvv-build) at the shared git hooks, copies dvv-build's repository-local commit identity
    (git config --local; never the global one) to those without one,
    and builds the third-party dependencies into <root>/_third_party/<toolchain> (build tree
    <root>/_build/tp-<toolchain>). Missing repositories are skipped: tools/fetch-deps.cmake or
    git submodule update --init clones them. Nothing machine-specific is written into any repository.
.PARAMETER Toolchain
    msvc (default) or clang.
.PARAMETER Force
    Rebuild the third-party dependencies even if they are up to date.
.PARAMETER BundleFfmpeg
    ON (default) or OFF: whether the rawreel packages ship custom_ffmpeg's LGPL libraries (superbuild
    option DVV_BUNDLE_FFMPEG; user decision U4). FFmpeg is installed for development and tests
    either way.
#>
param(
    [ValidateSet('msvc', 'clang')]
    [string] $Toolchain = 'msvc',
    [switch] $Force,
    [ValidateSet('ON', 'OFF')]
    [string] $BundleFfmpeg = 'ON'
)
$ErrorActionPreference = 'Stop'
$BundleFfmpeg = $BundleFfmpeg.ToUpperInvariant()

# The deepest path the builds create below the dvv root, counting the separator after the root: an
# application's vs2026-asan tree with DVV_TEST_DEPENDENCIES goes 189 characters deep, plus 1 for the
# separator and 1 spare. Windows paths must stay within 259 characters, so the root may be at most
# 259 - DVV_PATH_DEPTH long.
Set-Variable -Name DVV_PATH_DEPTH -Value 191 -Option Constant
$maxPath = 259

function Invoke-Native {
    param([string] $File, [string[]] $Arguments)
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$File $($Arguments -join ' ') failed with exit code $LASTEXITCODE" }
}

$dvvBuild = $PSScriptRoot
$root = Split-Path $dvvBuild -Parent
$repos = Get-Content (Join-Path $dvvBuild 'repos.txt') |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }

# Only dvv-build's repository-local identity is copied, never the global one: a copied identity
# sticks, because repositories that already have one are left alone.
$userName = git -C $dvvBuild config --local user.name
$userEmail = git -C $dvvBuild config --local user.email
if (-not $userName -or -not $userEmail) {
    Write-Host ("dvv-build has no repository-local commit identity, so none is copied; set it with " +
        "git -C `"$dvvBuild`" config user.name/user.email (GitHub noreply) and re-run bootstrap.")
}

# Points a repository at the shared hooks (path relative to its work tree) and gives it the identity.
function Set-RepoConfig {
    param([string] $Dir, [string] $HooksPath)
    Invoke-Native git @('-C', $Dir, 'config', 'core.hooksPath', $HooksPath)
    if ($userName -and -not (git -C $Dir config --local user.name)) {
        Invoke-Native git @('-C', $Dir, 'config', 'user.name', $userName)
    }
    if ($userEmail -and -not (git -C $Dir config --local user.email)) {
        Invoke-Native git @('-C', $Dir, 'config', 'user.email', $userEmail)
    }
}

Invoke-Native git @('-C', $dvvBuild, 'config', 'core.hooksPath', 'tools/githooks')
foreach ($repo in $repos) {
    $dir = Join-Path $root $repo
    if (Test-Path (Join-Path $dir '.git')) { Set-RepoConfig $dir '../dvv-build/tools/githooks' }
}
# The app: the root is its libs/ folder and its .gitmodules holds libs/dvv-build.
$app = Split-Path $root -Parent
$gitmodules = $app ? (Join-Path $app '.gitmodules') : ''
if ((Split-Path $root -Leaf) -eq 'libs' -and $gitmodules -and (Test-Path $gitmodules) -and
    (Test-Path (Join-Path $app '.git')) -and
    ((Get-Content $gitmodules -Raw) -match '(?m)^\s*path\s*=\s*libs/dvv-build\s*$')) {
    Set-RepoConfig $app 'libs/dvv-build/tools/githooks'
}

# Third-party superbuild, skipped while its inputs (deps/, the modules it includes and the FFmpeg
# bundling option) are unchanged.
$inputs = @(Get-ChildItem (Join-Path $dvvBuild 'deps') -Recurse -File) +
    @('DvvThirdParty.cmake', 'DvvSpdx.cmake' | ForEach-Object { Get-Item (Join-Path $dvvBuild "cmake/$_") })
$listing = ($inputs | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($dvvBuild, $_.FullName).Replace('\', '/')
        "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $relative`n"
    } | Sort-Object) -join ''
# The option changes the notices and the package files, so it is part of the stamp.
$listing += "DVV_BUNDLE_FFMPEG=$BundleFfmpeg`n"
$stream = [IO.MemoryStream]::new([Text.UTF8Encoding]::new($false).GetBytes($listing))
$hash = (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash.ToLowerInvariant()
$prefix = Join-Path $root "_third_party/$Toolchain"
$stamp = Join-Path $prefix 'versions.sha256'
$rootTooLong = $IsWindows -and $root.Length + $DVV_PATH_DEPTH -gt $maxPath
$rootMessage = "The dvv root $root is $($root.Length) characters long; at most $($maxPath - $DVV_PATH_DEPTH) " +
    "fit the Windows path limit ($maxPath, of which the builds use up to $DVV_PATH_DEPTH below the " +
    "root). Clone to a shorter path."
if (-not $Force -and (Test-Path $stamp) -and ((Get-Content $stamp -Raw).Trim() -eq $hash)) {
    # A valid stamp (for example a copied prefix) needs no superbuild, but the preset builds still
    # create deep trees below the root.
    if ($rootTooLong) { Write-Warning $rootMessage }
    Write-Host "Third-party dependencies for $Toolchain are up to date."
    exit 0
}
if ($rootTooLong) { throw $rootMessage }
$build = Join-Path $root "_build/tp-$Toolchain"
# The build tree holds the step stamps of every dependency: reusing it after -Force or a deleted
# prefix would skip every step and install nothing.
if (($Force -or -not (Test-Path $stamp)) -and (Test-Path $build)) {
    Remove-Item $build -Recurse -Force
}
$configure = @('-S', (Join-Path $dvvBuild 'deps'), '-B', $build, "-DDVV_THIRD_PARTY_PREFIX=$prefix",
    "-DDVV_BUNDLE_FFMPEG=$BundleFfmpeg", "-DCMAKE_PROJECT_INCLUDE=$((Join-Path $dvvBuild 'cmake/DvvEpBase.cmake').Replace('\', '/'))")
switch ($Toolchain) {
    'msvc' { $configure += @('-G', 'Visual Studio 18 2026', '-A', 'x64') }
    'clang' { $configure += @('-G', 'Ninja', '-DCMAKE_C_COMPILER=clang-19', '-DCMAKE_CXX_COMPILER=clang++-19') }
}
Invoke-Native cmake $configure
Invoke-Native cmake @('--build', $build, '--config', 'Release', '--parallel')
Set-Content -Path $stamp -Value $hash -NoNewline
Write-Host "Third-party dependencies for $Toolchain installed."
