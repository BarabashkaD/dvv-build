#Requires -Version 7.2

<#
.SYNOPSIS
    The sanity cycle: an incremental vs2026 Debug build and the tests labelled sanity, per repository.
.DESCRIPTION
    The repositories are dvv-build, the repositories of repos.txt cloned next to it (in that order)
    and the app (the folder above a libs/ root whose .gitmodules holds libs/dvv-build, as in
    bootstrap.ps1). For each one: configures its vs2026 tree (<root>/_build/<name>/vs2026) if it does
    not exist yet, builds it incrementally (cmake --build --preset vs2026) and runs
    ctest --preset vs2026-sanity with the GPU settings (DVV_REQUIRE_GPU=1, DVV_VK_VALIDATION=sync,
    DVV_VK_VALIDATION_REQUIRED=1 and the validation layer of <root>/_third_party/msvc). dvv-build
    runs only its own dvv_build.* tests.
    Prints one PASS or FAIL line per repository and exits with 1 when any repository fails. The build
    and test output goes to <root>/_build/sanity/<name>.log; a failure prints the log's last lines.
    Everything is resolved from this script's location (<root> is the folder that holds dvv-build).
    Only the selected repositories are built: a change in a lower repository (e.g. dvv-base) is not
    rebuilt into its users unless they are named.
.PARAMETER Repo
    The repositories to check: dvv-build, names from repos.txt or the app's folder name. Default:
    those with uncommitted changes or with commits that are on no remote; all of them when none has.
    Names may also be given comma-separated in one argument (pwsh -File passes -Repo a,b as one
    string).
.PARAMETER NoGui
    Leaves out the tests labelled display (ctest -LE display), for a locked or headless desktop.
#>
[CmdletBinding()]
param(
    [string[]] $Repo,
    [switch] $NoGui
)
$ErrorActionPreference = 'Stop'

$dvvBuild = Split-Path $PSScriptRoot -Parent
$root = Split-Path $dvvBuild -Parent

# name -> work tree, in sanity order: dvv-build, repos.txt, the app.
$dirs = [ordered]@{ 'dvv-build' = $dvvBuild }
Get-Content (Join-Path $dvvBuild 'repos.txt') |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') } |
    ForEach-Object { $dirs[$_] = Join-Path $root $_ }
# The app: the root is its libs/ folder and its .gitmodules holds libs/dvv-build.
$app = Split-Path $root -Parent
$gitmodules = $app ? (Join-Path $app '.gitmodules') : ''
if ((Split-Path $root -Leaf) -eq 'libs' -and $gitmodules -and (Test-Path $gitmodules) -and
    (Test-Path (Join-Path $app '.git')) -and
    ((Get-Content $gitmodules -Raw) -match '(?m)^\s*path\s*=\s*libs/dvv-build\s*$')) {
    $dirs[(Split-Path $app -Leaf)] = $app
}
$known = @($dirs.Keys)

function Test-Present {
    param([string] $Name)
    return Test-Path (Join-Path $dirs[$Name] '.git')
}

function Test-Changed {
    param([string] $Dir)
    if (git -C $Dir status --porcelain) { return $true }
    $unpushed = git -C $Dir rev-list --count HEAD --not --remotes
    return [int] $unpushed -gt 0
}

$Repo = @($Repo -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Repo) {
    $unknown = @($Repo | Where-Object { $_ -notin $known })
    if ($unknown) { throw "Unknown repository: $($unknown -join ', '). Known: $($known -join ', ')" }
    $missing = @($Repo | Where-Object { -not (Test-Present $_) })
    if ($missing) { throw "Not cloned next to dvv-build: $($missing -join ', ')" }
    $selected = @($known | Where-Object { $_ -in $Repo })
} else {
    $present = @($known | Where-Object { Test-Present $_ })
    $selected = @($present | Where-Object { Test-Changed $dirs[$_] })
    if (-not $selected) { $selected = $present }
}

# Runs a native command with its output appended to the log; returns its exit code.
function Invoke-Logged {
    param([string] $Log, [string] $File, [string[]] $Arguments)
    "> $File $($Arguments -join ' ')" | Add-Content -Path $Log
    & $File @Arguments *>> $Log
    return $LASTEXITCODE
}

$envNames = 'DVV_REQUIRE_GPU', 'DVV_VK_VALIDATION', 'DVV_VK_VALIDATION_REQUIRED', 'VK_ADD_LAYER_PATH'
$savedEnv = @{}
foreach ($name in $envNames) { $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name) }
$logDir = Join-Path $root '_build/sanity'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$failed = 0
$total = [Diagnostics.Stopwatch]::StartNew()
try {
    $env:DVV_REQUIRE_GPU = '1'
    $env:DVV_VK_VALIDATION = 'sync'
    $env:DVV_VK_VALIDATION_REQUIRED = '1'
    $env:VK_ADD_LAYER_PATH = [IO.Path]::GetFullPath((Join-Path $root '_third_party/msvc/bin'))
    foreach ($name in $selected) {
        $dir = $dirs[$name]
        $log = Join-Path $logDir "$name.log"
        Set-Content -Path $log -Value "sanity: $name"
        $stage = 'build'
        $code = 0
        $buildTime = [Diagnostics.Stopwatch]::StartNew()
        $testTime = [Diagnostics.Stopwatch]::new()
        Push-Location $dir
        try {
            # Every preset tree is <root>/_build/<folder name>/<preset> (the app's libs/_build too).
            if (-not (Test-Path (Join-Path $root "_build/$name/vs2026/CMakeCache.txt"))) {
                $stage = 'configure'
                $code = Invoke-Logged $log cmake @('--preset', 'vs2026')
                $stage = 'build'
            }
            if ($code -eq 0) {
                $code = Invoke-Logged $log cmake @('--build', '--preset', 'vs2026')
            }
            $buildTime.Stop()
            if ($code -eq 0) {
                $stage = 'tests'
                $test = @('--preset', 'vs2026-sanity')
                if ($name -eq 'dvv-build') { $test += @('-R', '^dvv_build\.') }
                if ($NoGui) { $test += @('-LE', 'display') }
                $testTime.Start()
                $code = Invoke-Logged $log ctest $test
                $testTime.Stop()
            }
        } finally {
            Pop-Location
        }
        $times = 'build {0:N1} s, tests {1:N1} s' -f $buildTime.Elapsed.TotalSeconds, $testTime.Elapsed.TotalSeconds
        if ($code -eq 0) {
            $summary = Select-String -Path $log -Pattern 'tests passed' | Select-Object -Last 1
            Write-Host ("PASS {0,-18} {1}; {2}" -f $name, $times, ($summary.Line ?? '').Trim())
        } else {
            $failed++
            Write-Host ("FAIL {0,-18} {1} failed (exit {2}); {3}; log: {4}" -f $name, $stage, $code,
                $times, "_build/sanity/$name.log")
            Get-Content $log -Tail 25 | ForEach-Object { Write-Host "    $_" }
        }
    }
} finally {
    foreach ($name in $envNames) { [Environment]::SetEnvironmentVariable($name, $savedEnv[$name]) }
}
Write-Host ('sanity: {0} passed, {1} failed in {2:N1} s' -f ($selected.Count - $failed), $failed,
    $total.Elapsed.TotalSeconds)
exit ([int] ($failed -gt 0))
