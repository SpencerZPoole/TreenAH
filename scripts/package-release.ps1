[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$OutputDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$AddonName = "TreenAH"

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Assert-PathInside {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $FullPath = Get-NormalizedFullPath -Path $Path
    $ParentPath = Get-NormalizedFullPath -Path $Parent
    $ExpectedPrefix = $ParentPath + [System.IO.Path]::DirectorySeparatorChar

    if ($FullPath -ne $ParentPath -and -not $FullPath.StartsWith($ExpectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description must stay inside $ParentPath. Resolved path: $FullPath"
    }
}

if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    $ScriptRoot = $PSScriptRoot
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $ScriptRoot ".."
}

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot "dist"
}

$TocPath = Join-Path $ProjectRoot "$AddonName.toc"
if (-not (Test-Path -LiteralPath $TocPath -PathType Leaf)) {
    throw "Missing addon metadata file: $TocPath"
}

$VersionLine = Get-Content -LiteralPath $TocPath |
    Where-Object { $_ -match '^##\s+Version:\s*(.+?)\s*$' } |
    Select-Object -First 1

if (-not $VersionLine) {
    throw "Could not find '## Version:' in $TocPath."
}

$Version = ($VersionLine -replace '^##\s+Version:\s*', '').Trim()
if ([string]::IsNullOrWhiteSpace($Version)) {
    throw "The version field in $TocPath is empty."
}

$RequiredPaths = @(
    "$AddonName.toc",
    "icon.tga",
    "Core",
    "Data",
    "Systems",
    "UI",
    "README.md",
    "LICENSE",
    "CHANGELOG.md"
)

foreach ($RelativePath in $RequiredPaths) {
    $SourcePath = Join-Path $ProjectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Cannot package release because required path is missing: $RelativePath"
    }
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path

$ZipPath = Join-Path $OutputDir "$AddonName-v$Version.zip"
Assert-PathInside -Path $ZipPath -Parent $OutputDir -Description "Release zip path"

if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
}

$TempRoot = [System.IO.Path]::GetTempPath()
$StagingRoot = Join-Path $TempRoot ("$AddonName-package-" + [System.Guid]::NewGuid().ToString("N"))
$AddonStage = Join-Path $StagingRoot $AddonName

try {
    New-Item -ItemType Directory -Path $AddonStage -Force | Out-Null

    foreach ($RelativePath in $RequiredPaths) {
        $SourcePath = Join-Path $ProjectRoot $RelativePath
        $DestinationPath = Join-Path $AddonStage $RelativePath
        Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Recurse -Force
    }

    Compress-Archive -LiteralPath $AddonStage -DestinationPath $ZipPath -CompressionLevel Optimal
    Write-Host "Created $ZipPath"
}
finally {
    if (Test-Path -LiteralPath $StagingRoot) {
        Assert-PathInside -Path $StagingRoot -Parent $TempRoot -Description "Temporary staging path"
        Remove-Item -LiteralPath $StagingRoot -Recurse -Force
    }
}
