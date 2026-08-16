Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = "/work"
$CasesRoot = Join-Path $ProjectRoot "tests/test_data"
$ResultsRoot = Join-Path $ProjectRoot "tests/test_results"
$ScratchRoot = "/tmp/files-archive-tests"

function Copy-DirectoryContent {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return
    }

    Get-ChildItem -LiteralPath $Source -Force |
        Copy-Item -Destination $Destination -Recurse -Force
}

function Set-TestFileTimes {
    param(
        [Parameter(Mandatory)]
        [string]$AppRoot,

        [Parameter(Mandatory)]
        [string]$TimesFile
    )

    if (-not (Test-Path -LiteralPath $TimesFile -PathType Leaf)) {
        return
    }

    $Entries = @(Get-Content -LiteralPath $TimesFile -Raw -Encoding UTF8 | ConvertFrom-Json)

    foreach ($Entry in $Entries) {
        $RelativePath = [string]$Entry.Path
        $FilePath = Join-Path $AppRoot $RelativePath

        if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
            throw "Timestamp target ne postoji: $RelativePath"
        }

        $Item = Get-Item -LiteralPath $FilePath

        if ($Entry.PSObject.Properties.Name -contains "LastWriteTime") {
            $Item.LastWriteTimeUtc = ([datetime]::Parse([string]$Entry.LastWriteTime)).ToUniversalTime()
        }

        if ($Entry.PSObject.Properties.Name -contains "CreationTime") {
            try {
                $Item.CreationTimeUtc = ([datetime]::Parse([string]$Entry.CreationTime)).ToUniversalTime()
            }
            catch {
                # CreationTime nije jednako pouzdan na svim Docker filesystemima.
            }
        }
    }
}

function Get-FileManifest {
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
            Sort-Object FullName |
            ForEach-Object {
                $RelativePath = $_.FullName.Substring($Root.Length).TrimStart("\", "/").Replace("\", "/")
                $Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                "$Hash  $RelativePath"
            }
    )
}

function Write-Lines {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [AllowNull()]
        [string[]]$Lines
    )

    $Directory = Split-Path -Parent $Path

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    if ($null -eq $Lines) {
        $Lines = @()
    }

    Set-Content -LiteralPath $Path -Value $Lines -Encoding UTF8
}

function Invoke-TestCase {
    param(
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo]$Case
    )

    $CaseName = $Case.Name
    $CaseInput = Join-Path $Case.FullName "input"
    $CaseExpected = Join-Path $Case.FullName "expected/data"
    $CaseTimes = Join-Path $Case.FullName "file-times.json"
    $CaseResult = Join-Path $ResultsRoot $CaseName
    $AppRoot = Join-Path (Join-Path $ScratchRoot $CaseName) "app"

    if (Test-Path -LiteralPath $AppRoot) {
        Remove-Item -LiteralPath $AppRoot -Recurse -Force
    }

    if (Test-Path -LiteralPath $CaseResult) {
        Remove-Item -LiteralPath $CaseResult -Recurse -Force
    }

    New-Item -ItemType Directory -Path $AppRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $CaseResult -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path $ProjectRoot "Start-FileArchive.ps1") -Destination $AppRoot -Force
    Copy-Item -LiteralPath (Join-Path $ProjectRoot "archive-lib") -Destination $AppRoot -Recurse -Force
    Copy-DirectoryContent -Source $CaseInput -Destination $AppRoot
    Set-TestFileTimes -AppRoot $AppRoot -TimesFile $CaseTimes

    $RunOutputPath = Join-Path $CaseResult "run-output.log"
    $RunOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $AppRoot "Start-FileArchive.ps1") 2>&1
    $ExitCode = $LASTEXITCODE
    Write-Lines -Path $RunOutputPath -Lines @($RunOutput | ForEach-Object { [string]$_ })

    $LogFile = Join-Path $AppRoot "Logs/FileArchive.log"
    if (Test-Path -LiteralPath $LogFile -PathType Leaf) {
        Copy-Item -LiteralPath $LogFile -Destination (Join-Path $CaseResult "FileArchive.log") -Force
    }

    $ActualData = Join-Path $AppRoot "data"
    $ActualCopy = Join-Path $CaseResult "actual"
    Copy-DirectoryContent -Source $ActualData -Destination $ActualCopy

    $ActualManifest = @(Get-FileManifest -Root $ActualData)
    $ExpectedManifest = @(Get-FileManifest -Root $CaseExpected)
    Write-Lines -Path (Join-Path $CaseResult "actual-tree.txt") -Lines $ActualManifest
    Write-Lines -Path (Join-Path $CaseResult "expected-tree.txt") -Lines $ExpectedManifest

    $Diff = @(Compare-Object -ReferenceObject $ExpectedManifest -DifferenceObject $ActualManifest |
        ForEach-Object {
            $Prefix = if ($_.SideIndicator -eq "<=") { "MISSING" } else { "EXTRA" }
            "$Prefix $($_.InputObject)"
        })

    if ($ExitCode -ne 0) {
        $Diff += "SCRIPT_EXIT_CODE $ExitCode"
    }

    Write-Lines -Path (Join-Path $CaseResult "diff.txt") -Lines $Diff

    if ($Diff.Count -gt 0) {
        Write-Host "FAIL $CaseName"
        $Diff | ForEach-Object { Write-Host "  $_" }
        return $false
    }

    Write-Host "PASS $CaseName"
    return $true
}

if (Test-Path -LiteralPath $ResultsRoot) {
    Remove-Item -LiteralPath $ResultsRoot -Recurse -Force
}

if (Test-Path -LiteralPath $ScratchRoot) {
    Remove-Item -LiteralPath $ScratchRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $ResultsRoot -Force | Out-Null
New-Item -ItemType Directory -Path $ScratchRoot -Force | Out-Null

$Cases = @(Get-ChildItem -LiteralPath $CasesRoot -Directory | Sort-Object Name)

if ($Cases.Count -eq 0) {
    throw "Nema test case foldera u: $CasesRoot"
}

$Failed = 0

foreach ($Case in $Cases) {
    if (-not (Invoke-TestCase -Case $Case)) {
        $Failed++
    }
}

if ($Failed -gt 0) {
    Write-Host "$Failed testova je palo. Detalji su u tests/test_results."
    exit 1
}

Write-Host "Svi testovi su prosli."
