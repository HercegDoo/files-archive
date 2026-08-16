param(
    [string]$ConfigFile,
    [string]$TaskConfigFile,
    [string]$InputFile,

    [ValidateSet("Menu", "TaskScheduler")]
    [string]$Mode = "Menu",

    [switch]$SkipTaskApplyPrompt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptRoot = if ([string]::IsNullOrWhiteSpace($env:FILE_ARCHIVE_PORTABLE_ROOT)) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    $env:FILE_ARCHIVE_PORTABLE_ROOT
}

if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
    $ConfigFile = Join-Path $ScriptRoot "config.json"
}

if ([string]::IsNullOrWhiteSpace($TaskConfigFile)) {
    $TaskConfigFile = Join-Path $ScriptRoot "scheduled-task.json"
}

$script:WizardInputLines = @()
$script:WizardInputIndex = 0

if (-not [string]::IsNullOrWhiteSpace($InputFile)) {
    if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
        throw "Input fajl ne postoji: $InputFile"
    }

    $script:WizardInputLines = @(Get-Content -LiteralPath $InputFile -Encoding UTF8)
}

function Read-WizardValue {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [AllowNull()]
        [object]$Default = $null
    )

    $DefaultText = if ($null -eq $Default) { "" } else { [string]$Default }
    $PromptText = if ([string]::IsNullOrWhiteSpace($DefaultText)) { $Prompt } else { "$Prompt [$DefaultText]" }

    if ($script:WizardInputIndex -lt $script:WizardInputLines.Count) {
        $Value = [string]$script:WizardInputLines[$script:WizardInputIndex]
        $script:WizardInputIndex++
        Write-Host "$PromptText`: $Value"

        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $Default
        }

        return $Value
    }

    $EnteredValue = Read-Host $PromptText

    if ([string]::IsNullOrWhiteSpace($EnteredValue)) {
        return $Default
    }

    return $EnteredValue
}

function ConvertTo-WizardNullableInt {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    return [int]$Value
}

function ConvertTo-WizardNullableDouble {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    return [double]$Value
}

function ConvertTo-WizardBool {
    param(
        [AllowNull()]
        [object]$Value,

        [bool]$Default = $false
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $Default
    }

    switch -Regex (([string]$Value).Trim().ToLowerInvariant()) {
        "^(y|yes|da|d|true|1)$" { return $true }
        "^(n|no|ne|false|0)$" { return $false }
        default { throw "Neispravna boolean vrijednost: $Value" }
    }
}

function ConvertTo-WizardStringArray {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return @()
    }

    return @(
        ([string]$Value).Split(",", [System.StringSplitOptions]::RemoveEmptyEntries) |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Set-ObjectProperty {
    param(
        [Parameter(Mandatory)]
        [object]$Object,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$Value
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
        return
    }

    Add-Member -InputObject $Object -MemberType NoteProperty -Name $Name -Value $Value
}

function New-WizardConfig {
    return [PSCustomObject]@{
        Defaults = [PSCustomObject]@{
            MaxLogSizeMB = 20
            LogRotateCount = 5
            OlderThanSeconds = 2592000
            DateField = "LastWriteTime"
            Extensions = @(".txt", ".pdf", ".docx", ".bmp")
            MaxDepth = $null
            MaxFilesPerRun = $null
            DeleteEmptyFolders = $true
            ProtectedEmptyFolders = @()
            ArchiveFolder = "Arhiva"
            ArchiveZipEnabled = $false
            ArchiveZipAfter = "1 year"
            ArchiveZipGroupBy = "year"
            RetentionEnabled = $false
            RetentionYears = 7
            RetentionAction = "delete"
            SecondaryStorage = $null
            TestMode = $true
        }
        Targets = @()
    }
}

function Import-WizardConfig {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return New-WizardConfig
    }

    $Config = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json

    if (-not ($Config.PSObject.Properties.Name -contains "Defaults")) {
        Set-ObjectProperty -Object $Config -Name "Defaults" -Value (New-WizardConfig).Defaults
    }

    if (-not ($Config.PSObject.Properties.Name -contains "Targets")) {
        Set-ObjectProperty -Object $Config -Name "Targets" -Value @()
    }

    return $Config
}

function Save-WizardConfig {
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $Directory = Split-Path -Parent $Path

    if (-not [string]::IsNullOrWhiteSpace($Directory) -and -not (Test-Path -LiteralPath $Directory -PathType Container)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $Config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
    Write-Host "Config sacuvan: $Path"
}

function New-WizardTaskConfig {
    $DefaultScriptPath = if ([string]::IsNullOrWhiteSpace($env:FILE_ARCHIVE_PORTABLE_SCRIPT)) {
        Join-Path $ScriptRoot "Start-FileArchive.ps1"
    }
    else {
        $env:FILE_ARCHIVE_PORTABLE_SCRIPT
    }

    return [PSCustomObject]@{
        TaskName = "FileArchive"
        ScriptPath = $DefaultScriptPath
        WorkingDirectory = $ScriptRoot
        ScheduleType = "Daily"
        StartTime = "02:00"
        Interval = 1
        DaysOfWeek = @("Monday")
        UserId = "SYSTEM"
        RunElevated = $true
        Enabled = $true
    }
}

function Import-WizardTaskConfig {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return New-WizardTaskConfig
    }

    $TaskConfig = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $Defaults = New-WizardTaskConfig

    foreach ($Property in $Defaults.PSObject.Properties.Name) {
        if (-not ($TaskConfig.PSObject.Properties.Name -contains $Property)) {
            Set-ObjectProperty -Object $TaskConfig -Name $Property -Value $Defaults.$Property
        }
    }

    return $TaskConfig
}

function Save-WizardTaskConfig {
    param(
        [Parameter(Mandatory)]
        [object]$TaskConfig,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $Directory = Split-Path -Parent $Path

    if (-not [string]::IsNullOrWhiteSpace($Directory) -and -not (Test-Path -LiteralPath $Directory -PathType Container)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $TaskConfig | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
    Write-Host "Task config sacuvan: $Path"
}

function Configure-ScheduledTask {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$SkipApplyPrompt
    )

    $TaskConfig = Import-WizardTaskConfig -Path $Path

    Set-ObjectProperty -Object $TaskConfig -Name "TaskName" -Value ([string](Read-WizardValue "Task name" $TaskConfig.TaskName))
    Set-ObjectProperty -Object $TaskConfig -Name "ScriptPath" -Value ([string](Read-WizardValue "Archive script path" $TaskConfig.ScriptPath))
    Set-ObjectProperty -Object $TaskConfig -Name "WorkingDirectory" -Value ([string](Read-WizardValue "Working directory" $TaskConfig.WorkingDirectory))
    Set-ObjectProperty -Object $TaskConfig -Name "ScheduleType" -Value ([string](Read-WizardValue "ScheduleType Daily/Hourly/Weekly/AtStartup" $TaskConfig.ScheduleType))
    Set-ObjectProperty -Object $TaskConfig -Name "StartTime" -Value ([string](Read-WizardValue "StartTime HH:mm" $TaskConfig.StartTime))
    Set-ObjectProperty -Object $TaskConfig -Name "Interval" -Value (ConvertTo-WizardNullableInt (Read-WizardValue "Interval" $TaskConfig.Interval))
    Set-ObjectProperty -Object $TaskConfig -Name "DaysOfWeek" -Value (ConvertTo-WizardStringArray (Read-WizardValue "DaysOfWeek comma-separated for Weekly" (@($TaskConfig.DaysOfWeek) -join ",")))
    Set-ObjectProperty -Object $TaskConfig -Name "UserId" -Value ([string](Read-WizardValue "Windows account/UserId" $TaskConfig.UserId))
    Set-ObjectProperty -Object $TaskConfig -Name "RunElevated" -Value (ConvertTo-WizardBool (Read-WizardValue "RunElevated true/false" $TaskConfig.RunElevated) $TaskConfig.RunElevated)
    Set-ObjectProperty -Object $TaskConfig -Name "Enabled" -Value (ConvertTo-WizardBool (Read-WizardValue "Task enabled true/false" $TaskConfig.Enabled) $TaskConfig.Enabled)

    Save-WizardTaskConfig -TaskConfig $TaskConfig -Path $Path

    if ($SkipApplyPrompt) {
        return
    }

    $ApplyNow = ConvertTo-WizardBool (Read-WizardValue "Register/update Windows Scheduled Task now true/false" $false) $false

    if ($ApplyNow) {
        $RegisterScript = Join-Path $ScriptRoot "Register-FileArchiveScheduledTask.ps1"
        & powershell.exe -ExecutionPolicy Bypass -File $RegisterScript -TaskConfigFile $Path
    }
}

function Get-Targets {
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    return @($Config.Targets)
}

function Set-Targets {
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [object[]]$Targets
    )

    $Config.Targets = @($Targets)
}

function Show-Targets {
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    $Targets = @(Get-Targets -Config $Config)

    if ($Targets.Count -eq 0) {
        Write-Host "Targets: nema definisanih targeta."
        return
    }

    for ($Index = 0; $Index -lt $Targets.Count; $Index++) {
        $Target = $Targets[$Index]
        $Enabled = if ($Target.PSObject.Properties.Name -contains "Enabled") { $Target.Enabled } else { $true }
        Write-Host "$($Index + 1). $($Target.Name) | Enabled=$Enabled | Path=$($Target.Path)"
    }
}

function Edit-Defaults {
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    $Defaults = $Config.Defaults
    $DefaultDeleteEmptyFolders = if ($Defaults.PSObject.Properties.Name -contains "DeleteEmptyFolders") { $Defaults.DeleteEmptyFolders } else { $true }
    $DefaultProtectedEmptyFolders = if ($Defaults.PSObject.Properties.Name -contains "ProtectedEmptyFolders") { @($Defaults.ProtectedEmptyFolders) } else { @() }

    Set-ObjectProperty -Object $Defaults -Name "MaxLogSizeMB" -Value (ConvertTo-WizardNullableDouble (Read-WizardValue "MaxLogSizeMB" $Defaults.MaxLogSizeMB))
    Set-ObjectProperty -Object $Defaults -Name "LogRotateCount" -Value (ConvertTo-WizardNullableInt (Read-WizardValue "LogRotateCount" $Defaults.LogRotateCount))
    Set-ObjectProperty -Object $Defaults -Name "OlderThanSeconds" -Value (ConvertTo-WizardNullableDouble (Read-WizardValue "OlderThanSeconds" $Defaults.OlderThanSeconds))
    Set-ObjectProperty -Object $Defaults -Name "DateField" -Value ([string](Read-WizardValue "DateField (LastWriteTime/CreationTime)" $Defaults.DateField))
    Set-ObjectProperty -Object $Defaults -Name "Extensions" -Value (ConvertTo-WizardStringArray (Read-WizardValue "Extensions comma-separated" ($Defaults.Extensions -join ",")))
    Set-ObjectProperty -Object $Defaults -Name "MaxDepth" -Value (ConvertTo-WizardNullableInt (Read-WizardValue "MaxDepth empty=unlimited" $Defaults.MaxDepth))
    Set-ObjectProperty -Object $Defaults -Name "MaxFilesPerRun" -Value (ConvertTo-WizardNullableInt (Read-WizardValue "MaxFilesPerRun empty=unlimited" $Defaults.MaxFilesPerRun))
    Set-ObjectProperty -Object $Defaults -Name "DeleteEmptyFolders" -Value (ConvertTo-WizardBool (Read-WizardValue "DeleteEmptyFolders true/false" $DefaultDeleteEmptyFolders) $DefaultDeleteEmptyFolders)
    Set-ObjectProperty -Object $Defaults -Name "ProtectedEmptyFolders" -Value (ConvertTo-WizardStringArray (Read-WizardValue "ProtectedEmptyFolders comma-separated" ($DefaultProtectedEmptyFolders -join ",")))
    Set-ObjectProperty -Object $Defaults -Name "ArchiveFolder" -Value ([string](Read-WizardValue "ArchiveFolder" $Defaults.ArchiveFolder))
    Set-ObjectProperty -Object $Defaults -Name "TestMode" -Value (ConvertTo-WizardBool (Read-WizardValue "TestMode true/false" $Defaults.TestMode) $Defaults.TestMode)

    Set-ObjectProperty -Object $Defaults -Name "ArchiveZipEnabled" -Value (ConvertTo-WizardBool (Read-WizardValue "ArchiveZipEnabled true/false" $Defaults.ArchiveZipEnabled) $Defaults.ArchiveZipEnabled)
    Set-ObjectProperty -Object $Defaults -Name "ArchiveZipAfter" -Value ([string](Read-WizardValue "ArchiveZipAfter" $Defaults.ArchiveZipAfter))
    Set-ObjectProperty -Object $Defaults -Name "ArchiveZipGroupBy" -Value ([string](Read-WizardValue "ArchiveZipGroupBy year/month" $Defaults.ArchiveZipGroupBy))

    Set-ObjectProperty -Object $Defaults -Name "RetentionEnabled" -Value (ConvertTo-WizardBool (Read-WizardValue "RetentionEnabled true/false" $Defaults.RetentionEnabled) $Defaults.RetentionEnabled)
    Set-ObjectProperty -Object $Defaults -Name "RetentionYears" -Value (ConvertTo-WizardNullableDouble (Read-WizardValue "RetentionYears" $Defaults.RetentionYears))
    Set-ObjectProperty -Object $Defaults -Name "RetentionAction" -Value ([string](Read-WizardValue "RetentionAction delete/move" $Defaults.RetentionAction))
    Set-ObjectProperty -Object $Defaults -Name "SecondaryStorage" -Value (Read-WizardValue "SecondaryStorage empty=none" $Defaults.SecondaryStorage)
}

function Read-TargetValues {
    param(
        [AllowNull()]
        [object]$ExistingTarget = $null
    )

    $ExistingName = if ($null -ne $ExistingTarget -and ($ExistingTarget.PSObject.Properties.Name -contains "Name")) { $ExistingTarget.Name } else { "" }
    $ExistingPath = if ($null -ne $ExistingTarget -and ($ExistingTarget.PSObject.Properties.Name -contains "Path")) { $ExistingTarget.Path } else { "" }
    $ExistingEnabled = if ($null -ne $ExistingTarget -and ($ExistingTarget.PSObject.Properties.Name -contains "Enabled")) { $ExistingTarget.Enabled } else { $true }
    $ExistingArchiveFolder = if ($null -ne $ExistingTarget -and ($ExistingTarget.PSObject.Properties.Name -contains "ArchiveFolder")) { $ExistingTarget.ArchiveFolder } else { "" }
    $ExistingOlderThanSeconds = if ($null -ne $ExistingTarget -and ($ExistingTarget.PSObject.Properties.Name -contains "OlderThanSeconds")) { $ExistingTarget.OlderThanSeconds } else { $null }
    $ExistingExtensions = if ($null -ne $ExistingTarget -and ($ExistingTarget.PSObject.Properties.Name -contains "Extensions")) { @($ExistingTarget.Extensions) -join "," } else { "" }
    $ExistingMaxDepth = if ($null -ne $ExistingTarget -and ($ExistingTarget.PSObject.Properties.Name -contains "MaxDepth")) { $ExistingTarget.MaxDepth } else { $null }
    $ExistingDeleteEmptyFolders = if ($null -ne $ExistingTarget -and ($ExistingTarget.PSObject.Properties.Name -contains "DeleteEmptyFolders")) { $ExistingTarget.DeleteEmptyFolders } else { $null }
    $ExistingProtectedEmptyFolders = if ($null -ne $ExistingTarget -and ($ExistingTarget.PSObject.Properties.Name -contains "ProtectedEmptyFolders")) { @($ExistingTarget.ProtectedEmptyFolders) -join "," } else { "" }

    $Target = [PSCustomObject]@{
        Name = [string](Read-WizardValue "Target name" $ExistingName)
        Path = [string](Read-WizardValue "Target path" $ExistingPath)
        Enabled = ConvertTo-WizardBool (Read-WizardValue "Enabled true/false" $ExistingEnabled) $ExistingEnabled
    }

    $ArchiveFolder = Read-WizardValue "ArchiveFolder override empty=default" $ExistingArchiveFolder
    if (-not [string]::IsNullOrWhiteSpace([string]$ArchiveFolder)) {
        Set-ObjectProperty -Object $Target -Name "ArchiveFolder" -Value ([string]$ArchiveFolder)
    }

    $OlderThanSeconds = ConvertTo-WizardNullableDouble (Read-WizardValue "OlderThanSeconds override empty=default" $ExistingOlderThanSeconds)
    if ($null -ne $OlderThanSeconds) {
        Set-ObjectProperty -Object $Target -Name "OlderThanSeconds" -Value $OlderThanSeconds
    }

    $Extensions = @(ConvertTo-WizardStringArray (Read-WizardValue "Extensions override comma-separated empty=default" $ExistingExtensions))
    if ($Extensions.Count -gt 0) {
        Set-ObjectProperty -Object $Target -Name "Extensions" -Value $Extensions
    }

    $MaxDepth = ConvertTo-WizardNullableInt (Read-WizardValue "MaxDepth override empty=default" $ExistingMaxDepth)
    if ($null -ne $MaxDepth) {
        Set-ObjectProperty -Object $Target -Name "MaxDepth" -Value $MaxDepth
    }

    $DeleteEmptyFolders = Read-WizardValue "DeleteEmptyFolders override true/false empty=default" $ExistingDeleteEmptyFolders
    if ($null -ne $DeleteEmptyFolders -and -not [string]::IsNullOrWhiteSpace([string]$DeleteEmptyFolders)) {
        Set-ObjectProperty -Object $Target -Name "DeleteEmptyFolders" -Value (ConvertTo-WizardBool $DeleteEmptyFolders $true)
    }

    $ProtectedEmptyFolders = @(ConvertTo-WizardStringArray (Read-WizardValue "ProtectedEmptyFolders override comma-separated empty=default" $ExistingProtectedEmptyFolders))
    if ($ProtectedEmptyFolders.Count -gt 0) {
        Set-ObjectProperty -Object $Target -Name "ProtectedEmptyFolders" -Value $ProtectedEmptyFolders
    }

    return $Target
}

function Add-Target {
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    $Targets = @(Get-Targets -Config $Config)
    $Targets += Read-TargetValues
    Set-Targets -Config $Config -Targets $Targets
}

function Edit-Target {
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    $Targets = @(Get-Targets -Config $Config)
    Show-Targets -Config $Config

    if ($Targets.Count -eq 0) {
        return
    }

    $Index = [int](Read-WizardValue "Target number to edit" "1") - 1

    if ($Index -lt 0 -or $Index -ge $Targets.Count) {
        throw "Target broj nije validan."
    }

    $Targets[$Index] = Read-TargetValues -ExistingTarget $Targets[$Index]
    Set-Targets -Config $Config -Targets $Targets
}

function Set-TargetEnabled {
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    $Targets = @(Get-Targets -Config $Config)
    Show-Targets -Config $Config

    if ($Targets.Count -eq 0) {
        return
    }

    $Index = [int](Read-WizardValue "Target number" "1") - 1

    if ($Index -lt 0 -or $Index -ge $Targets.Count) {
        throw "Target broj nije validan."
    }

    $Enabled = ConvertTo-WizardBool (Read-WizardValue "Enabled true/false" $Targets[$Index].Enabled) $Targets[$Index].Enabled
    Set-ObjectProperty -Object $Targets[$Index] -Name "Enabled" -Value $Enabled
    Set-Targets -Config $Config -Targets $Targets
}

function Remove-Target {
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    $Targets = @(Get-Targets -Config $Config)
    Show-Targets -Config $Config

    if ($Targets.Count -eq 0) {
        return
    }

    $Index = [int](Read-WizardValue "Target number to remove" "1") - 1

    if ($Index -lt 0 -or $Index -ge $Targets.Count) {
        throw "Target broj nije validan."
    }

    $UpdatedTargets = @()

    for ($ItemIndex = 0; $ItemIndex -lt $Targets.Count; $ItemIndex++) {
        if ($ItemIndex -ne $Index) {
            $UpdatedTargets += $Targets[$ItemIndex]
        }
    }

    Set-Targets -Config $Config -Targets $UpdatedTargets
}

function Show-WizardMenu {
    Write-Host ""
    Write-Host "Config wizard"
    Write-Host "1) New config"
    Write-Host "2) Edit defaults"
    Write-Host "3) Add target"
    Write-Host "4) Edit target"
    Write-Host "5) Enable/disable target"
    Write-Host "6) Remove target"
    Write-Host "7) List targets"
    Write-Host "8) Save"
    Write-Host "9) Configure Windows Scheduled Task"
    Write-Host "0) Exit"
}

$Config = Import-WizardConfig -Path $ConfigFile

if ($Mode -eq "TaskScheduler") {
    Configure-ScheduledTask -Path $TaskConfigFile -SkipApplyPrompt:$SkipTaskApplyPrompt
    return
}

while ($true) {
    Show-WizardMenu
    $Choice = [string](Read-WizardValue "Choice" "")

    switch ($Choice) {
        "1" {
            $Config = New-WizardConfig
            Write-Host "Novi config je kreiran u memoriji."
        }
        "2" { Edit-Defaults -Config $Config }
        "3" { Add-Target -Config $Config }
        "4" { Edit-Target -Config $Config }
        "5" { Set-TargetEnabled -Config $Config }
        "6" { Remove-Target -Config $Config }
        "7" { Show-Targets -Config $Config }
        "8" { Save-WizardConfig -Config $Config -Path $ConfigFile }
        "9" { Configure-ScheduledTask -Path $TaskConfigFile }
        "0" { return }
        default { Write-Host "Nepoznata opcija: $Choice" }
    }
}
