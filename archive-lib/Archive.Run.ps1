function New-ArchiveResult {
    param(
        [int]$Found = 0,
        [int]$Selected = 0,
        [int]$Moved = 0,
        [int]$Deleted = 0,
        [int]$Tested = 0,
        [int]$Skipped = 0,
        [int]$Errors = 0
    )

    return [PSCustomObject]@{
        Found    = $Found
        Selected = $Selected
        Moved    = $Moved
        Deleted  = $Deleted
        Tested   = $Tested
        Skipped  = $Skipped
        Errors   = $Errors
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
    $Target.Selected += $Source.Selected
    $Target.Moved += $Source.Moved
    $Target.Deleted += $Source.Deleted
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

function New-ArchiveTargetContext {
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
    $Result = New-ArchiveResult

    if (-not $Settings.Enabled) {
        Write-ArchiveLog "PRESKOCEN [$TargetName]: Enabled je false." -LogFile $LogFile
        $Result.Skipped = 1

        return [PSCustomObject]@{
            TargetConfig = $TargetConfig
            Settings     = $Settings
            TargetName   = $TargetName
            SourceRoot   = $SourceRoot
            ArchiveRoot  = $null
            Result       = $Result
            Candidates   = @()
        }
    }

    $ArchiveRoot = Get-ArchiveRoot -SourceRoot $SourceRoot -Settings $Settings
    $CutoffDate = Get-CutoffDate -OlderThanSeconds $Settings.OlderThanSeconds

    Write-ArchiveLog "------------------------------------------------------------" -LogFile $LogFile
    Write-ArchiveLog "CILJ: $TargetName" -LogFile $LogFile
    Write-ArchiveLog "Putanja: $SourceRoot" -LogFile $LogFile
    Write-ArchiveLog "Arhiva: $ArchiveRoot" -LogFile $LogFile
    Write-ArchiveLog "Starost: $($Settings.OlderThanSeconds) sekundi" -LogFile $LogFile
    Write-ArchiveLog "Datum za arhivu: $($Settings.DateField)" -LogFile $LogFile
    Write-ArchiveLog "Ekstenzije: $($Settings.Extensions -join ', ')" -LogFile $LogFile
    if ($Settings.FileAction -ne "archive") {
        Write-ArchiveLog "Akcija nad fajlovima: $($Settings.FileAction)" -LogFile $LogFile
    }
    Write-ArchiveLog "Maksimalna dubina: $(if ($null -eq $Settings.MaxDepth) { 'neograniceno' } else { $Settings.MaxDepth })" -LogFile $LogFile
    if (-not $Settings.DeleteEmptyFolders -or @($Settings.ProtectedEmptyFolders).Count -gt 0) {
        Write-ArchiveLog "Brisanje praznih foldera: $($Settings.DeleteEmptyFolders)" -LogFile $LogFile
        Write-ArchiveLog "Protected empty folders: $(if (@($Settings.ProtectedEmptyFolders).Count -eq 0) { '<none>' } else { @($Settings.ProtectedEmptyFolders) -join ', ' })" -LogFile $LogFile
    }
    Write-ArchiveLog "TestMode: $($Settings.TestMode)" -LogFile $LogFile

    $FileSearchParams = @{
        SourceRoot  = $SourceRoot
        ArchiveRoot = $ArchiveRoot
        CutoffDate  = $CutoffDate
        DateField   = $Settings.DateField
        Extensions  = $Settings.Extensions
        MaxDepth    = $Settings.MaxDepth
    }

    $Files = @(Get-ArchivableFiles @FileSearchParams)
    $Result.Found = $Files.Count

    Write-ArchiveLog "Pronadjeno fajlova: $($Files.Count)" -LogFile $LogFile

    $Candidates = @(
        foreach ($File in $Files) {
            [PSCustomObject]@{
                File        = $File
                Context     = $null
                CreatedAt   = $File.CreationTimeUtc
                FullName    = $File.FullName
            }
        }
    )

    $Context = [PSCustomObject]@{
        TargetConfig = $TargetConfig
        Settings     = $Settings
        TargetName   = $TargetName
        SourceRoot   = $SourceRoot
        ArchiveRoot  = $ArchiveRoot
        Result       = $Result
        Candidates   = $Candidates
    }

    foreach ($Candidate in $Context.Candidates) {
        $Candidate.Context = $Context
    }

    return $Context
}

function Select-ArchiveCandidates {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Candidates,

        [AllowNull()]
        [object]$MaxFilesPerRun
    )

    $SortedCandidates = @(
        $Candidates |
            Sort-Object `
                @{ Expression = { $_.CreatedAt } }, `
                @{ Expression = { $_.FullName } }
    )

    if ($null -eq $MaxFilesPerRun) {
        return $SortedCandidates
    }

    return @($SortedCandidates | Select-Object -First ([int]$MaxFilesPerRun))
}

function Invoke-ArchiveCandidate {
    param(
        [Parameter(Mandatory)]
        [object]$Candidate,

        [Parameter(Mandatory)]
        [string]$LogFile
    )

    $Context = $Candidate.Context
    $File = $Candidate.File
    $Settings = $Context.Settings
    $TargetName = $Context.TargetName

    try {
        if ($Settings.FileAction -eq "delete") {
            if ($Settings.TestMode) {
                Write-ArchiveLog "TEST DELETE [$TargetName]: '$($File.FullName)'" -LogFile $LogFile
                $Context.Result.Tested++
                return
            }

            Remove-Item -LiteralPath $File.FullName -Force
            Write-ArchiveLog "OBRISAN [$TargetName]: '$($File.FullName)'" -LogFile $LogFile

            $Context.Result.Deleted++
            return
        }

        $DestinationParams = @{
            File        = $File
            SourceRoot  = $Context.SourceRoot
            ArchiveRoot = $Context.ArchiveRoot
            DateField   = $Settings.DateField
        }

        $Destination = Get-DestinationPath @DestinationParams

        if ($Settings.TestMode) {
            Write-ArchiveLog "TEST [$TargetName]: '$($File.FullName)' -> '$($Destination.File)'" -LogFile $LogFile
            $Context.Result.Tested++
            return
        }

        if (-not (Test-Path -LiteralPath $Destination.Directory -PathType Container)) {
            New-Item -ItemType Directory -Path $Destination.Directory -Force | Out-Null
        }

        Move-Item -LiteralPath $File.FullName -Destination $Destination.File
        Write-ArchiveLog "PREMJESTEN [$TargetName]: '$($File.FullName)' -> '$($Destination.File)'" -LogFile $LogFile

        $Context.Result.Moved++
    }
    catch {
        Write-ArchiveLog "GRESKA [$TargetName]: '$($File.FullName)' - $($_.Exception.Message)" -LogFile $LogFile
        $Context.Result.Errors++
    }
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
    Write-ArchiveLog "Max files per run: $(if ($null -eq $Defaults.MaxFilesPerRun) { 'neograniceno' } else { $Defaults.MaxFilesPerRun })" -LogFile $LogFile
    Write-ArchiveLog "============================================================" -LogFile $LogFile

    $Contexts = @()
    $AllCandidates = @()

    foreach ($ArchiveTarget in $ArchiveTargets) {
        $Settings = Get-TargetSettings -TargetConfig $ArchiveTarget -Defaults $Defaults

        $ContextParams = @{
            TargetConfig = $ArchiveTarget
            Settings     = $Settings
            LogFile      = $LogFile
        }

        $Context = New-ArchiveTargetContext @ContextParams
        $Contexts += $Context
        $AllCandidates += @($Context.Candidates)
    }

    $SelectedCandidates = @(Select-ArchiveCandidates -Candidates $AllCandidates -MaxFilesPerRun $Defaults.MaxFilesPerRun)
    $RemainingFiles = $AllCandidates.Count - $SelectedCandidates.Count

    foreach ($Candidate in $SelectedCandidates) {
        $Candidate.Context.Result.Selected++
    }

    Write-ArchiveLog "Files eligible for archive: $($AllCandidates.Count)" -LogFile $LogFile
    Write-ArchiveLog "Max files per run: $(if ($null -eq $Defaults.MaxFilesPerRun) { 'neograniceno' } else { $Defaults.MaxFilesPerRun })" -LogFile $LogFile
    Write-ArchiveLog "Files selected: $($SelectedCandidates.Count)" -LogFile $LogFile
    Write-ArchiveLog "Files remaining: $RemainingFiles" -LogFile $LogFile

    foreach ($Candidate in $SelectedCandidates) {
        Invoke-ArchiveCandidate -Candidate $Candidate -LogFile $LogFile
    }

    foreach ($Context in $Contexts) {
        if (
            $Context.Settings.Enabled -and
            -not $Context.Settings.TestMode
        ) {
            if (@($Context.Settings.ProtectedEmptyFolders).Count -gt 0) {
                if ($Context.Settings.FileAction -eq "archive") {
                    $CreatedProtectedDirectories = Ensure-ProtectedEmptyDirectoriesInArchive `
                        -SourceRoot $Context.SourceRoot `
                        -ArchiveRoot $Context.ArchiveRoot `
                        -ProtectedPatterns @($Context.Settings.ProtectedEmptyFolders) `
                        -Date (Get-Date)

                    Write-ArchiveLog "Kreirano protected empty folders u arhivi [$($Context.TargetName)]: $CreatedProtectedDirectories" -LogFile $LogFile
                }
            }

            if (($Context.Result.Moved + $Context.Result.Deleted) -gt 0) {
                if ($Context.Settings.DeleteEmptyFolders) {
                    $RemovedDirectories = Remove-EmptySourceDirectories `
                        -SourceRoot $Context.SourceRoot `
                        -ArchiveRoot $Context.ArchiveRoot `
                        -ProtectedPatterns @($Context.Settings.ProtectedEmptyFolders)

                    Write-ArchiveLog "Obrisano praznih foldera [$($Context.TargetName)]: $RemovedDirectories" -LogFile $LogFile
                }
                else {
                    Write-ArchiveLog "Brisanje praznih foldera iskljuceno [$($Context.TargetName)]." -LogFile $LogFile
                }
            }
        }
    }

    foreach ($Context in $Contexts) {
        Invoke-ArchiveZipMaintenance -Context $Context -LogFile $LogFile
    }

    foreach ($Context in $Contexts) {
        Invoke-RetentionMaintenance -Context $Context -LogFile $LogFile
    }

    $Totals = New-ArchiveResult

    foreach ($Context in $Contexts) {
        Add-ArchiveResult -Target $Totals -Source $Context.Result
    }

    Write-ArchiveLog "============================================================" -LogFile $LogFile
    Write-ArchiveLog "Arhiviranje zavrseno" -LogFile $LogFile
    Write-ArchiveLog "Pronadjeno: $($Totals.Found)" -LogFile $LogFile
    Write-ArchiveLog "Odabrano: $($Totals.Selected)" -LogFile $LogFile
    Write-ArchiveLog "Premjesteno: $($Totals.Moved)" -LogFile $LogFile
    if ($Totals.Deleted -gt 0) {
        Write-ArchiveLog "Obrisano fajlova: $($Totals.Deleted)" -LogFile $LogFile
    }
    Write-ArchiveLog "Testirano: $($Totals.Tested)" -LogFile $LogFile
    Write-ArchiveLog "Preskoceno: $($Totals.Skipped)" -LogFile $LogFile
    Write-ArchiveLog "Greske: $($Totals.Errors)" -LogFile $LogFile
    Write-ArchiveLog "Preostalo: $RemainingFiles" -LogFile $LogFile
    Write-ArchiveLog "===== ARCHIVE RUN SUMMARY =====" -LogFile $LogFile
    Write-ArchiveLog "Eligible files: $($Totals.Found)" -LogFile $LogFile
    Write-ArchiveLog "Selected files: $($Totals.Selected)" -LogFile $LogFile
    Write-ArchiveLog "Successfully archived: $($Totals.Moved)" -LogFile $LogFile
    if ($Totals.Deleted -gt 0) {
        Write-ArchiveLog "Successfully deleted: $($Totals.Deleted)" -LogFile $LogFile
    }
    Write-ArchiveLog "Skipped: $($Totals.Skipped)" -LogFile $LogFile
    Write-ArchiveLog "Failed: $($Totals.Errors)" -LogFile $LogFile
    Write-ArchiveLog "Remaining backlog: $RemainingFiles" -LogFile $LogFile
    Write-ArchiveLog "============================================================" -LogFile $LogFile

    return $Totals
}
