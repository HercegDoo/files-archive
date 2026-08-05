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

    $Properties.OlderThanDays = $Source.OlderThanDays
    $Properties.Extensions = $Source.Extensions
    $Properties.ArchiveFolder = $Source.ArchiveFolder
    $Properties.TestMode = $Source.TestMode

    return [PSCustomObject]$Properties
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
    }

    if (Test-ConfigProperty $Source "Extensions") {
        $Settings.Extensions = @($Source.Extensions)
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

function Get-MachineSettings {
    param(
        [AllowNull()]
        [object]$MachineConfig,

        [Parameter(Mandatory)]
        [object]$Defaults
    )

    $Settings = New-ArchiveSettings -Source $Defaults -IncludeEnabled

    if ($null -eq $MachineConfig) {
        return $Settings
    }

    $UpdateParams = @{
        Settings       = $Settings
        Source         = $MachineConfig
        IncludeEnabled = $true
    }

    return Update-ArchiveSettings @UpdateParams
}
