<#
.SYNOPSIS
    Build the Windows MicroPython FFI DLL without Flutter or Visual Studio.
.EXAMPLE
    .\native\desktop\build.ps1 -Compiler D:\Tools\mingw64\bin\gcc.exe
.EXAMPLE
    .\native\desktop\build.ps1 -CMake C:\Tools\cmake.exe -Ninja C:\Tools\ninja.exe -Compiler C:\Tools\gcc.exe
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string]$BuildType = 'Release',
    [string]$BuildDir = '',
    [string]$CMake = '',
    [string]$Ninja = '',
    [string]$Compiler = '',
    [ValidateRange(1, 64)]
    [int]$Jobs = 2
)

$ErrorActionPreference = 'Stop'
$nativeDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $BuildDir) {
    $BuildDir = Join-Path $nativeDir 'build\windows'
}
$BuildDir = [IO.Path]::GetFullPath($BuildDir)

function Resolve-Tool([string]$Name, [string]$ExplicitPath, [string[]]$Candidates = @()) {
    if ($ExplicitPath) {
        $command = Get-Command $ExplicitPath -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
        throw "Tool not found: $ExplicitPath"
    }
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($candidate in $Candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    throw "Tool '$Name' not found; specify its executable path explicitly."
}

$sdkRoots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME,
    'D:\ProgramData\Android\Sdk', (Join-Path $env:USERPROFILE 'AppData\Local\Android\Sdk'))
$cmakeCandidates = @()
$ninjaCandidates = @()
foreach ($sdkRoot in $sdkRoots) {
    if (-not $sdkRoot) { continue }
    $cmakeRoot = Join-Path $sdkRoot 'cmake'
    if (-not (Test-Path -LiteralPath $cmakeRoot -PathType Container)) { continue }
    foreach ($installation in (Get-ChildItem -LiteralPath $cmakeRoot -Directory | Sort-Object Name -Descending)) {
        $cmakeCandidates += Join-Path $installation.FullName 'bin\cmake.exe'
        $ninjaCandidates += Join-Path $installation.FullName 'bin\ninja.exe'
    }
}

$cmakeExe = Resolve-Tool 'cmake.exe' $CMake $cmakeCandidates
$ninjaExe = Resolve-Tool 'ninja.exe' $Ninja $ninjaCandidates
$compilerExe = Resolve-Tool 'gcc.exe' $Compiler
$ninjaCMakePath = $ninjaExe.Replace('\', '/')
$compilerCMakePath = $compilerExe.Replace('\', '/')
$originalPath = $env:PATH
try {
    # GCC invokes its assembler and linker from the same toolchain directory.
    $env:PATH = "$(Split-Path -Parent $compilerExe);$originalPath"
    & $cmakeExe -S $PSScriptRoot -B $BuildDir -G Ninja `
        "-DCMAKE_MAKE_PROGRAM=$ninjaCMakePath" "-DCMAKE_C_COMPILER=$compilerCMakePath" `
        "-DCMAKE_BUILD_TYPE=$BuildType"
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed: $LASTEXITCODE" }
    & $cmakeExe --build $BuildDir --target qfli_py_ffi --parallel $Jobs
    if ($LASTEXITCODE -ne 0) { throw "Native build failed: $LASTEXITCODE" }
} finally {
    $env:PATH = $originalPath
}

$library = Join-Path $BuildDir 'qfli_py_ffi.dll'
if (-not (Test-Path -LiteralPath $library -PathType Leaf)) {
    throw "Expected FFI library not found: $library"
}
Write-Output $library
