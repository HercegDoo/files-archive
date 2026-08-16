param(
    [string]$ConfigFile,
    [string]$LogFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# Osnovne putanje
# ============================================================

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
    $ConfigFile = Join-Path $ScriptRoot "config.json"
}

if ([string]::IsNullOrWhiteSpace($LogFile)) {
    $LogFile = Join-Path $ScriptRoot "Logs\FileArchive.log"
}

$LibRoot = Join-Path $ScriptRoot "archive-lib"

# Vrijednosti koje se koriste kada nisu navedene u config.json
$BuiltInDefaults = [PSCustomObject]@{
    OlderThanSeconds = 31536000
    OlderThanDays    = $null
    DateField        = "LastWriteTime"
    Extensions       = @(".txt")
    MaxDepth         = $null
    MaxFilesPerRun   = $null
    DeleteEmptyFolders = $true
    ProtectedEmptyFolders = @()
    ArchiveFolder    = "Arhiva"
    ArchivePath      = $null
    ArchiveZipEnabled = $false
    ArchiveZipAfter = $null
    ArchiveZipGroupBy = "year"
    RetentionEnabled = $false
    RetentionYears = $null
    RetentionAction = "delete"
    SecondaryStorage = $null
    MaxLogSizeMB     = 10
    LogRotateCount   = 5
    TestMode         = $false
}

# ============================================================
# Ucitavanje pomocnih funkcija
# ============================================================

$RequiredScripts = @(
    "Archive.Logging.ps1"
    "Archive.Config.ps1"
    "Archive.Files.ps1"
    "Archive.Maintenance.ps1"
    "Archive.Settings.ps1"
    "Archive.Run.ps1"
)

foreach ($ScriptName in $RequiredScripts) {
    $ScriptPath = Join-Path $LibRoot $ScriptName

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "Pomocni fajl ne postoji: $ScriptPath"
    }

    . $ScriptPath
}

# ============================================================
# Glavni tok
# ============================================================

try {
    $RunParams = @{
        ConfigFile      = $ConfigFile
        LogFile         = $LogFile
        BuiltInDefaults = $BuiltInDefaults
    }

    $Totals = Invoke-ArchiveRun @RunParams

    if ($Totals.Errors -gt 0) {
        exit 1
    }

    exit 0
}
catch {
    Write-ArchiveLog "KRITICNA GRESKA: $($_.Exception.Message)" -LogFile $LogFile
    exit 1
}
