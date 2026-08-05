function Get-CutoffDate {
    param(
        [Parameter(Mandatory)]
        [double]$OlderThanDays
    )

    if ($OlderThanDays -le 0) {
        throw "Broj dana mora biti veći od 0."
    }

    return (Get-Date).AddDays(-$OlderThanDays)
}

function Test-ExtensionAllowed {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$File,

        [Parameter(Mandatory)]
        [string[]]$Extensions
    )

    return $Extensions -contains $File.Extension.ToLowerInvariant()
}

function Test-IsInsideArchive {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ArchiveRoot
    )

    $ArchiveRootPrefix = $ArchiveRoot.TrimEnd("\", "/") + "\"

    return $Path.StartsWith(
        $ArchiveRootPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Get-ArchivableFiles {
    param(
        [Parameter(Mandatory)]
        [string]$MachineRoot,

        [Parameter(Mandatory)]
        [string]$ArchiveRoot,

        [Parameter(Mandatory)]
        [datetime]$CutoffDate,

        [Parameter(Mandatory)]
        [string[]]$Extensions
    )

    return @(
        Get-ChildItem -LiteralPath $MachineRoot -Recurse -File -Force |
            Where-Object {
                $IsInsideArchive = Test-IsInsideArchive -Path $_.FullName -ArchiveRoot $ArchiveRoot
                $IsOldEnough = $_.LastWriteTime -lt $CutoffDate
                $IsExtensionAllowed = Test-ExtensionAllowed -File $_ -Extensions $Extensions

                -not $IsInsideArchive -and $IsOldEnough -and $IsExtensionAllowed
            }
    )
}

function Get-DestinationPath {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$File,

        [Parameter(Mandatory)]
        [string]$MachineRoot,

        [Parameter(Mandatory)]
        [string]$ArchiveRoot
    )

    $Year = $File.LastWriteTime.Year.ToString()
    $RelativePath = $File.FullName.Substring($MachineRoot.Length).TrimStart("\")
    $RelativeDirectory = Split-Path -Path $RelativePath -Parent
    $DestinationDirectory = Join-Path $ArchiveRoot $Year

    if (-not [string]::IsNullOrWhiteSpace($RelativeDirectory)) {
        $DestinationDirectory = Join-Path $DestinationDirectory $RelativeDirectory
    }

    $DestinationFile = Join-Path $DestinationDirectory $File.Name

    if (Test-Path -LiteralPath $DestinationFile) {
        $Name = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
        $Extension = $File.Extension
        $Timestamp = Get-Date -Format "yyyyMMdd-HHmmssfff"

        $DestinationFile = Join-Path $DestinationDirectory "${Name}_${Timestamp}${Extension}"
    }

    return [PSCustomObject]@{
        Directory = $DestinationDirectory
        File      = $DestinationFile
    }
}
