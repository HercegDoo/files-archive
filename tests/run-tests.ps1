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

function Get-TreeManifest {
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return @()
    }

    $Directories = @(
        Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force |
            ForEach-Object {
                $RelativePath = $_.FullName.Substring($Root.Length).TrimStart("\", "/").Replace("\", "/")
                "DIR   $RelativePath/"
            }
    )

    $Files = @(
        Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
            ForEach-Object {
                $RelativePath = $_.FullName.Substring($Root.Length).TrimStart("\", "/").Replace("\", "/")
                $Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                "FILE  $Hash  $RelativePath"
            }
    )

    return @($Directories + $Files | Sort-Object)
}

function Get-ExpectedExtraDirectoryManifest {
    param(
        [Parameter(Mandatory)]
        [string]$CaseRoot
    )

    $ExpectedDirectoriesFile = Join-Path $CaseRoot "expected-dirs.txt"

    if (-not (Test-Path -LiteralPath $ExpectedDirectoriesFile -PathType Leaf)) {
        return @()
    }

    return @(
        Get-Content -LiteralPath $ExpectedDirectoriesFile -Encoding UTF8 |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object {
                $RelativePath = ([string]$_).Trim().Trim("\", "/").Replace("\", "/")
                "DIR   $RelativePath/"
            }
    )
}

function Get-ExpectedLines {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    return @(
        Get-Content -LiteralPath $Path -Encoding UTF8 |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { ([string]$_).Trim() }
    )
}

function Get-ArchiveLogText {
    param(
        [Parameter(Mandatory)]
        [string]$LogsRoot,

        [Parameter(Mandatory)]
        [string]$ExtractionRoot
    )

    $LogTextParts = @()

    if (-not (Test-Path -LiteralPath $LogsRoot -PathType Container)) {
        return ""
    }

    $ActiveLog = Join-Path $LogsRoot "FileArchive.log"

    if (Test-Path -LiteralPath $ActiveLog -PathType Leaf) {
        $LogTextParts += Get-Content -LiteralPath $ActiveLog -Raw -Encoding UTF8
    }

    $RotatedLogs = @(
        Get-ChildItem -LiteralPath $LogsRoot -Filter "FileArchive.log.*.zip" -File -Force |
            Sort-Object Name
    )

    foreach ($RotatedLog in $RotatedLogs) {
        $RotatedExtractionRoot = Join-Path $ExtractionRoot $RotatedLog.BaseName

        if (Test-Path -LiteralPath $RotatedExtractionRoot) {
            Remove-Item -LiteralPath $RotatedExtractionRoot -Recurse -Force
        }

        New-Item -ItemType Directory -Path $RotatedExtractionRoot -Force | Out-Null
        Expand-Archive -LiteralPath $RotatedLog.FullName -DestinationPath $RotatedExtractionRoot -Force

        $ExtractedFiles = @(Get-ChildItem -LiteralPath $RotatedExtractionRoot -File -Recurse -Force | Sort-Object FullName)

        foreach ($ExtractedFile in $ExtractedFiles) {
            $LogTextParts += Get-Content -LiteralPath $ExtractedFile.FullName -Raw -Encoding UTF8
        }
    }

    return ($LogTextParts -join [Environment]::NewLine)
}

function Test-ExpectedLogAssertions {
    param(
        [Parameter(Mandatory)]
        [string]$CaseRoot,

        [Parameter(Mandatory)]
        [string]$AppRoot,

        [Parameter(Mandatory)]
        [string]$CaseResult
    )

    $Failures = @()
    $LogsRoot = Join-Path $AppRoot "Logs"
    $ExpectedLogFiles = Get-ExpectedLines -Path (Join-Path $CaseRoot "expected-log-files.txt")
    $ExpectedLogContains = Get-ExpectedLines -Path (Join-Path $CaseRoot "expected-log-contains.txt")
    $ExpandedLogsRoot = Join-Path $CaseResult "expanded-logs"
    $AllLogText = Get-ArchiveLogText -LogsRoot $LogsRoot -ExtractionRoot $ExpandedLogsRoot

    foreach ($ExpectedLogFile in $ExpectedLogFiles) {
        $LogFilePath = Join-Path $LogsRoot $ExpectedLogFile

        if (-not (Test-Path -LiteralPath $LogFilePath -PathType Leaf)) {
            $Failures += "LOG_FILE_MISSING $ExpectedLogFile"
        }
    }

    foreach ($ExpectedText in $ExpectedLogContains) {
        if (-not $AllLogText.Contains($ExpectedText)) {
            $Failures += "LOG_TEXT_MISSING $ExpectedText"
        }
    }

    return $Failures
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

    $LogsRoot = Join-Path $AppRoot "Logs"
    if (Test-Path -LiteralPath $LogsRoot -PathType Container) {
        Copy-Item -LiteralPath $LogsRoot -Destination $CaseResult -Recurse -Force
    }

    $ActualData = Join-Path $AppRoot "data"
    $ActualCopy = Join-Path $CaseResult "actual"
    Copy-DirectoryContent -Source $ActualData -Destination $ActualCopy

    $ActualManifest = @(Get-TreeManifest -Root $ActualData)
    $ExpectedManifest = @(
        (Get-TreeManifest -Root $CaseExpected) +
        (Get-ExpectedExtraDirectoryManifest -CaseRoot $Case.FullName) |
            Sort-Object -Unique
    )
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

    $Diff += Test-ExpectedLogAssertions -CaseRoot $Case.FullName -AppRoot $AppRoot -CaseResult $CaseResult

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

if (Test-Path -LiteralPath $ResultsRoot) {
    Remove-Item -LiteralPath $ResultsRoot -Recurse -Force
}

Write-Host "Svi testovi su prosli."
