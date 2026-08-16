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
    $Properties.DateField = "LastWriteTime"
    $Properties.Extensions = @(".txt")
    $Properties.MaxDepth = $null
    $Properties.MaxFilesPerRun = $null
    $Properties.ArchiveFolder = "Arhiva"
    $Properties.ArchivePath = $null
    $Properties.ArchiveZipEnabled = $false
    $Properties.ArchiveZipAfter = $null
    $Properties.ArchiveZipGroupBy = "year"
    $Properties.RetentionEnabled = $false
    $Properties.RetentionYears = $null
    $Properties.RetentionAction = "delete"
    $Properties.SecondaryStorage = $null
    $Properties.MaxLogSizeMB = 10
    $Properties.LogRotateCount = 5
    $Properties.TestMode = $false

    $Settings = [PSCustomObject]$Properties

    return Update-ArchiveSettings -Settings $Settings -Source $Source -IncludeEnabled:$IncludeEnabled
}

function ConvertTo-ArchiveMaxDepth {
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$PropertyName
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    $Depth = [double]$Value

    if ($Depth -lt 0 -or $Depth -ne [math]::Floor($Depth)) {
        throw "$PropertyName mora biti cijeli broj veci ili jednak 0."
    }

    return [int]$Depth
}

function ConvertTo-ArchiveMaxFilesPerRun {
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$PropertyName
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    $Limit = [double]$Value

    if ($Limit -lt 1 -or $Limit -ne [math]::Floor($Limit)) {
        throw "$PropertyName mora biti cijeli broj veci ili jednak 1."
    }

    return [int]$Limit
}

function ConvertTo-ArchivePositiveNumber {
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$PropertyName
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    $Number = [double]$Value

    if ($Number -le 0) {
        throw "$PropertyName mora biti veci od 0."
    }

    return $Number
}

function ConvertTo-ArchiveZipGroupBy {
    param(
        [Parameter(Mandatory)]
        [object]$Value
    )

    $GroupBy = ([string]$Value).Trim().ToLowerInvariant()

    switch ($GroupBy) {
        "year" { return "year" }
        "month" { return "month" }
        default { throw "ArchiveZipGroupBy mora biti 'year' ili 'month'. Vrijednost: $Value" }
    }
}

function ConvertTo-RetentionAction {
    param(
        [Parameter(Mandatory)]
        [object]$Value
    )

    $Action = ([string]$Value).Trim().ToLowerInvariant()

    switch ($Action) {
        "delete" { return "delete" }
        "move" { return "move" }
        default { throw "RetentionAction mora biti 'delete' ili 'move'. Vrijednost: $Value" }
    }
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

    if (Test-ConfigProperty $Source "DateField") {
        $DateField = ([string]$Source.DateField).Trim()

        switch -Regex ($DateField) {
            "^(LastWriteTime|Modified|ModificationTime)$" {
                $Settings.DateField = "LastWriteTime"
                break
            }
            "^(CreationTime|Created|CreateTime)$" {
                $Settings.DateField = "CreationTime"
                break
            }
            default {
                throw "DateField mora biti 'LastWriteTime' ili 'CreationTime'. Vrijednost: $DateField"
            }
        }
    }

    if (Test-ConfigProperty $Source "Extensions") {
        $Settings.Extensions = @($Source.Extensions)
    }

    if (Test-ConfigProperty $Source "MaxNestedDepth") {
        $Settings.MaxDepth = ConvertTo-ArchiveMaxDepth -Value $Source.MaxNestedDepth -PropertyName "MaxNestedDepth"
    }

    if (Test-ConfigProperty $Source "MaxDepth") {
        $Settings.MaxDepth = ConvertTo-ArchiveMaxDepth -Value $Source.MaxDepth -PropertyName "MaxDepth"
    }

    if (Test-ConfigProperty $Source "max_files_per_run") {
        $Settings.MaxFilesPerRun = ConvertTo-ArchiveMaxFilesPerRun -Value $Source.max_files_per_run -PropertyName "max_files_per_run"
    }

    if (Test-ConfigProperty $Source "MaxFilesPerRun") {
        $Settings.MaxFilesPerRun = ConvertTo-ArchiveMaxFilesPerRun -Value $Source.MaxFilesPerRun -PropertyName "MaxFilesPerRun"
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

    if (Test-ConfigProperty $Source "archive_zip_enabled") {
        $Settings.ArchiveZipEnabled = [bool]$Source.archive_zip_enabled
    }

    if (Test-ConfigProperty $Source "ArchiveZipEnabled") {
        $Settings.ArchiveZipEnabled = [bool]$Source.ArchiveZipEnabled
    }

    if (Test-ConfigProperty $Source "archive_zip_after") {
        $Settings.ArchiveZipAfter = $Source.archive_zip_after
    }

    if (Test-ConfigProperty $Source "ArchiveZipAfter") {
        $Settings.ArchiveZipAfter = $Source.ArchiveZipAfter
    }

    if (Test-ConfigProperty $Source "ArchiveZipAfterYears") {
        $Settings.ArchiveZipAfter = "$($Source.ArchiveZipAfterYears) years"
    }

    if (Test-ConfigProperty $Source "archive_zip_group_by") {
        $Settings.ArchiveZipGroupBy = ConvertTo-ArchiveZipGroupBy -Value $Source.archive_zip_group_by
    }

    if (Test-ConfigProperty $Source "ArchiveZipGroupBy") {
        $Settings.ArchiveZipGroupBy = ConvertTo-ArchiveZipGroupBy -Value $Source.ArchiveZipGroupBy
    }

    if (Test-ConfigProperty $Source "retention_enabled") {
        $Settings.RetentionEnabled = [bool]$Source.retention_enabled
    }

    if (Test-ConfigProperty $Source "RetentionEnabled") {
        $Settings.RetentionEnabled = [bool]$Source.RetentionEnabled
    }

    if (Test-ConfigProperty $Source "retention_years") {
        $Settings.RetentionYears = ConvertTo-ArchivePositiveNumber -Value $Source.retention_years -PropertyName "retention_years"
    }

    if (Test-ConfigProperty $Source "RetentionYears") {
        $Settings.RetentionYears = ConvertTo-ArchivePositiveNumber -Value $Source.RetentionYears -PropertyName "RetentionYears"
    }

    if (Test-ConfigProperty $Source "retention_action") {
        $Settings.RetentionAction = ConvertTo-RetentionAction -Value $Source.retention_action
    }

    if (Test-ConfigProperty $Source "RetentionAction") {
        $Settings.RetentionAction = ConvertTo-RetentionAction -Value $Source.RetentionAction
    }

    if (Test-ConfigProperty $Source "secondary_storage") {
        $Settings.SecondaryStorage = [string]$Source.secondary_storage
    }

    if (Test-ConfigProperty $Source "SecondaryStorage") {
        $Settings.SecondaryStorage = [string]$Source.SecondaryStorage
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

    if (Test-ConfigProperty $Source "DryRun") {
        $Settings.TestMode = [bool]$Source.DryRun
    }

    if (Test-ConfigProperty $Source "dry_run") {
        $Settings.TestMode = [bool]$Source.dry_run
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
    $Settings = Update-ArchiveSettings -Settings $Settings -Source $Config

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
