function Get-CutoffDate {
    param(
        [Parameter(Mandatory)]
        [double]$OlderThanSeconds
    )

    if ($OlderThanSeconds -le 0) {
        throw "Broj sekundi mora biti veci od 0."
    }

    return (Get-Date).AddSeconds(-$OlderThanSeconds)
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

function Get-NormalizedDirectoryPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return [System.IO.Path]::GetFullPath($Path).TrimEnd("\", "/")
}

function Test-IsSamePath {
    param(
        [Parameter(Mandatory)]
        [string]$Left,

        [Parameter(Mandatory)]
        [string]$Right
    )

    $NormalizedLeft = Get-NormalizedDirectoryPath -Path $Left
    $NormalizedRight = Get-NormalizedDirectoryPath -Path $Right

    return [string]::Equals(
        $NormalizedLeft,
        $NormalizedRight,
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Test-ArchivePathHasDateTokens {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return $Path -match "\{(year|month)\}"
}

function ConvertTo-ArchivePathRegex {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $NormalizedPath = (Get-NormalizedDirectoryPath -Path $Path) + "\"
    $NormalizedPath = [regex]::Replace(
        $NormalizedPath,
        "\{year\}",
        "ARCHIVE_YEAR_TOKEN",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    $NormalizedPath = [regex]::Replace(
        $NormalizedPath,
        "\{month\}",
        "ARCHIVE_MONTH_TOKEN",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    $EscapedPath = [regex]::Escape($NormalizedPath)
    $EscapedPath = $EscapedPath.Replace("ARCHIVE_YEAR_TOKEN", "\d{4}")
    $EscapedPath = $EscapedPath.Replace("ARCHIVE_MONTH_TOKEN", "\d{2}")

    return "^$EscapedPath"
}

function Expand-ArchivePathTemplate {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [datetime]$Date
    )

    $ExpandedPath = [regex]::Replace(
        $Path,
        "\{year\}",
        $Date.Year.ToString("0000"),
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    $ExpandedPath = [regex]::Replace(
        $ExpandedPath,
        "\{month\}",
        $Date.Month.ToString("00"),
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    return Get-NormalizedDirectoryPath -Path $ExpandedPath
}

function Get-ArchiveDate {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$File,

        [Parameter(Mandatory)]
        [string]$DateField
    )

    switch ($DateField) {
        "LastWriteTime" {
            return $File.LastWriteTime
        }
        "CreationTime" {
            return $File.CreationTime
        }
        default {
            throw "Nepodrzan DateField: $DateField"
        }
    }
}

function Test-IsInsideArchive {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ArchiveRoot
    )

    $NormalizedPath = [System.IO.Path]::GetFullPath($Path)
    $ArchiveRootPattern = ConvertTo-ArchivePathRegex -Path $ArchiveRoot

    return $NormalizedPath -match $ArchiveRootPattern
}

function Get-ArchivableFiles {
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [string]$ArchiveRoot,

        [Parameter(Mandatory)]
        [datetime]$CutoffDate,

        [Parameter(Mandatory)]
        [string]$DateField,

        [Parameter(Mandatory)]
        [string[]]$Extensions
    )

    if (Test-IsSamePath -Left $SourceRoot -Right $ArchiveRoot) {
        throw "Arhiva putanja ne smije biti ista kao izvorna putanja: $SourceRoot"
    }

    $ArchiveRootIsInsideSource = Test-IsInsideArchive -Path $ArchiveRoot -ArchiveRoot $SourceRoot

    return @(
        Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Force |
            Where-Object {
                $IsInsideArchive = (
                    $ArchiveRootIsInsideSource -and
                    (Test-IsInsideArchive -Path $_.FullName -ArchiveRoot $ArchiveRoot)
                )
                $ArchiveDate = Get-ArchiveDate -File $_ -DateField $DateField
                $IsOldEnough = $ArchiveDate -lt $CutoffDate
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
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [string]$ArchiveRoot,

        [Parameter(Mandatory)]
        [string]$DateField
    )

    $ArchiveDate = Get-ArchiveDate -File $File -DateField $DateField
    $Year = $ArchiveDate.Year.ToString("0000")
    $RelativePath = $File.FullName.Substring($SourceRoot.Length).TrimStart("\", "/")
    $RelativeDirectory = Split-Path -Path $RelativePath -Parent
    $ExpandedArchiveRoot = Expand-ArchivePathTemplate -Path $ArchiveRoot -Date $ArchiveDate

    if (Test-ArchivePathHasDateTokens -Path $ArchiveRoot) {
        $DestinationDirectory = $ExpandedArchiveRoot
    }
    else {
        $DestinationDirectory = Join-Path $ExpandedArchiveRoot $Year
    }

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
