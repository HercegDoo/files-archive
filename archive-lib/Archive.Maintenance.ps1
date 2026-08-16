function Get-ArchiveBaseRoot {
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [object]$Settings
    )

    $ConfiguredPath = if (-not [string]::IsNullOrWhiteSpace([string]$Settings.ArchivePath)) {
        [string]$Settings.ArchivePath
    }
    else {
        [string]$Settings.ArchiveFolder
    }

    $FirstTokenMatch = [regex]::Match($ConfiguredPath, "\{(year|month)\}", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    if ($FirstTokenMatch.Success) {
        $ConfiguredPath = $ConfiguredPath.Substring(0, $FirstTokenMatch.Index).TrimEnd("\", "/")
    }

    if ([string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        $ConfiguredPath = "."
    }

    return Resolve-ArchivePath -Path $ConfiguredPath -BaseDirectory $SourceRoot
}

function Get-ArchiveAgeCutoffDate {
    param(
        [Parameter(Mandatory)]
        [object]$Age
    )

    if ($Age -is [int] -or $Age -is [long] -or $Age -is [double] -or $Age -is [decimal]) {
        return (Get-Date).AddYears(-[int]$Age)
    }

    $Text = ([string]$Age).Trim().ToLowerInvariant()
    $Match = [regex]::Match($Text, "^(?<value>\d+(?:\.\d+)?)\s*(?<unit>year|years|month|months|day|days)$")

    if (-not $Match.Success) {
        throw "ArchiveZipAfter mora biti npr. '1 year', '6 months' ili '30 days'. Vrijednost: $Age"
    }

    $Value = [double]$Match.Groups["value"].Value
    $Unit = $Match.Groups["unit"].Value

    switch -Regex ($Unit) {
        "^years?$" { return (Get-Date).AddYears(-[int]$Value) }
        "^months?$" { return (Get-Date).AddMonths(-[int]$Value) }
        "^days?$" { return (Get-Date).AddDays(-$Value) }
    }
}

function Get-ArchiveFilesUnderPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force | Where-Object {
        $_.Extension.ToLowerInvariant() -ne ".zip"
    })
}

function Test-ArchiveGroupOldEnough {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$Files,

        [Parameter(Mandatory)]
        [datetime]$CutoffDate
    )

    if ($Files.Count -eq 0) {
        return $false
    }

    $NewestCreationTime = ($Files | Sort-Object CreationTimeUtc -Descending | Select-Object -First 1).CreationTimeUtc

    return $NewestCreationTime -lt $CutoffDate.ToUniversalTime()
}

function Get-ZipEntryNames {
    param(
        [Parameter(Mandatory)]
        [string]$ZipFile
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $Zip = [System.IO.Compression.ZipFile]::OpenRead($ZipFile)

    try {
        return @($Zip.Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) } | ForEach-Object {
            $_.FullName.Replace("\", "/")
        })
    }
    finally {
        $Zip.Dispose()
    }
}

function Test-ZipContainsExpectedFiles {
    param(
        [Parameter(Mandatory)]
        [string]$ZipFile,

        [Parameter(Mandatory)]
        [string[]]$ExpectedEntries
    )

    if (-not (Test-Path -LiteralPath $ZipFile -PathType Leaf)) {
        return $false
    }

    $ZipItem = Get-Item -LiteralPath $ZipFile

    if ($ZipItem.Length -le 0) {
        return $false
    }

    $ActualEntries = @(Get-ZipEntryNames -ZipFile $ZipFile | Sort-Object)
    $Expected = @($ExpectedEntries | Sort-Object)
    $Diff = @(Compare-Object -ReferenceObject $Expected -DifferenceObject $ActualEntries)

    return $Diff.Count -eq 0
}

function Compress-ArchiveGroup {
    param(
        [Parameter(Mandatory)]
        [string]$SourceDirectory,

        [Parameter(Mandatory)]
        [string]$DestinationZip,

        [Parameter(Mandatory)]
        [string]$LogFile,

        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [bool]$DryRun
    )

    if (Test-Path -LiteralPath $DestinationZip -PathType Leaf) {
        Write-ArchiveLog "ZIP PRESKOCEN [$Label]: vec postoji '$DestinationZip'." -LogFile $LogFile
        return
    }

    $Files = @(Get-ArchiveFilesUnderPath -Path $SourceDirectory)

    if ($Files.Count -eq 0) {
        Write-ArchiveLog "ZIP PRESKOCEN [$Label]: nema fajlova za kompresovanje." -LogFile $LogFile
        return
    }

    $ExpectedEntries = @($Files | ForEach-Object {
        $_.FullName.Substring($SourceDirectory.Length).TrimStart("\", "/").Replace("\", "/")
    })

    if ($DryRun) {
        Write-ArchiveLog "TEST ZIP [$Label]: '$SourceDirectory' -> '$DestinationZip' ($($Files.Count) fajlova)" -LogFile $LogFile
        return
    }

    $DestinationDirectory = Split-Path -Parent $DestinationZip
    $DestinationFileName = [System.IO.Path]::GetFileNameWithoutExtension($DestinationZip)
    $TempZip = Join-Path $DestinationDirectory "$DestinationFileName.$([guid]::NewGuid().ToString("N")).tmp.zip"

    try {
        if (-not (Test-Path -LiteralPath $DestinationDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
        }

        if (Test-Path -LiteralPath $TempZip -PathType Leaf) {
            Remove-Item -LiteralPath $TempZip -Force
        }

        Compress-Archive -Path (Join-Path $SourceDirectory "*") -DestinationPath $TempZip -Force

        if (-not (Test-ZipContainsExpectedFiles -ZipFile $TempZip -ExpectedEntries $ExpectedEntries)) {
            throw "ZIP validacija nije uspjela."
        }

        Move-Item -LiteralPath $TempZip -Destination $DestinationZip -Force

        if (-not (Test-ZipContainsExpectedFiles -ZipFile $DestinationZip -ExpectedEntries $ExpectedEntries)) {
            throw "Finalna ZIP validacija nije uspjela."
        }

        Remove-Item -LiteralPath $SourceDirectory -Recurse -Force
        Write-ArchiveLog "ZIP KREIRAN [$Label]: '$DestinationZip' ($($Files.Count) fajlova)" -LogFile $LogFile
    }
    catch {
        if (Test-Path -LiteralPath $TempZip -PathType Leaf) {
            Remove-Item -LiteralPath $TempZip -Force
        }

        Write-ArchiveLog "ZIP GRESKA [$Label]: '$SourceDirectory' - $($_.Exception.Message)" -LogFile $LogFile
    }
}

function Invoke-ArchiveZipMaintenance {
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [string]$LogFile
    )

    $Settings = $Context.Settings

    if (-not $Settings.Enabled -or -not $Settings.ArchiveZipEnabled) {
        return
    }

    if ($null -eq $Settings.ArchiveZipAfter) {
        throw "ArchiveZipAfter mora biti definisan kada je ArchiveZipEnabled ukljucen."
    }

    $ArchiveBaseRoot = Get-ArchiveBaseRoot -SourceRoot $Context.SourceRoot -Settings $Settings

    if (-not (Test-Path -LiteralPath $ArchiveBaseRoot -PathType Container)) {
        return
    }

    $CutoffDate = Get-ArchiveAgeCutoffDate -Age $Settings.ArchiveZipAfter

    Write-ArchiveLog "ZIP maintenance [$($Context.TargetName)]: group_by=$($Settings.ArchiveZipGroupBy), cutoff=$($CutoffDate.ToString("yyyy-MM-dd"))" -LogFile $LogFile

    if ($Settings.ArchiveZipGroupBy -eq "year") {
        $YearDirectories = @(Get-ChildItem -LiteralPath $ArchiveBaseRoot -Directory -Force | Where-Object {
            $_.Name -match "^\d{4}$"
        } | Sort-Object Name)

        foreach ($YearDirectory in $YearDirectories) {
            $Files = @(Get-ArchiveFilesUnderPath -Path $YearDirectory.FullName)

            if (-not (Test-ArchiveGroupOldEnough -Files $Files -CutoffDate $CutoffDate)) {
                continue
            }

            $DestinationZip = Join-Path $ArchiveBaseRoot "$($YearDirectory.Name).zip"
            Compress-ArchiveGroup -SourceDirectory $YearDirectory.FullName -DestinationZip $DestinationZip -LogFile $LogFile -Label "$($Context.TargetName):$($YearDirectory.Name)" -DryRun:$Settings.TestMode
        }

        return
    }

    $MonthDirectories = @(Get-ChildItem -LiteralPath $ArchiveBaseRoot -Directory -Force | Where-Object {
        $_.Name -match "^\d{4}$"
    } | ForEach-Object {
        Get-ChildItem -LiteralPath $_.FullName -Directory -Force | Where-Object { $_.Name -match "^\d{2}$" }
    } | Sort-Object FullName)

    foreach ($MonthDirectory in $MonthDirectories) {
        $Files = @(Get-ArchiveFilesUnderPath -Path $MonthDirectory.FullName)

        if (-not (Test-ArchiveGroupOldEnough -Files $Files -CutoffDate $CutoffDate)) {
            continue
        }

        $DestinationZip = "$($MonthDirectory.FullName).zip"
        Compress-ArchiveGroup -SourceDirectory $MonthDirectory.FullName -DestinationZip $DestinationZip -LogFile $LogFile -Label "$($Context.TargetName):$($MonthDirectory.Parent.Name)/$($MonthDirectory.Name)" -DryRun:$Settings.TestMode
    }
}

function Get-RetentionCutoffYear {
    param(
        [Parameter(Mandatory)]
        [double]$RetentionYears
    )

    return (Get-Date).AddYears(-[int]$RetentionYears).Year
}

function Get-RetentionArchiveItems {
    param(
        [Parameter(Mandatory)]
        [string]$ArchiveBaseRoot,

        [Parameter(Mandatory)]
        [int]$CutoffYear
    )

    if (-not (Test-Path -LiteralPath $ArchiveBaseRoot -PathType Container)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $ArchiveBaseRoot -Force | Where-Object {
            $ArchiveYear = $null

            if ($_.PSIsContainer -and $_.Name -match "^\d{4}$") {
                $ArchiveYear = [int]$_.Name
            }
            elseif (-not $_.PSIsContainer -and $_.Name -match "^(\d{4})\.zip$") {
                $ArchiveYear = [int]$Matches[1]
            }

            $null -ne $ArchiveYear -and $ArchiveYear -lt $CutoffYear
        }
    )
}

function Copy-ArchiveItemForRetention {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    $DestinationParent = Split-Path -Parent $DestinationPath

    if (-not (Test-Path -LiteralPath $DestinationParent -PathType Container)) {
        New-Item -ItemType Directory -Path $DestinationParent -Force | Out-Null
    }

    Copy-Item -LiteralPath $Item.FullName -Destination $DestinationPath -Recurse -Force

    if (-not (Test-Path -LiteralPath $DestinationPath)) {
        throw "Destination nije kreiran: $DestinationPath"
    }

    $SourceManifest = @(Get-RetentionItemManifest -Path $Item.FullName)
    $DestinationManifest = @(Get-RetentionItemManifest -Path $DestinationPath)
    $Diff = @(Compare-Object -ReferenceObject $SourceManifest -DifferenceObject $DestinationManifest)

    if ($Diff.Count -gt 0) {
        throw "Destination validacija nije uspjela: $DestinationPath"
    }
}

function Get-RetentionItemManifest {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $Item = Get-Item -LiteralPath $Path

    if (-not $Item.PSIsContainer) {
        $Hash = (Get-FileHash -LiteralPath $Item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        return @("FILE  $Hash  $($Item.Name)")
    }

    return @(
        Get-ChildItem -LiteralPath $Item.FullName -Recurse -File -Force |
            Sort-Object FullName |
            ForEach-Object {
                $RelativePath = $_.FullName.Substring($Item.FullName.Length).TrimStart("\", "/").Replace("\", "/")
                $Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                "FILE  $Hash  $RelativePath"
            }
    )
}

function Invoke-RetentionMaintenance {
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [string]$LogFile
    )

    $Settings = $Context.Settings

    if (-not $Settings.Enabled -or -not $Settings.RetentionEnabled) {
        return
    }

    if ($null -eq $Settings.RetentionYears) {
        throw "RetentionYears mora biti definisan kada je RetentionEnabled ukljucen."
    }

    if ($Settings.RetentionAction -eq "move" -and [string]::IsNullOrWhiteSpace([string]$Settings.SecondaryStorage)) {
        throw "SecondaryStorage mora biti definisan za retention move akciju."
    }

    $ArchiveBaseRoot = Get-ArchiveBaseRoot -SourceRoot $Context.SourceRoot -Settings $Settings
    $CutoffYear = Get-RetentionCutoffYear -RetentionYears $Settings.RetentionYears
    $Items = @(Get-RetentionArchiveItems -ArchiveBaseRoot $ArchiveBaseRoot -CutoffYear $CutoffYear)

    foreach ($Item in $Items) {
        $ArchiveYear = if ($Item.Name -match "^(\d{4})") { [int]$Matches[1] } else { 0 }
        $Age = (Get-Date).Year - $ArchiveYear

        try {
            if ($Settings.TestMode) {
                $DestinationInfo = ""

                if ($Settings.RetentionAction -eq "move") {
                    $DestinationRoot = Resolve-ArchivePath -Path ([string]$Settings.SecondaryStorage) -BaseDirectory (Split-Path -Parent $ArchiveBaseRoot)
                    $DestinationInfo = " -> '$([System.IO.Path]::Combine($DestinationRoot, $Item.Name))'"
                }

                Write-ArchiveLog "TEST RETENTION [$($Context.TargetName)]: action=$($Settings.RetentionAction), age=$Age, path='$($Item.FullName)'$DestinationInfo, status=would_run" -LogFile $LogFile
                continue
            }

            if ($Settings.RetentionAction -eq "delete") {
                Remove-Item -LiteralPath $Item.FullName -Recurse -Force
                Write-ArchiveLog "RETENTION [$($Context.TargetName)]: action=delete, age=$Age, path='$($Item.FullName)', status=success" -LogFile $LogFile
                continue
            }

            $DestinationRoot = Resolve-ArchivePath -Path ([string]$Settings.SecondaryStorage) -BaseDirectory (Split-Path -Parent $ArchiveBaseRoot)
            $DestinationPath = [System.IO.Path]::Combine($DestinationRoot, $Item.Name)

            Copy-ArchiveItemForRetention -Item $Item -DestinationPath $DestinationPath
            Remove-Item -LiteralPath $Item.FullName -Recurse -Force
            Write-ArchiveLog "RETENTION [$($Context.TargetName)]: action=move, age=$Age, path='$($Item.FullName)', destination='$DestinationPath', status=success" -LogFile $LogFile
        }
        catch {
            Write-ArchiveLog "RETENTION GRESKA [$($Context.TargetName)]: action=$($Settings.RetentionAction), path='$($Item.FullName)', status=error, error='$($_.Exception.Message)'" -LogFile $LogFile
        }
    }
}
