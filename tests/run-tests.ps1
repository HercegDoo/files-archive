Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = "/work"
$CasesRoot = Join-Path $ProjectRoot "tests/test_data"
$WizardCasesRoot = Join-Path $ProjectRoot "tests/wizard_data"
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

                if ($_.Extension.ToLowerInvariant() -eq ".zip") {
                    "ZIP   $RelativePath"
                }
                else {
                    $Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                    "FILE  $Hash  $RelativePath"
                }
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

function Get-ExpectedZipManifest {
    param(
        [Parameter(Mandatory)]
        [string]$CaseRoot
    )

    $ExpectedZipsFile = Join-Path $CaseRoot "expected-zips.txt"

    if (-not (Test-Path -LiteralPath $ExpectedZipsFile -PathType Leaf)) {
        return @()
    }

    $Manifest = @(
        Get-Content -LiteralPath $ExpectedZipsFile -Encoding UTF8 |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object {
                $RelativePath = ([string]$_).Trim().Trim("\", "/").Replace("\", "/")
                $ParentPath = Split-Path -Path $RelativePath -Parent
                $Entries = @()

                if (-not [string]::IsNullOrWhiteSpace($ParentPath)) {
                    $Entries += "DIR   $($ParentPath.Replace("\", "/"))/"
                }

                $Entries += "ZIP   $RelativePath"

                $Entries
            }
    )

    return @($Manifest | Sort-Object -Unique)
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

function Get-NormalizedActiveLogLines {
    param(
        [Parameter(Mandatory)]
        [string]$LogsRoot
    )

    $ActiveLog = Join-Path $LogsRoot "FileArchive.log"

    if (-not (Test-Path -LiteralPath $ActiveLog -PathType Leaf)) {
        return @()
    }

    return @(
        Get-Content -LiteralPath $ActiveLog -Encoding UTF8 |
            ForEach-Object {
                ([string]$_) -replace "^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] ", ""
            }
    )
}

function Get-ExpectedExactLogLines {
    param(
        [Parameter(Mandatory)]
        [string]$CaseRoot,

        [Parameter(Mandatory)]
        [string]$AppRoot
    )

    $ExpectedExactLogFile = Join-Path $CaseRoot "expected-log-exact.txt"

    if (-not (Test-Path -LiteralPath $ExpectedExactLogFile -PathType Leaf)) {
        return $null
    }

    return @(
        Get-Content -LiteralPath $ExpectedExactLogFile -Encoding UTF8 |
            ForEach-Object {
                ([string]$_).Replace("{APP_ROOT}", $AppRoot)
            }
    )
}

function Compare-ExactLogLines {
    param(
        [AllowNull()]
        [string[]]$ExpectedLines,

        [Parameter(Mandatory)]
        [string[]]$ActualLines
    )

    $Failures = @()

    if ($null -eq $ExpectedLines) {
        return $Failures
    }

    if ($ExpectedLines.Count -ne $ActualLines.Count) {
        $Failures += "LOG_EXACT_LINE_COUNT expected=$($ExpectedLines.Count) actual=$($ActualLines.Count)"
    }

    $MaxCount = [math]::Max($ExpectedLines.Count, $ActualLines.Count)

    for ($Index = 0; $Index -lt $MaxCount; $Index++) {
        $LineNumber = $Index + 1
        $ExpectedLine = if ($Index -lt $ExpectedLines.Count) { $ExpectedLines[$Index] } else { "<missing>" }
        $ActualLine = if ($Index -lt $ActualLines.Count) { $ActualLines[$Index] } else { "<missing>" }

        if ($ExpectedLine -ne $ActualLine) {
            $Failures += "LOG_EXACT_MISMATCH line=$LineNumber expected='$ExpectedLine' actual='$ActualLine'"
        }
    }

    return $Failures
}

function Test-ExpectedZipEntries {
    param(
        [Parameter(Mandatory)]
        [string]$CaseRoot,

        [Parameter(Mandatory)]
        [string]$ActualDataRoot
    )

    $ExpectedZipEntriesFile = Join-Path $CaseRoot "expected-zip-entries.txt"
    $Failures = @()

    if (-not (Test-Path -LiteralPath $ExpectedZipEntriesFile -PathType Leaf)) {
        return $Failures
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $ExpectedByZip = @{}

    Get-Content -LiteralPath $ExpectedZipEntriesFile -Encoding UTF8 |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object {
            $Parts = ([string]$_).Split("|", 2)

            if ($Parts.Count -ne 2) {
                throw "Neispravan expected-zip-entries format: $_"
            }

            $ZipPath = $Parts[0].Trim().Trim("\", "/").Replace("\", "/")
            $EntryPath = $Parts[1].Trim().Trim("\", "/").Replace("\", "/")

            if (-not $ExpectedByZip.ContainsKey($ZipPath)) {
                $ExpectedByZip[$ZipPath] = @()
            }

            $ExpectedByZip[$ZipPath] += $EntryPath
        }

    foreach ($ZipPath in $ExpectedByZip.Keys) {
        $ActualZipPath = Join-Path $ActualDataRoot $ZipPath

        if (-not (Test-Path -LiteralPath $ActualZipPath -PathType Leaf)) {
            $Failures += "ZIP_MISSING $ZipPath"
            continue
        }

        $Zip = [System.IO.Compression.ZipFile]::OpenRead($ActualZipPath)

        try {
            $ActualEntries = @($Zip.Entries | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.Name)
            } | ForEach-Object {
                $_.FullName.Replace("\", "/")
            } | Sort-Object)
        }
        finally {
            $Zip.Dispose()
        }

        $ExpectedEntries = @($ExpectedByZip[$ZipPath] | Sort-Object)
        $EntryDiff = @(Compare-Object -ReferenceObject $ExpectedEntries -DifferenceObject $ActualEntries)

        foreach ($Diff in $EntryDiff) {
            $Prefix = if ($Diff.SideIndicator -eq "<=") { "ZIP_ENTRY_MISSING" } else { "ZIP_ENTRY_EXTRA" }
            $Failures += "$Prefix $ZipPath|$($Diff.InputObject)"
        }
    }

    return $Failures
}

function Get-ExpectedExitCode {
    param(
        [Parameter(Mandatory)]
        [string]$CaseRoot
    )

    $ExpectedExitCodeFile = Join-Path $CaseRoot "expected-exit-code.txt"

    if (-not (Test-Path -LiteralPath $ExpectedExitCodeFile -PathType Leaf)) {
        return 0
    }

    return [int]((Get-Content -LiteralPath $ExpectedExitCodeFile -Raw -Encoding UTF8).Trim())
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
    $ExpectedExactLogLines = Get-ExpectedExactLogLines -CaseRoot $CaseRoot -AppRoot $AppRoot
    $ActualExactLogLines = @(Get-NormalizedActiveLogLines -LogsRoot $LogsRoot)
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

    $Failures += Compare-ExactLogLines -ExpectedLines $ExpectedExactLogLines -ActualLines $ActualExactLogLines

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
    $ExpectedExitCode = Get-ExpectedExitCode -CaseRoot $Case.FullName
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
    $ExpectedManifest = @(
        $ExpectedManifest +
        (Get-ExpectedZipManifest -CaseRoot $Case.FullName) |
            Sort-Object -Unique
    )
    Write-Lines -Path (Join-Path $CaseResult "actual-tree.txt") -Lines $ActualManifest
    Write-Lines -Path (Join-Path $CaseResult "expected-tree.txt") -Lines $ExpectedManifest

    $Diff = @(Compare-Object -ReferenceObject $ExpectedManifest -DifferenceObject $ActualManifest |
        ForEach-Object {
            $Prefix = if ($_.SideIndicator -eq "<=") { "MISSING" } else { "EXTRA" }
            "$Prefix $($_.InputObject)"
        })

    if ($ExitCode -ne $ExpectedExitCode) {
        $Diff += "SCRIPT_EXIT_CODE expected=$ExpectedExitCode actual=$ExitCode"
    }

    $Diff += Test-ExpectedLogAssertions -CaseRoot $Case.FullName -AppRoot $AppRoot -CaseResult $CaseResult
    $Diff += Test-ExpectedZipEntries -CaseRoot $Case.FullName -ActualDataRoot $ActualData

    Write-Lines -Path (Join-Path $CaseResult "diff.txt") -Lines $Diff

    if ($Diff.Count -gt 0) {
        Write-Host "FAIL $CaseName"
        $Diff | ForEach-Object { Write-Host "  $_" }
        return $false
    }

    Write-Host "PASS $CaseName"
    return $true
}

function ConvertTo-CanonicalJson {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) |
        ConvertTo-Json -Depth 30 -Compress
}

function Invoke-WizardTestCase {
    param(
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo]$Case
    )

    $CaseName = $Case.Name
    $CaseResult = Join-Path $ResultsRoot "wizard-$CaseName"
    $ActualConfig = Join-Path $CaseResult "config.json"
    $ActualTaskConfig = Join-Path $CaseResult "scheduled-task.json"
    $InputFile = Join-Path $Case.FullName "input.txt"
    $ExpectedConfig = Join-Path $Case.FullName "expected-config.json"
    $ExpectedTaskConfig = Join-Path $Case.FullName "expected-task-config.json"
    $RunOutputPath = Join-Path $CaseResult "run-output.log"

    if (Test-Path -LiteralPath $CaseResult) {
        Remove-Item -LiteralPath $CaseResult -Recurse -Force
    }

    New-Item -ItemType Directory -Path $CaseResult -Force | Out-Null

    $RunOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectRoot "Start-ConfigWizard.ps1") -ConfigFile $ActualConfig -TaskConfigFile $ActualTaskConfig -InputFile $InputFile 2>&1
    $ExitCode = $LASTEXITCODE
    Write-Lines -Path $RunOutputPath -Lines @($RunOutput | ForEach-Object { [string]$_ })

    $Diff = @()

    if ($ExitCode -ne 0) {
        $Diff += "WIZARD_EXIT_CODE $ExitCode"
    }

    if ((Test-Path -LiteralPath $ExpectedConfig -PathType Leaf) -and -not (Test-Path -LiteralPath $ActualConfig -PathType Leaf)) {
        $Diff += "WIZARD_CONFIG_MISSING $ActualConfig"
    }
    elseif (Test-Path -LiteralPath $ExpectedConfig -PathType Leaf) {
        $ExpectedJson = ConvertTo-CanonicalJson -Path $ExpectedConfig
        $ActualJson = ConvertTo-CanonicalJson -Path $ActualConfig

        if ($ExpectedJson -ne $ActualJson) {
            $Diff += "WIZARD_JSON_MISMATCH"
            Write-Lines -Path (Join-Path $CaseResult "expected-canonical.json") -Lines @($ExpectedJson)
            Write-Lines -Path (Join-Path $CaseResult "actual-canonical.json") -Lines @($ActualJson)
        }
    }

    if ((Test-Path -LiteralPath $ExpectedTaskConfig -PathType Leaf) -and -not (Test-Path -LiteralPath $ActualTaskConfig -PathType Leaf)) {
        $Diff += "WIZARD_TASK_CONFIG_MISSING $ActualTaskConfig"
    }
    elseif (Test-Path -LiteralPath $ExpectedTaskConfig -PathType Leaf) {
        $ExpectedTaskJson = ConvertTo-CanonicalJson -Path $ExpectedTaskConfig
        $ActualTaskJson = ConvertTo-CanonicalJson -Path $ActualTaskConfig

        if ($ExpectedTaskJson -ne $ActualTaskJson) {
            $Diff += "WIZARD_TASK_JSON_MISMATCH"
            Write-Lines -Path (Join-Path $CaseResult "expected-task-canonical.json") -Lines @($ExpectedTaskJson)
            Write-Lines -Path (Join-Path $CaseResult "actual-task-canonical.json") -Lines @($ActualTaskJson)
        }
    }

    Write-Lines -Path (Join-Path $CaseResult "diff.txt") -Lines $Diff

    if ($Diff.Count -gt 0) {
        Write-Host "FAIL wizard-$CaseName"
        $Diff | ForEach-Object { Write-Host "  $_" }
        return $false
    }

    Write-Host "PASS wizard-$CaseName"
    return $true
}

function Invoke-SingleFileBuildTest {
    $CaseName = "single-file-build"
    $CaseResult = Join-Path $ResultsRoot $CaseName
    $BuildOutput = Join-Path $CaseResult "dist"
    $PackageRoot = Join-Path $BuildOutput "files-archive-test"
    $PortableScript = Join-Path $PackageRoot "FileArchive.Portable.ps1"
    $Diff = @()

    if (Test-Path -LiteralPath $CaseResult) {
        Remove-Item -LiteralPath $CaseResult -Recurse -Force
    }

    New-Item -ItemType Directory -Path $CaseResult -Force | Out-Null

    $BuildOutputText = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectRoot "build/Build-SingleFile.ps1") -Version "test" -OutputDirectory $BuildOutput 2>&1
    $BuildExitCode = $LASTEXITCODE
    Write-Lines -Path (Join-Path $CaseResult "build-output.log") -Lines @($BuildOutputText | ForEach-Object { [string]$_ })

    if ($BuildExitCode -ne 0) {
        $Diff += "BUILD_EXIT_CODE $BuildExitCode"
    }

    if (-not (Test-Path -LiteralPath $PortableScript -PathType Leaf)) {
        $Diff += "PORTABLE_SCRIPT_MISSING $PortableScript"
    }

    if (-not (Test-Path -LiteralPath (Join-Path $BuildOutput "files-archive-test.zip") -PathType Leaf)) {
        $Diff += "PORTABLE_ZIP_MISSING"
    }

    if ($Diff.Count -eq 0) {
        $ExtractDir = Join-Path $CaseResult "extracted"
        $ExtractOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File $PortableScript -Mode Extract -ExtractTo $ExtractDir 2>&1
        $ExtractExitCode = $LASTEXITCODE
        Write-Lines -Path (Join-Path $CaseResult "extract-output.log") -Lines @($ExtractOutput | ForEach-Object { [string]$_ })

        if ($ExtractExitCode -ne 0) {
            $Diff += "EXTRACT_EXIT_CODE $ExtractExitCode"
        }

        foreach ($ExpectedFile in @("Start-FileArchive.ps1", "Start-ConfigWizard.ps1", "Register-FileArchiveScheduledTask.ps1", "archive-lib/Archive.Run.ps1")) {
            if (-not (Test-Path -LiteralPath (Join-Path $ExtractDir $ExpectedFile) -PathType Leaf)) {
                $Diff += "EXTRACT_FILE_MISSING $ExpectedFile"
            }
        }
    }

    if ($Diff.Count -eq 0) {
        $ArchiveRunDir = Join-Path $CaseResult "archive-run"
        New-Item -ItemType Directory -Path (Join-Path $ArchiveRunDir "data/Source") -Force | Out-Null

        @"
{
  "Defaults": {
    "OlderThanSeconds": 86400,
    "DateField": "LastWriteTime",
    "Extensions": [".txt"],
    "ArchiveFolder": "Archive",
    "TestMode": false
  },
  "Targets": [
    {
      "Name": "PortableSource",
      "Path": "data/Source",
      "Enabled": true
    }
  ]
}
"@ | Set-Content -LiteralPath (Join-Path $ArchiveRunDir "config.json") -Encoding UTF8

        Set-Content -LiteralPath (Join-Path $ArchiveRunDir "data/Source/old.txt") -Value "portable archive test" -Encoding UTF8
        $OldFile = Get-Item -LiteralPath (Join-Path $ArchiveRunDir "data/Source/old.txt")
        $OldFile.LastWriteTimeUtc = ([datetime]::Parse("2020-01-01T00:00:00Z")).ToUniversalTime()

        $ArchiveOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File $PortableScript -Mode Archive -ConfigFile (Join-Path $ArchiveRunDir "config.json") 2>&1
        $ArchiveExitCode = $LASTEXITCODE
        Write-Lines -Path (Join-Path $CaseResult "portable-archive-output.log") -Lines @($ArchiveOutput | ForEach-Object { [string]$_ })

        if ($ArchiveExitCode -ne 0) {
            $Diff += "PORTABLE_ARCHIVE_EXIT_CODE $ArchiveExitCode"
        }

        if (-not (Test-Path -LiteralPath (Join-Path $ArchiveRunDir "data/Source/Archive/2020/old.txt") -PathType Leaf)) {
            $Diff += "PORTABLE_ARCHIVE_FILE_NOT_MOVED"
        }
    }

    if ($Diff.Count -eq 0) {
        $WizardRunDir = Join-Path $CaseResult "wizard-run"
        New-Item -ItemType Directory -Path $WizardRunDir -Force | Out-Null
        $WizardInput = Join-Path $WizardRunDir "input.txt"
        Write-Lines -Path $WizardInput -Lines @("1", "8", "0")

        $WizardOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File $PortableScript -Mode Wizard -ConfigFile (Join-Path $WizardRunDir "config.json") -InputFile $WizardInput 2>&1
        $WizardExitCode = $LASTEXITCODE
        Write-Lines -Path (Join-Path $CaseResult "portable-wizard-output.log") -Lines @($WizardOutput | ForEach-Object { [string]$_ })

        if ($WizardExitCode -ne 0) {
            $Diff += "PORTABLE_WIZARD_EXIT_CODE $WizardExitCode"
        }

        if (-not (Test-Path -LiteralPath (Join-Path $WizardRunDir "config.json") -PathType Leaf)) {
            $Diff += "PORTABLE_WIZARD_CONFIG_MISSING"
        }
    }

    if ($Diff.Count -eq 0) {
        $MenuArchiveRunDir = Join-Path $CaseResult "menu-archive-run"
        New-Item -ItemType Directory -Path (Join-Path $MenuArchiveRunDir "data/Source") -Force | Out-Null

        @"
{
  "Defaults": {
    "OlderThanSeconds": 86400,
    "DateField": "LastWriteTime",
    "Extensions": [".txt"],
    "ArchiveFolder": "Archive",
    "TestMode": false
  },
  "Targets": [
    {
      "Name": "PortableMenuSource",
      "Path": "data/Source",
      "Enabled": true
    }
  ]
}
"@ | Set-Content -LiteralPath (Join-Path $MenuArchiveRunDir "config.json") -Encoding UTF8

        Set-Content -LiteralPath (Join-Path $MenuArchiveRunDir "data/Source/old-menu.txt") -Value "portable menu archive test" -Encoding UTF8
        $OldMenuFile = Get-Item -LiteralPath (Join-Path $MenuArchiveRunDir "data/Source/old-menu.txt")
        $OldMenuFile.LastWriteTimeUtc = ([datetime]::Parse("2020-01-01T00:00:00Z")).ToUniversalTime()

        $MenuArchiveInput = Join-Path $MenuArchiveRunDir "input.txt"
        Write-Lines -Path $MenuArchiveInput -Lines @("1")

        $MenuArchiveOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File $PortableScript -ConfigFile (Join-Path $MenuArchiveRunDir "config.json") -InputFile $MenuArchiveInput 2>&1
        $MenuArchiveExitCode = $LASTEXITCODE
        $MenuArchiveOutputLines = @($MenuArchiveOutput | ForEach-Object { [string]$_ })
        Write-Lines -Path (Join-Path $CaseResult "portable-menu-archive-output.log") -Lines $MenuArchiveOutputLines

        if ($MenuArchiveExitCode -ne 0) {
            $Diff += "PORTABLE_MENU_ARCHIVE_EXIT_CODE $MenuArchiveExitCode"
        }

        if (-not ($MenuArchiveOutputLines -contains "Pokrecem archive script:")) {
            $Diff += "PORTABLE_MENU_ARCHIVE_START_MESSAGE_MISSING"
        }

        if (-not ($MenuArchiveOutputLines -contains "Archive run zavrseno uspjesno.")) {
            $Diff += "PORTABLE_MENU_ARCHIVE_SUCCESS_MESSAGE_MISSING"
        }

        if (-not (Test-Path -LiteralPath (Join-Path $MenuArchiveRunDir "data/Source/Archive/2020/old-menu.txt") -PathType Leaf)) {
            $Diff += "PORTABLE_MENU_ARCHIVE_FILE_NOT_MOVED"
        }
    }

    if ($Diff.Count -eq 0) {
        $MenuTaskRunDir = Join-Path $CaseResult "menu-task-run"
        New-Item -ItemType Directory -Path $MenuTaskRunDir -Force | Out-Null
        $MenuTaskInput = Join-Path $MenuTaskRunDir "input.txt"
        Write-Lines -Path $MenuTaskInput -Lines @("3")

        $MenuTaskOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File $PortableScript -ConfigFile (Join-Path $MenuTaskRunDir "config.json") -TaskConfigFile (Join-Path $MenuTaskRunDir "missing-scheduled-task.json") -InputFile $MenuTaskInput 2>&1
        $MenuTaskExitCode = $LASTEXITCODE
        $MenuTaskOutputLines = @($MenuTaskOutput | ForEach-Object { [string]$_ })
        Write-Lines -Path (Join-Path $CaseResult "portable-menu-task-output.log") -Lines $MenuTaskOutputLines

        if ($MenuTaskExitCode -eq 0) {
            $Diff += "PORTABLE_MENU_TASK_EXPECTED_FAILURE_NOT_RETURNED"
        }

        if (-not ($MenuTaskOutputLines -contains "Pokrecem Windows Task Scheduler registraciju:")) {
            $Diff += "PORTABLE_MENU_TASK_START_MESSAGE_MISSING"
        }

        if (-not ($MenuTaskOutputLines -match "Task Scheduler registration nije uspjelo|Task Scheduler registration greska")) {
            $Diff += "PORTABLE_MENU_TASK_FAILURE_MESSAGE_MISSING"
        }
    }

    if ($Diff.Count -eq 0) {
        $MenuRunDir = Join-Path $CaseResult "menu-run"
        New-Item -ItemType Directory -Path $MenuRunDir -Force | Out-Null
        $MenuInput = Join-Path $MenuRunDir "input.txt"
        Write-Lines -Path $MenuInput -Lines @("2", "1", "8", "0")

        $MenuOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File $PortableScript -ConfigFile (Join-Path $MenuRunDir "config.json") -InputFile $MenuInput 2>&1
        $MenuExitCode = $LASTEXITCODE
        $MenuOutputLines = @($MenuOutput | ForEach-Object { [string]$_ })
        Write-Lines -Path (Join-Path $CaseResult "portable-menu-output.log") -Lines $MenuOutputLines

        if ($MenuExitCode -ne 0) {
            $Diff += "PORTABLE_MENU_EXIT_CODE $MenuExitCode"
        }

        if (-not ($MenuOutputLines -contains "Odaberi akciju:")) {
            $Diff += "PORTABLE_MENU_NOT_SHOWN"
        }

        if (-not ($MenuOutputLines -contains "  2) Build/edit config wizard")) {
            $Diff += "PORTABLE_MENU_WIZARD_OPTION_MISSING"
        }

        if (-not (Test-Path -LiteralPath (Join-Path $MenuRunDir "config.json") -PathType Leaf)) {
            $Diff += "PORTABLE_MENU_WIZARD_CONFIG_MISSING"
        }
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

if (Test-Path -LiteralPath $WizardCasesRoot -PathType Container) {
    $WizardCases = @(Get-ChildItem -LiteralPath $WizardCasesRoot -Directory | Sort-Object Name)

    foreach ($WizardCase in $WizardCases) {
        if (-not (Invoke-WizardTestCase -Case $WizardCase)) {
            $Failed++
        }
    }
}

if (-not (Invoke-SingleFileBuildTest)) {
    $Failed++
}

if ($Failed -gt 0) {
    Write-Host "$Failed testova je palo. Detalji su u tests/test_results."
    exit 1
}

if (Test-Path -LiteralPath $ResultsRoot) {
    Remove-Item -LiteralPath $ResultsRoot -Recurse -Force
}

Write-Host "Svi testovi su prosli."
