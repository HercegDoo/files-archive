param(
    [string]$Version = "dev",
    [string]$OutputDirectory,
    [switch]$NoZip
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $ProjectRoot "dist"
}

$PackageName = "files-archive-$Version"
$PackageRoot = Join-Path $OutputDirectory $PackageName
$PortableScript = Join-Path $PackageRoot "FileArchive.Portable.ps1"
$ZipPath = Join-Path $OutputDirectory "$PackageName.zip"

$RuntimeFiles = @(
    "Start-FileArchive.ps1",
    "Start-ConfigWizard.ps1",
    "Register-FileArchiveScheduledTask.ps1",
    "README.md",
    "archive-lib/Archive.Logging.ps1",
    "archive-lib/Archive.Config.ps1",
    "archive-lib/Archive.Files.ps1",
    "archive-lib/Archive.Maintenance.ps1",
    "archive-lib/Archive.Settings.ps1",
    "archive-lib/Archive.Run.ps1"
)

function Get-FileText {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    return Get-Content -LiteralPath (Join-Path $ProjectRoot $RelativePath) -Raw -Encoding UTF8
}

function Get-FileBase64 {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    $Bytes = [System.IO.File]::ReadAllBytes((Join-Path $ProjectRoot $RelativePath))
    return [Convert]::ToBase64String($Bytes)
}

function ConvertTo-SingleQuotedPowerShellString {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    return "'" + $Value.Replace("'", "''") + "'"
}

if (Test-Path -LiteralPath $PackageRoot) {
    Remove-Item -LiteralPath $PackageRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $PackageRoot -Force | Out-Null

$EmbeddedFileLines = @()

foreach ($RuntimeFile in $RuntimeFiles) {
    $EmbeddedFileLines += "    $(ConvertTo-SingleQuotedPowerShellString $RuntimeFile) = $(ConvertTo-SingleQuotedPowerShellString (Get-FileBase64 -RelativePath $RuntimeFile))"
}

$ArchiveLibrary = @(
    Get-FileText "archive-lib/Archive.Logging.ps1"
    Get-FileText "archive-lib/Archive.Config.ps1"
    Get-FileText "archive-lib/Archive.Files.ps1"
    Get-FileText "archive-lib/Archive.Maintenance.ps1"
    Get-FileText "archive-lib/Archive.Settings.ps1"
    Get-FileText "archive-lib/Archive.Run.ps1"
) -join [Environment]::NewLine

$GeneratedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$EmbeddedFilesBlock = $EmbeddedFileLines -join [Environment]::NewLine

$PortableContent = @"
param(
    [ValidateSet("Menu", "Archive", "Wizard", "RegisterTask", "Extract")]
    [string]`$Mode = "Menu",

    [string]`$ConfigFile,
    [string]`$TaskConfigFile,
    [string]`$InputFile,
    [string]`$ExtractTo,
    [switch]`$WhatIf
)

Set-StrictMode -Version Latest
`$ErrorActionPreference = "Stop"

`$PortableVersion = $(ConvertTo-SingleQuotedPowerShellString $Version)
`$PortableGeneratedAt = $(ConvertTo-SingleQuotedPowerShellString $GeneratedAt)
`$PortableScriptPath = `$MyInvocation.MyCommand.Path
`$PortableRoot = Split-Path -Parent `$PortableScriptPath
`$script:PortableInputLines = @()
`$script:PortableInputIndex = 0
`$script:PortableInputMode = -not [string]::IsNullOrWhiteSpace(`$InputFile)

if ([string]::IsNullOrWhiteSpace(`$ConfigFile)) {
    `$ConfigFile = Join-Path `$PortableRoot "config.json"
}

if ([string]::IsNullOrWhiteSpace(`$TaskConfigFile)) {
    `$TaskConfigFile = Join-Path `$PortableRoot "scheduled-task.json"
}

`$EmbeddedFiles = @{
$EmbeddedFilesBlock
}

if (`$script:PortableInputMode) {
    if (-not (Test-Path -LiteralPath `$InputFile -PathType Leaf)) {
        throw "Input fajl ne postoji: `$InputFile"
    }

    `$script:PortableInputLines = @(Get-Content -LiteralPath `$InputFile -Encoding UTF8)
}

function Read-PortableValue {
    param(
        [Parameter(Mandatory)]
        [string]`$Prompt,

        [AllowNull()]
        [object]`$Default = `$null
    )

    `$DefaultText = if (`$null -eq `$Default) { "" } else { [string]`$Default }
    `$PromptText = if ([string]::IsNullOrWhiteSpace(`$DefaultText)) { `$Prompt } else { "`$Prompt [`$DefaultText]" }

    if (`$script:PortableInputIndex -lt `$script:PortableInputLines.Count) {
        `$Value = [string]`$script:PortableInputLines[`$script:PortableInputIndex]
        `$script:PortableInputIndex++
        Write-Host "`${PromptText}: `$Value"

        if ([string]::IsNullOrWhiteSpace(`$Value)) {
            return `$Default
        }

        return `$Value
    }

    if (`$script:PortableInputMode) {
        return `$Default
    }

    `$EnteredValue = Read-Host `$PromptText

    if ([string]::IsNullOrWhiteSpace(`$EnteredValue)) {
        return `$Default
    }

    return `$EnteredValue
}

function New-PortableRemainingInputFile {
    if (-not `$script:PortableInputMode -or `$script:PortableInputIndex -ge `$script:PortableInputLines.Count) {
        return `$null
    }

    `$RemainingLines = @(`$script:PortableInputLines[`$script:PortableInputIndex..(`$script:PortableInputLines.Count - 1)])
    `$script:PortableInputIndex = `$script:PortableInputLines.Count
    `$RemainingInputFile = Join-Path ([System.IO.Path]::GetTempPath()) ("files-archive-portable-input-" + [guid]::NewGuid().ToString("N") + ".txt")
    Set-Content -LiteralPath `$RemainingInputFile -Value `$RemainingLines -Encoding UTF8

    return `$RemainingInputFile
}

function Get-PortablePowerShellCommand {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        return "pwsh"
    }

    return "powershell.exe"
}

function Expand-PortableRuntime {
    param(
        [Parameter(Mandatory)]
        [string]`$Destination
    )

    if (-not (Test-Path -LiteralPath `$Destination -PathType Container)) {
        New-Item -ItemType Directory -Path `$Destination -Force | Out-Null
    }

    foreach (`$RelativePath in `$EmbeddedFiles.Keys) {
        `$OutputPath = Join-Path `$Destination `$RelativePath
        `$OutputDirectory = Split-Path -Parent `$OutputPath

        if (-not (Test-Path -LiteralPath `$OutputDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path `$OutputDirectory -Force | Out-Null
        }

        [System.IO.File]::WriteAllBytes(`$OutputPath, [Convert]::FromBase64String(`$EmbeddedFiles[`$RelativePath]))
    }

    return `$Destination
}

function Get-PortableRuntimeRoot {
    return Join-Path `$PortableRoot "files-archive-runtime"
}

function Ensure-PortableRuntime {
    `$RuntimeRoot = Get-PortableRuntimeRoot
    Expand-PortableRuntime -Destination `$RuntimeRoot | Out-Null
    return `$RuntimeRoot
}

function Invoke-PortableScriptFile {
    param(
        [Parameter(Mandatory)]
        [string]`$ScriptPath,

        [string[]]`$Arguments = @()
    )

    `$PowerShellCommand = Get-PortablePowerShellCommand
    `$BaseArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", `$ScriptPath)
    `$AllArguments = `$BaseArguments + `$Arguments
    & `$PowerShellCommand @AllArguments 2>&1 | ForEach-Object { Write-Host ([string]`$_) }

    return `$LASTEXITCODE
}

$ArchiveLibrary

function Invoke-PortableArchive {
    `$RuntimeRoot = Ensure-PortableRuntime
    `$ArchiveScript = Join-Path `$RuntimeRoot "Start-FileArchive.ps1"
    `$LogFile = Join-Path `$PortableRoot "Logs/FileArchive.log"

    Write-Host "Pokrecem archive script:"
    Write-Host "  Script: `$ArchiveScript"
    Write-Host "  Config: `$ConfigFile"
    Write-Host "  Log:    `$LogFile"

    return Invoke-PortableScriptFile -ScriptPath `$ArchiveScript -Arguments @("-ConfigFile", `$ConfigFile, "-LogFile", `$LogFile)
}

function Invoke-PortableWizard {
    param(
        [AllowNull()]
        [string]`$WizardInputFile = `$InputFile
    )

    `$RuntimeRoot = Ensure-PortableRuntime
    `$PreviousRoot = `$env:FILE_ARCHIVE_PORTABLE_ROOT
    `$PreviousScript = `$env:FILE_ARCHIVE_PORTABLE_SCRIPT

    try {
        `$env:FILE_ARCHIVE_PORTABLE_ROOT = `$PortableRoot
        `$env:FILE_ARCHIVE_PORTABLE_SCRIPT = Join-Path `$RuntimeRoot "Start-FileArchive.ps1"

        `$WizardScript = Join-Path `$RuntimeRoot "Start-ConfigWizard.ps1"
        `$WizardParams = @{
            ConfigFile = `$ConfigFile
            TaskConfigFile = `$TaskConfigFile
        }

        if (-not [string]::IsNullOrWhiteSpace(`$WizardInputFile)) {
            `$WizardParams.InputFile = `$WizardInputFile
        }

        & `$WizardScript @WizardParams
        return 0
    }
    finally {
        `$env:FILE_ARCHIVE_PORTABLE_ROOT = `$PreviousRoot
        `$env:FILE_ARCHIVE_PORTABLE_SCRIPT = `$PreviousScript
    }
}

function Invoke-PortableRegisterTask {
    `$RuntimeRoot = Ensure-PortableRuntime

    try {
        `$RegisterScript = Join-Path `$RuntimeRoot "Register-FileArchiveScheduledTask.ps1"

        Write-Host "Pokrecem Windows Task Scheduler registraciju:"
        Write-Host "  Task config: `$TaskConfigFile"
        Write-Host "  Helper:      `$RegisterScript"

        `$RegisterArgs = @(
            "-ExecutionPolicy", "Bypass",
            "-File", `$RegisterScript,
            "-TaskConfigFile", `$TaskConfigFile
        )

        if (`$WhatIf) {
            `$RegisterArgs += "-WhatIf"
        }

        & powershell.exe @RegisterArgs 2>&1 | ForEach-Object { Write-Host ([string]`$_) }

        return `$LASTEXITCODE
    }
    finally {
    }
}

function Complete-PortableMenuAction {
    param(
        [Parameter(Mandatory)]
        [string]`$ActionName,

        [int]`$ExitCode
    )

    if (`$ExitCode -eq 0) {
        Write-Host "`$ActionName zavrseno uspjesno."
    }
    else {
        Write-Host "`$ActionName nije uspjelo. ExitCode: `$ExitCode"
        Write-Host "Provjeri output iznad i log/config putanje prikazane u meniju."
    }

    if (`$script:PortableInputMode) {
        return
    }

    [void](Read-Host "Pritisni Enter za povratak u meni")
}

function Invoke-PortableMenuAction {
    param(
        [Parameter(Mandatory)]
        [string]`$ActionName,

        [Parameter(Mandatory)]
        [scriptblock]`$Action
    )

    try {
        `$ExitCode = [int](& `$Action)
    }
    catch {
        `$ExitCode = 1
        Write-Host "`$ActionName greska: `$(`$_.Exception.Message)"
    }

    Complete-PortableMenuAction -ActionName `$ActionName -ExitCode `$ExitCode

    if (`$script:PortableInputMode) {
        return `$ExitCode
    }

    return 0
}

function Invoke-PortableExtract {
    param(
        [AllowNull()]
        [string]`$Destination = `$ExtractTo
    )

    if ([string]::IsNullOrWhiteSpace(`$Destination)) {
        `$Destination = Join-Path `$PortableRoot "files-archive-runtime"
    }

    Expand-PortableRuntime -Destination `$Destination | Out-Null
    Write-Host "Portable runtime extracted: `$Destination"
    return 0
}

function Show-PortableStatus {
    `$StatusLogFile = Join-Path `$PortableRoot "Logs/FileArchive.log"

    Write-Host ""
    Write-Host "File Archive Portable"
    Write-Host "Version:          `$PortableVersion"
    Write-Host "Portable root:    `$PortableRoot"
    Write-Host "Config file:      `$ConfigFile"
    Write-Host "Task config file: `$TaskConfigFile"
    Write-Host "Log file:         `$StatusLogFile"
    Write-Host ""
}

function Invoke-PortableMenu {
    while (`$true) {
        Show-PortableStatus
        Write-Host "Odaberi akciju:"
        Write-Host "  1) Run archive script"
        Write-Host "  2) Build/edit config wizard"
        Write-Host "  3) Register/update Windows Task Scheduler"
        Write-Host "  4) Extract runtime files"
        Write-Host "  5) Show paths/status"
        Write-Host "  0) Exit"

        `$Choice = [string](Read-PortableValue -Prompt "Choice" -Default "0")

        switch (`$Choice.Trim()) {
            "1" {
                `$ExitCode = Invoke-PortableMenuAction -ActionName "Archive run" -Action { Invoke-PortableArchive }

                if (`$script:PortableInputMode) {
                    return `$ExitCode
                }
            }
            "2" {
                `$RemainingInputFile = New-PortableRemainingInputFile

                try {
                    `$ExitCode = Invoke-PortableWizard -WizardInputFile `$RemainingInputFile
                }
                finally {
                    if (-not [string]::IsNullOrWhiteSpace(`$RemainingInputFile) -and (Test-Path -LiteralPath `$RemainingInputFile -PathType Leaf)) {
                        Remove-Item -LiteralPath `$RemainingInputFile -Force
                    }
                }

                Complete-PortableMenuAction -ActionName "Config wizard" -ExitCode `$ExitCode

                if (`$script:PortableInputMode) {
                    return `$ExitCode
                }
            }
            "3" {
                `$ExitCode = Invoke-PortableMenuAction -ActionName "Task Scheduler registration" -Action { Invoke-PortableRegisterTask }

                if (`$script:PortableInputMode) {
                    return `$ExitCode
                }
            }
            "4" {
                `$Destination = Read-PortableValue -Prompt "Extract destination" -Default (Join-Path `$PortableRoot "files-archive-runtime")
                `$ExitCode = Invoke-PortableExtract -Destination `$Destination

                Complete-PortableMenuAction -ActionName "Runtime extract" -ExitCode `$ExitCode

                if (`$script:PortableInputMode) {
                    return `$ExitCode
                }
            }
            "5" {
                Show-PortableStatus

                if (`$script:PortableInputMode) {
                    return 0
                }

                [void](Read-Host "Pritisni Enter za povratak u meni")
            }
            "0" {
                return 0
            }
            default {
                Write-Host "Nepoznata opcija: `$Choice"

                if (`$script:PortableInputMode) {
                    return 1
                }
            }
        }
    }
}

switch (`$Mode) {
    "Menu" {
        exit (Invoke-PortableMenu)
    }
    "Archive" {
        exit (Invoke-PortableArchive)
    }
    "Wizard" {
        exit (Invoke-PortableWizard)
    }
    "RegisterTask" {
        exit (Invoke-PortableRegisterTask)
    }
    "Extract" {
        exit (Invoke-PortableExtract)
    }
}
"@

Set-Content -LiteralPath $PortableScript -Value $PortableContent -Encoding UTF8

$ReadmePath = Join-Path $PackageRoot "README.PORTABLE.txt"
$Readme = @"
File Archive Portable Package
Version: $Version
Generated: $GeneratedAt

Main file:
  FileArchive.Portable.ps1

On first use, the portable script unpacks runtime files into:
  files-archive-runtime

Default interactive menu:
  powershell.exe -ExecutionPolicy Bypass -File .\FileArchive.Portable.ps1

Run archive:
  powershell.exe -ExecutionPolicy Bypass -File .\FileArchive.Portable.ps1 -Mode Archive

Run wizard:
  powershell.exe -ExecutionPolicy Bypass -File .\FileArchive.Portable.ps1 -Mode Wizard

Register/update Windows Scheduled Task:
  powershell.exe -ExecutionPolicy Bypass -File .\FileArchive.Portable.ps1 -Mode RegisterTask

Extract normal runtime files:
  powershell.exe -ExecutionPolicy Bypass -File .\FileArchive.Portable.ps1 -Mode Extract -ExtractTo .\runtime

Expected config files next to the portable script:
  config.json
  scheduled-task.json
"@

Set-Content -LiteralPath $ReadmePath -Value $Readme -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $ProjectRoot "README.md") -Destination (Join-Path $PackageRoot "README.md") -Force

if (-not $NoZip) {
    if (Test-Path -LiteralPath $ZipPath -PathType Leaf) {
        Remove-Item -LiteralPath $ZipPath -Force
    }

    Compress-Archive -LiteralPath $PackageRoot -DestinationPath $ZipPath -Force
}

Write-Host "Portable script: $PortableScript"

if (-not $NoZip) {
    Write-Host "Portable zip: $ZipPath"
}
