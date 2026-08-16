param(
    [string]$TaskConfigFile,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($TaskConfigFile)) {
    $TaskConfigFile = Join-Path $ScriptRoot "scheduled-task.json"
}

if (-not (Test-Path -LiteralPath $TaskConfigFile -PathType Leaf)) {
    throw "Task config fajl ne postoji: $TaskConfigFile"
}

$IsWindowsPlatform = if (Test-Path Variable:IsWindows) {
    $IsWindows
}
else {
    $env:OS -eq "Windows_NT"
}

if (-not $IsWindowsPlatform) {
    throw "Windows Task Scheduler registracija je podrzana samo na Windowsu."
}

Import-Module ScheduledTasks -ErrorAction Stop

$TaskConfig = Get-Content -LiteralPath $TaskConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json

function Get-RequiredTaskValue {
    param(
        [Parameter(Mandatory)]
        [object]$Object,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if (
        -not ($Object.PSObject.Properties.Name -contains $Name) -or
        [string]::IsNullOrWhiteSpace([string]$Object.$Name)
    ) {
        throw "Task config mora sadrzavati $Name."
    }

    return $Object.$Name
}

function ConvertTo-TaskStartTime {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return (Get-Date "02:00")
    }

    return [datetime]::ParseExact([string]$Value, "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
}

$TaskName = [string](Get-RequiredTaskValue -Object $TaskConfig -Name "TaskName")
$ScriptPath = [string](Get-RequiredTaskValue -Object $TaskConfig -Name "ScriptPath")
$WorkingDirectory = [string](Get-RequiredTaskValue -Object $TaskConfig -Name "WorkingDirectory")
$ScheduleType = ([string](Get-RequiredTaskValue -Object $TaskConfig -Name "ScheduleType")).Trim()
$UserId = if ($TaskConfig.PSObject.Properties.Name -contains "UserId") { [string]$TaskConfig.UserId } else { "SYSTEM" }
$RunElevated = if ($TaskConfig.PSObject.Properties.Name -contains "RunElevated") { [bool]$TaskConfig.RunElevated } else { $true }
$Enabled = if ($TaskConfig.PSObject.Properties.Name -contains "Enabled") { [bool]$TaskConfig.Enabled } else { $true }
$Interval = if ($TaskConfig.PSObject.Properties.Name -contains "Interval") { [int]$TaskConfig.Interval } else { 1 }
$StartTime = if ($TaskConfig.PSObject.Properties.Name -contains "StartTime") { ConvertTo-TaskStartTime -Value $TaskConfig.StartTime } else { ConvertTo-TaskStartTime -Value $null }
$DaysOfWeek = if ($TaskConfig.PSObject.Properties.Name -contains "DaysOfWeek") { @($TaskConfig.DaysOfWeek) } else { @("Monday") }

if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    throw "Archive script ne postoji: $ScriptPath"
}

if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) {
    throw "Working directory ne postoji: $WorkingDirectory"
}

if ($Interval -lt 1) {
    throw "Interval mora biti veci ili jednak 1."
}

$QuotedScriptPath = '"' + $ScriptPath + '"'
$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File $QuotedScriptPath" `
    -WorkingDirectory $WorkingDirectory

switch -Regex ($ScheduleType) {
    "^(Daily)$" {
        $Trigger = New-ScheduledTaskTrigger -Daily -At $StartTime -DaysInterval $Interval
        break
    }
    "^(Hourly)$" {
        $Trigger = New-ScheduledTaskTrigger -Once -At $StartTime -RepetitionInterval (New-TimeSpan -Hours $Interval)
        break
    }
    "^(Weekly)$" {
        $Trigger = New-ScheduledTaskTrigger -Weekly -At $StartTime -WeeksInterval $Interval -DaysOfWeek $DaysOfWeek
        break
    }
    "^(AtStartup)$" {
        $Trigger = New-ScheduledTaskTrigger -AtStartup
        break
    }
    default {
        throw "ScheduleType mora biti Daily, Hourly, Weekly ili AtStartup. Vrijednost: $ScheduleType"
    }
}

$Principal = New-ScheduledTaskPrincipal `
    -UserId $UserId `
    -LogonType ServiceAccount `
    -RunLevel $(if ($RunElevated) { "Highest" } else { "Limited" })

$Settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 12)

$Task = New-ScheduledTask -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings

if ($WhatIf) {
    Write-Host "WHATIF: Scheduled task '$TaskName' bi bio registrovan/azuriran."
    return
}

Register-ScheduledTask -TaskName $TaskName -InputObject $Task -Force | Out-Null

if (-not $Enabled) {
    Disable-ScheduledTask -TaskName $TaskName | Out-Null
}
else {
    Enable-ScheduledTask -TaskName $TaskName | Out-Null
}

Write-Host "Scheduled task registrovan/azuriran: $TaskName"
