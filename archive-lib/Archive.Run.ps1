function New-ArchiveResult {
    param(
        [int]$Found = 0,
        [int]$Moved = 0,
        [int]$Tested = 0,
        [int]$Skipped = 0,
        [int]$Errors = 0
    )

    return [PSCustomObject]@{
        Found   = $Found
        Moved   = $Moved
        Tested  = $Tested
        Skipped = $Skipped
        Errors  = $Errors
    }
}

function Add-ArchiveResult {
    param(
        [Parameter(Mandatory)]
        [object]$Target,

        [Parameter(Mandatory)]
        [object]$Source
    )

    $Target.Found += $Source.Found
    $Target.Moved += $Source.Moved
    $Target.Tested += $Source.Tested
    $Target.Skipped += $Source.Skipped
    $Target.Errors += $Source.Errors
}

function Get-ArchiveRoot {
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [object]$Settings
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.ArchivePath)) {
        return Resolve-ArchivePath -Path $Settings.ArchivePath -BaseDirectory $SourceRoot
    }

    return Resolve-ArchivePath -Path $Settings.ArchiveFolder -BaseDirectory $SourceRoot
}

function Invoke-TargetArchive {
    param(
        [Parameter(Mandatory)]
        [object]$TargetConfig,

        [Parameter(Mandatory)]
        [object]$Settings,

        [Parameter(Mandatory)]
        [string]$LogFile
    )

    $TargetName = Get-ArchiveTargetName -Target $TargetConfig
    $SourceRoot = [string]$TargetConfig.Path

    if (-not $Settings.Enabled) {
        Write-ArchiveLog "PRESKOCEN [$TargetName]: Enabled je false." -LogFile $LogFile
        return New-ArchiveResult -Skipped 1
    }

    $ArchiveRoot = Get-ArchiveRoot -SourceRoot $SourceRoot -Settings $Settings
    $CutoffDate = Get-CutoffDate -OlderThanSeconds $Settings.OlderThanSeconds

    Write-ArchiveLog "------------------------------------------------------------" -LogFile $LogFile
    Write-ArchiveLog "CILJ: $TargetName" -LogFile $LogFile
    Write-ArchiveLog "Putanja: $SourceRoot" -LogFile $LogFile
    Write-ArchiveLog "Arhiva: $ArchiveRoot" -LogFile $LogFile
    Write-ArchiveLog "Starost: $($Settings.OlderThanSeconds) sekundi" -LogFile $LogFile
    Write-ArchiveLog "Ekstenzije: $($Settings.Extensions -join ', ')" -LogFile $LogFile
    Write-ArchiveLog "TestMode: $($Settings.TestMode)" -LogFile $LogFile

    $FileSearchParams = @{
        SourceRoot  = $SourceRoot
        ArchiveRoot = $ArchiveRoot
        CutoffDate  = $CutoffDate
        Extensions  = $Settings.Extensions
    }

    $Files = @(Get-ArchivableFiles @FileSearchParams)

    $Result = New-ArchiveResult -Found $Files.Count

    Write-ArchiveLog "Pronadjeno fajlova: $($Files.Count)" -LogFile $LogFile

    foreach ($File in $Files) {
        try {
            $DestinationParams = @{
                File        = $File
                SourceRoot  = $SourceRoot
                ArchiveRoot = $ArchiveRoot
            }

            $Destination = Get-DestinationPath @DestinationParams

            if ($Settings.TestMode) {
                Write-ArchiveLog "TEST [$TargetName]: '$($File.FullName)' -> '$($Destination.File)'" -LogFile $LogFile
                $Result.Tested++
                continue
            }

            if (-not (Test-Path -LiteralPath $Destination.Directory -PathType Container)) {
                New-Item -ItemType Directory -Path $Destination.Directory -Force | Out-Null
            }

            Move-Item -LiteralPath $File.FullName -Destination $Destination.File
            Write-ArchiveLog "PREMJESTEN [$TargetName]: '$($File.FullName)' -> '$($Destination.File)'" -LogFile $LogFile

            $Result.Moved++
        }
        catch {
            Write-ArchiveLog "GRESKA [$TargetName]: '$($File.FullName)' - $($_.Exception.Message)" -LogFile $LogFile
            $Result.Errors++
        }
    }

    return $Result
}

function Invoke-ArchiveRun {
    param(
        [Parameter(Mandatory)]
        [string]$ConfigFile,

        [Parameter(Mandatory)]
        [string]$LogFile,

        [Parameter(Mandatory)]
        [object]$BuiltInDefaults
    )

    $Config = Import-ArchiveConfig -Path $ConfigFile
    $Defaults = Get-DefaultSettings -Config $Config -BuiltInDefaults $BuiltInDefaults
    $ArchiveTargets = @(Get-ArchiveTargets -Config $Config)

    Set-ArchiveLogLimit -MaxLogSizeMB $Defaults.MaxLogSizeMB -LogRotateCount $Defaults.LogRotateCount

    Write-ArchiveLog "============================================================" -LogFile $LogFile
    Write-ArchiveLog "Pokretanje arhiviranja" -LogFile $LogFile
    Write-ArchiveLog "Broj ciljnih putanja: $($ArchiveTargets.Count)" -LogFile $LogFile
    Write-ArchiveLog "Limit log fajla: $($Defaults.MaxLogSizeMB) MB" -LogFile $LogFile
    Write-ArchiveLog "Broj rotiranih logova: $($Defaults.LogRotateCount)" -LogFile $LogFile
    Write-ArchiveLog "============================================================" -LogFile $LogFile

    $Totals = New-ArchiveResult

    foreach ($ArchiveTarget in $ArchiveTargets) {
        $Settings = Get-TargetSettings -TargetConfig $ArchiveTarget -Defaults $Defaults

        $ArchiveParams = @{
            TargetConfig = $ArchiveTarget
            Settings     = $Settings
            LogFile      = $LogFile
        }

        $Result = Invoke-TargetArchive @ArchiveParams

        Add-ArchiveResult -Target $Totals -Source $Result
    }

    Write-ArchiveLog "============================================================" -LogFile $LogFile
    Write-ArchiveLog "Arhiviranje zavrseno" -LogFile $LogFile
    Write-ArchiveLog "Pronadjeno: $($Totals.Found)" -LogFile $LogFile
    Write-ArchiveLog "Premjesteno: $($Totals.Moved)" -LogFile $LogFile
    Write-ArchiveLog "Testirano: $($Totals.Tested)" -LogFile $LogFile
    Write-ArchiveLog "Preskoceno: $($Totals.Skipped)" -LogFile $LogFile
    Write-ArchiveLog "Greske: $($Totals.Errors)" -LogFile $LogFile
    Write-ArchiveLog "============================================================" -LogFile $LogFile

    return $Totals
}
