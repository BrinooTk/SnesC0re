param(
    [ValidateSet("snes")]
    [string]$Target = "snes"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$BuildDir = Join-Path $ProjectRoot "compiled"
$ObjDir = Join-Path $BuildDir "obj"

Set-Location $ScriptDir

function Find-Zig {
    $cmd = Get-Command zig -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $wingetBase = Join-Path $env:LOCALAPPDATA "Microsoft\\WinGet\\Packages"
    if (Test-Path $wingetBase) {
        $zig = Get-ChildItem $wingetBase -Recurse -Filter zig.exe -ErrorAction SilentlyContinue |
            Sort-Object FullName |
            Select-Object -First 1 -ExpandProperty FullName
        if ($zig) {
            return $zig
        }
    }

    throw "zig.exe not found. Install Zig first."
}

function Ensure-ParentDir {
    param([string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Get-RelativePathCompat {
    param(
        [string]$ProjectDir,
        [string]$SourcePath
    )

    if ([System.IO.Path]::IsPathRooted($SourcePath)) {
        $fullSource = [System.IO.Path]::GetFullPath($SourcePath)
    } else {
        $fullSource = [System.IO.Path]::GetFullPath((Join-Path $ProjectDir $SourcePath))
    }
    $projectUri = New-Object System.Uri(([System.IO.Path]::GetFullPath($ProjectDir).TrimEnd('\') + '\'))
    $sourceUri = New-Object System.Uri($fullSource)
    return [System.Uri]::UnescapeDataString($projectUri.MakeRelativeUri($sourceUri).ToString()).Replace('/', '\')
}

function Get-RelativeObjectPath {
    param(
        [string]$ProjectDir,
        [string]$SourcePath
    )

    $relativeSource = Get-RelativePathCompat -ProjectDir $ProjectDir -SourcePath $SourcePath
    return [System.IO.Path]::ChangeExtension($relativeSource, ".o")
}

function Compile-Target {
    param(
        [string]$Zig,
        [string[]]$Sources
    )

    $commonArgs = @(
        "-target", "x86_64-freestanding-none",
        "-Os",
        "-ffreestanding",
        "-fno-stack-protector",
        "-fno-builtin",
        "-fpie",
        "-mno-red-zone",
        "-mstackrealign",
        "-fomit-frame-pointer",
        "-fcf-protection=none",
        "-fno-exceptions",
        "-fno-unwind-tables",
        "-fno-asynchronous-unwind-tables",
        "-Wall",
        "-Wno-unused-function",
        "-Isrc"
    )

    if (-not (Test-Path $BuildDir)) {
        New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
    }

    $objs = @()
    foreach ($src in $Sources) {
        $fullSrc = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir $src))
        $relativeObj = Get-RelativeObjectPath -ProjectDir $ScriptDir -SourcePath $src
        $obj = Join-Path $ObjDir $relativeObj
        Ensure-ParentDir $obj

        Write-Host "Compiling $src"
        & $Zig cc @commonArgs -c $fullSrc -o $obj
        if ($LASTEXITCODE -ne 0) {
            throw "compile failed: $src"
        }
        $objs += $obj
    }

    $elf = Join-Path $BuildDir "snes_emu.elf"
    $bin = Join-Path $BuildDir "snes_emu.bin"
    Ensure-ParentDir $elf

    $linkArgs = @(
        "cc"
    ) + $commonArgs + @(
        "-T", "linker.ld",
        "-nostdlib",
        "-nostartfiles",
        "-static",
        "-Wl,--build-id=none",
        "-no-pie",
        "-o", $elf
    ) + $objs

    & $Zig @linkArgs
    if ($LASTEXITCODE -ne 0) {
        throw "link failed: $elf"
    }

    & $Zig objcopy -O binary $elf $bin
    if ($LASTEXITCODE -ne 0) {
        throw "objcopy failed: $bin"
    }

    Get-Item $elf, $bin | Select-Object Name, Length
}

$zig = Find-Zig
Write-Host "Using Zig: $zig"

$snesSources = @(
    "src/snes_main.c",
    "src/snes_runtime.c",
    "src/ftp.c"
) + (
    Get-ChildItem "src/snes" -Filter "*.c" |
    Sort-Object Name |
    ForEach-Object { Get-RelativePathCompat -ProjectDir $ScriptDir -SourcePath $_.FullName }
)

Compile-Target -Zig $zig -Sources $snesSources
