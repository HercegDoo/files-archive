function New-ArchiveSettings {
    param(
        [Parameter(Mandatory)]
        [object]$Source,

        [switch]$IncludeEnabled
    )

    $Properties = [ordered]@{}

    if ($IncludeEnabled) {
        $Properties.Enabled = $true
    }

    $Properties.OlderThanSeconds = 31536000
    $Properties.OlderThanDays = $null
    $Properties.Extensions = @(".txt")
    $Properties.ArchiveFolder = "Arhiva"
    $Properties.ArchivePath = $null
    $Properties.MaxLogSizeMB = 10
    $Properties.LogRotateCount = 5
    $Properties.TestMode = $false

    $Settings = [PSCustomObject]$Properties

    return Update-ArchiveSettings -Settings $Settings -Source $Source -IncludeEnabled:$IncludeEnabled
}

function Update-ArchiveSettings {
    param(
        [Parameter(Mandatory)]
        [object]$Settings,

        [AllowNull()]
        [object]$Source,

        [switch]$IncludeEnabled
    )

    if ($null -eq $Source) {
        return $Settings
    }

    if ($IncludeEnabled -and (Test-ConfigProperty $Source "Enabled")) {
        $Settings.Enabled = [bool]$Source.Enabled
    }

    if (Test-ConfigProperty $Source "OlderThanDays") {
        $Settings.OlderThanDays = [double]$Source.OlderThanDays
        $Settings.OlderThanSeconds = $Settings.OlderThanDays * 86400
    }

    if (Test-ConfigProperty $Source "OlderThanSeconds") {
        $Settings.OlderThanSeconds = [double]$Source.OlderThanSeconds
        $Settings.OlderThanDays = $null
    }

    if (Test-ConfigProperty $Source "Extensions") {
        $Settings.Extensions = @($Source.Extensions)
    }

    if (Test-ConfigProperty $Source "ArchiveFolder") {
        $Settings.ArchiveFolder = [string]$Source.ArchiveFolder
    }

    if (Test-ConfigProperty $Source "ArchivePath") {
        if ([string]::IsNullOrWhiteSpace([string]$Source.ArchivePath)) {
            $Settings.ArchivePath = $null
        }
        else {
            $Settings.ArchivePath = [string]$Source.ArchivePath
        }
    }

    if (Test-ConfigProperty $Source "MaxLogSizeMB") {
        $Settings.MaxLogSizeMB = [double]$Source.MaxLogSizeMB
    }

    if (Test-ConfigProperty $Source "LogRotateCount") {
        $Settings.LogRotateCount = [int]$Source.LogRotateCount
    }

    if (Test-ConfigProperty $Source "TestMode") {
        $Settings.TestMode = [bool]$Source.TestMode
    }

    return $Settings
}

function Get-DefaultSettings {
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [object]$BuiltInDefaults
    )

    $Settings = New-ArchiveSettings -Source $BuiltInDefaults

    if (-not (Test-ConfigProperty $Config "Defaults")) {
        return $Settings
    }

    return Update-ArchiveSettings -Settings $Settings -Source $Config.Defaults
}

function Get-TargetSettings {
    param(
        [AllowNull()]
        [object]$TargetConfig,

        [Parameter(Mandatory)]
        [object]$Defaults
    )

    $Settings = New-ArchiveSettings -Source $Defaults -IncludeEnabled

    if ($null -eq $TargetConfig) {
        return $Settings
    }

    $UpdateParams = @{
        Settings       = $Settings
        Source         = $TargetConfig
        IncludeEnabled = $true
    }

    return Update-ArchiveSettings @UpdateParams
}
