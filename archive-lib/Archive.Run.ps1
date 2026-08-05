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

function Invoke-MachineArchive {
    param(
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo]$MachineFolder,

        [Parameter(Mandatory)]
        [object]$Settings,

        [Parameter(Mandatory)]
        [string]$LogFile
    )

    $MachineName = $MachineFolder.Name
    $MachineRoot = $MachineFolder.FullName

    if (-not $Settings.Enabled) {
        Write-ArchiveLog "PRESKOČEN [$MachineName]: Enabled je false." -LogFile $LogFile
        return New-ArchiveResult -Skipped 1
    }

    $ArchiveRoot = Join-Path $MachineRoot $Settings.ArchiveFolder
    $CutoffDate = Get-CutoffDate -OlderThanDays $Settings.OlderThanDays

    Write-ArchiveLog "------------------------------------------------------------" -LogFile $LogFile
    Write-ArchiveLog "MAŠINA: $MachineName" -LogFile $LogFile
    Write-ArchiveLog "Putanja: $MachineRoot" -LogFile $LogFile
    Write-ArchiveLog "Starost: $($Settings.OlderThanDays) dana" -LogFile $LogFile
    Write-ArchiveLog "Ekstenzije: $($Settings.Extensions -join ', ')" -LogFile $LogFile
    Write-ArchiveLog "TestMode: $($Settings.TestMode)" -LogFile $LogFile

    $FileSearchParams = @{
        MachineRoot = $MachineRoot
        ArchiveRoot = $ArchiveRoot
        CutoffDate  = $CutoffDate
        Extensions  = $Settings.Extensions
    }

    $Files = @(Get-ArchivableFiles @FileSearchParams)

    $Result = New-ArchiveResult -Found $Files.Count

    Write-ArchiveLog "Pronađeno fajlova: $($Files.Count)" -LogFile $LogFile

    foreach ($File in $Files) {
        try {
            $DestinationParams = @{
                File        = $File
                MachineRoot = $MachineRoot
                ArchiveRoot = $ArchiveRoot
            }

            $Destination = Get-DestinationPath @DestinationParams

            if ($Settings.TestMode) {
                Write-ArchiveLog "TEST [$MachineName]: '$($File.FullName)' -> '$($Destination.File)'" -LogFile $LogFile
                $Result.Tested++
                continue
            }

            if (-not (Test-Path -LiteralPath $Destination.Directory -PathType Container)) {
                New-Item -ItemType Directory -Path $Destination.Directory -Force | Out-Null
            }

            Move-Item -LiteralPath $File.FullName -Destination $Destination.File
            Write-ArchiveLog "PREMJEŠTEN [$MachineName]: '$($File.FullName)' -> '$($Destination.File)'" -LogFile $LogFile

            $Result.Moved++
        }
        catch {
            Write-ArchiveLog "GREŠKA [$MachineName]: '$($File.FullName)' - $($_.Exception.Message)" -LogFile $LogFile
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
    $ConfiguredMachines = $null

    if (Test-ConfigProperty $Config "Machines") {
        $ConfiguredMachines = @($Config.Machines)
    }

    $MachineFolders = @(
        Get-ChildItem -LiteralPath $Config.BasePath -Directory -Force
    )

    Write-ArchiveLog "============================================================" -LogFile $LogFile
    Write-ArchiveLog "Pokretanje arhiviranja" -LogFile $LogFile
    Write-ArchiveLog "BasePath: $($Config.BasePath)" -LogFile $LogFile
    Write-ArchiveLog "Pronađeno foldera: $($MachineFolders.Count)" -LogFile $LogFile
    Write-ArchiveLog "============================================================" -LogFile $LogFile

    $Totals = New-ArchiveResult

    foreach ($MachineFolder in $MachineFolders) {
        $MachineConfigParams = @{
            MachineName = $MachineFolder.Name
            Machines    = $ConfiguredMachines
        }

        $MachineConfig = Get-MachineConfig @MachineConfigParams

        if (
            $null -ne $ConfiguredMachines -and
            $ConfiguredMachines.Count -gt 0 -and
            $null -eq $MachineConfig
        ) {
            Write-ArchiveLog "PRESKOČEN [$($MachineFolder.Name)]: Nije naveden u configu." -LogFile $LogFile
            $Totals.Skipped++
            continue
        }

        $MachineSettingsParams = @{
            MachineConfig = $MachineConfig
            Defaults      = $Defaults
        }

        $Settings = Get-MachineSettings @MachineSettingsParams

        $ArchiveParams = @{
            MachineFolder = $MachineFolder
            Settings      = $Settings
            LogFile       = $LogFile
        }

        $Result = Invoke-MachineArchive @ArchiveParams

        Add-ArchiveResult -Target $Totals -Source $Result
    }

    Write-ArchiveLog "============================================================" -LogFile $LogFile
    Write-ArchiveLog "Arhiviranje završeno" -LogFile $LogFile
    Write-ArchiveLog "Pronađeno: $($Totals.Found)" -LogFile $LogFile
    Write-ArchiveLog "Premješteno: $($Totals.Moved)" -LogFile $LogFile
    Write-ArchiveLog "Testirano: $($Totals.Tested)" -LogFile $LogFile
    Write-ArchiveLog "Preskočeno: $($Totals.Skipped)" -LogFile $LogFile
    Write-ArchiveLog "Greške: $($Totals.Errors)" -LogFile $LogFile
    Write-ArchiveLog "============================================================" -LogFile $LogFile

    return $Totals
}
