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

    $NormalizedPath = Get-NormalizedDirectoryPath -Path $Path
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

    return "^$EscapedPath([\\/]|$)"
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

function Get-FileRelativeDirectoryDepth {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$File,

        [Parameter(Mandatory)]
        [string]$SourceRoot
    )

    $RelativePath = $File.FullName.Substring($SourceRoot.Length).TrimStart("\", "/")
    $RelativeDirectory = Split-Path -Path $RelativePath -Parent

    if ([string]::IsNullOrWhiteSpace($RelativeDirectory)) {
        return 0
    }

    return @($RelativeDirectory -split "[\\/]+" | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    }).Count
}

function Test-FileDepthAllowed {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$File,

        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [AllowNull()]
        [object]$MaxDepth
    )

    if ($null -eq $MaxDepth) {
        return $true
    }

    $Depth = Get-FileRelativeDirectoryDepth -File $File -SourceRoot $SourceRoot

    return $Depth -le [int]$MaxDepth
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

function Get-SourceFilesInDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [int]$CurrentDepth,

        [AllowNull()]
        [object]$MaxDepth
    )

    foreach ($File in @(Get-ChildItem -LiteralPath $Directory -File -Force)) {
        $File
    }

    if ($null -ne $MaxDepth -and $CurrentDepth -ge [int]$MaxDepth) {
        return
    }

    foreach ($ChildDirectory in @(Get-ChildItem -LiteralPath $Directory -Directory -Force)) {
        Get-SourceFilesInDirectory -Directory $ChildDirectory.FullName -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth
    }
}

function Get-SourceFiles {
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [AllowNull()]
        [object]$MaxDepth
    )

    return @(
        Get-SourceFilesInDirectory -Directory $SourceRoot -CurrentDepth 0 -MaxDepth $MaxDepth
    )
}

function Get-RelativeArchivePath {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Root
    )

    return [System.IO.Path]::GetFullPath($Path).Substring(
        (Get-NormalizedDirectoryPath -Path $Root).Length
    ).TrimStart("\", "/").Replace("\", "/")
}

function ConvertTo-ArchiveGlobRegex {
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $NormalizedPattern = $Pattern.Trim().Replace("\", "/").TrimStart("/")
    $NormalizedPattern = $NormalizedPattern.TrimEnd("/")
    $ContainsSlash = $NormalizedPattern.Contains("/")
    $EscapedPattern = [regex]::Escape($NormalizedPattern)
    $EscapedPattern = $EscapedPattern.Replace("\*\*", ".*")
    $EscapedPattern = $EscapedPattern.Replace("\*", "[^/]*")
    $EscapedPattern = $EscapedPattern.Replace("\?", "[^/]")

    if ($ContainsSlash) {
        return "^$EscapedPattern$"
    }

    return "(^|.*/)$EscapedPattern$"
}

function Test-ArchiveRelativePathPattern {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $NormalizedPattern = $Pattern.Trim()

    if (
        [string]::IsNullOrWhiteSpace($NormalizedPattern) -or
        $NormalizedPattern.StartsWith("#")
    ) {
        return $false
    }

    if ($NormalizedPattern.StartsWith("!")) {
        $NormalizedPattern = $NormalizedPattern.Substring(1)
    }

    if ([string]::IsNullOrWhiteSpace($NormalizedPattern)) {
        return $false
    }

    $NormalizedRelativePath = $RelativePath.Replace("\", "/").Trim("/")
    $Regex = ConvertTo-ArchiveGlobRegex -Pattern $NormalizedPattern

    return $NormalizedRelativePath -match $Regex
}

function Resolve-ArchiveIgnoreFilePath {
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [AllowNull()]
        [string]$IgnoreFile
    )

    if ([string]::IsNullOrWhiteSpace($IgnoreFile)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($IgnoreFile)) {
        return $IgnoreFile
    }

    return Join-Path $SourceRoot $IgnoreFile
}

function Get-ArchiveIgnorePatterns {
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [AllowNull()]
        [string]$IgnoreFile,

        [bool]$Enabled = $true
    )

    if (-not $Enabled) {
        return @()
    }

    $IgnoreFilePath = Resolve-ArchiveIgnoreFilePath -SourceRoot $SourceRoot -IgnoreFile $IgnoreFile

    if ([string]::IsNullOrWhiteSpace($IgnoreFilePath)) {
        return @()
    }

    if (-not (Test-Path -LiteralPath $IgnoreFilePath -PathType Leaf)) {
        return @()
    }

    return @(
        Get-Content -LiteralPath $IgnoreFilePath -Encoding UTF8 |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                -not $_.StartsWith("#")
            }
    )
}

function Test-IsArchiveIgnoreFile {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$File,

        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [AllowNull()]
        [string]$IgnoreFile,

        [bool]$Enabled = $true
    )

    if (-not $Enabled) {
        return $false
    }

    $IgnoreFilePath = Resolve-ArchiveIgnoreFilePath -SourceRoot $SourceRoot -IgnoreFile $IgnoreFile

    if ([string]::IsNullOrWhiteSpace($IgnoreFilePath)) {
        return $false
    }

    return Test-IsSamePath -Left $File.FullName -Right $IgnoreFilePath
}

function ConvertTo-ArchiveIgnoreRegex {
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $NormalizedPattern = $Pattern.Trim().Replace("\", "/")

    if ($NormalizedPattern.StartsWith("!")) {
        $NormalizedPattern = $NormalizedPattern.Substring(1)
    }

    $RootAnchored = $NormalizedPattern.StartsWith("/")
    $DirectoryOnly = $NormalizedPattern.EndsWith("/")
    $NormalizedPattern = $NormalizedPattern.Trim("/")

    if ([string]::IsNullOrWhiteSpace($NormalizedPattern)) {
        return $null
    }

    $ContainsSlash = $NormalizedPattern.Contains("/")
    $EscapedPattern = [regex]::Escape($NormalizedPattern)
    $EscapedPattern = $EscapedPattern.Replace("\*\*", ".*")
    $EscapedPattern = $EscapedPattern.Replace("\*", "[^/]*")
    $EscapedPattern = $EscapedPattern.Replace("\?", "[^/]")

    if ($DirectoryOnly) {
        if ($RootAnchored -or $ContainsSlash) {
            return "^$EscapedPattern(/.*)?$"
        }

        return "(^|.*/)$EscapedPattern(/.*)?$"
    }

    if ($RootAnchored -or $ContainsSlash) {
        return "^$EscapedPattern$"
    }

    return "(^|.*/)$EscapedPattern$"
}

function Test-ArchiveIgnoredRelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath,

        [AllowEmptyCollection()]
        [string[]]$IgnorePatterns
    )

    if (@($IgnorePatterns).Count -eq 0) {
        return $false
    }

    $NormalizedRelativePath = $RelativePath.Replace("\", "/").Trim("/")
    $Ignored = $false

    foreach ($Pattern in @($IgnorePatterns)) {
        if ([string]::IsNullOrWhiteSpace([string]$Pattern)) {
            continue
        }

        $PatternText = ([string]$Pattern).Trim()
        $IsNegated = $PatternText.StartsWith("!")
        $Regex = ConvertTo-ArchiveIgnoreRegex -Pattern $PatternText

        if ($null -eq $Regex) {
            continue
        }

        if ($NormalizedRelativePath -match $Regex) {
            $Ignored = -not $IsNegated
        }
    }

    return $Ignored
}

function Test-ArchiveIgnoredFile {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$File,

        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [AllowEmptyCollection()]
        [string[]]$IgnorePatterns
    )

    $RelativePath = Get-RelativeArchivePath -Path $File.FullName -Root $SourceRoot

    return Test-ArchiveIgnoredRelativePath -RelativePath $RelativePath -IgnorePatterns $IgnorePatterns
}

function Test-ProtectedEmptyDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [AllowEmptyCollection()]
        [string[]]$ProtectedPatterns
    )

    $RelativePath = Get-RelativeArchivePath -Path $Directory -Root $SourceRoot

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return $false
    }

    $Protected = $false

    foreach ($Pattern in @($ProtectedPatterns)) {
        if ([string]::IsNullOrWhiteSpace([string]$Pattern)) {
            continue
        }

        $PatternText = ([string]$Pattern).Trim()
        $IsNegated = $PatternText.StartsWith("!")

        if (Test-ArchiveRelativePathPattern -RelativePath $RelativePath -Pattern $PatternText) {
            $Protected = -not $IsNegated
        }
    }

    return $Protected
}

function Test-DirectoryIsEmpty {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return @(Get-ChildItem -LiteralPath $Path -Force).Count -eq 0
}

function Get-ArchiveDirectoryForRelativeDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$ArchiveRoot,

        [Parameter(Mandatory)]
        [string]$RelativeDirectory,

        [Parameter(Mandatory)]
        [datetime]$Date
    )

    $ExpandedArchiveRoot = Expand-ArchivePathTemplate -Path $ArchiveRoot -Date $Date

    $DestinationDirectory = $ExpandedArchiveRoot

    if (-not [string]::IsNullOrWhiteSpace($RelativeDirectory)) {
        $DestinationDirectory = Join-Path $DestinationDirectory $RelativeDirectory
    }

    return $DestinationDirectory
}

function Ensure-ProtectedEmptyDirectoriesInArchive {
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [string]$ArchiveRoot,

        [AllowEmptyCollection()]
        [string[]]$ProtectedPatterns,

        [Parameter(Mandatory)]
        [datetime]$Date
    )

    if (@($ProtectedPatterns).Count -eq 0) {
        return 0
    }

    $Created = 0

    $Directories = @(
        Get-ChildItem -LiteralPath $SourceRoot -Directory -Recurse -Force |
            Sort-Object FullName
    )

    foreach ($Directory in $Directories) {
        if (Test-IsInsideArchive -Path $Directory.FullName -ArchiveRoot $ArchiveRoot) {
            continue
        }

        if (-not (Test-DirectoryIsEmpty -Path $Directory.FullName)) {
            continue
        }

        if (-not (Test-ProtectedEmptyDirectory -Directory $Directory.FullName -SourceRoot $SourceRoot -ProtectedPatterns $ProtectedPatterns)) {
            continue
        }

        $RelativePath = Get-RelativeArchivePath -Path $Directory.FullName -Root $SourceRoot
        $ArchiveDirectory = Get-ArchiveDirectoryForRelativeDirectory -ArchiveRoot $ArchiveRoot -RelativeDirectory $RelativePath -Date $Date

        if (-not (Test-Path -LiteralPath $ArchiveDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $ArchiveDirectory -Force | Out-Null
            $Created++
        }
    }

    return $Created
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
        [string[]]$Extensions,

        [AllowNull()]
        [object]$MaxDepth = $null,

        [AllowEmptyCollection()]
        [string[]]$IgnorePatterns = @(),

        [AllowNull()]
        [string]$IgnoreFile = $null,

        [bool]$IgnoreFileEnabled = $true
    )

    if (Test-IsSamePath -Left $SourceRoot -Right $ArchiveRoot) {
        throw "Arhiva putanja ne smije biti ista kao izvorna putanja: $SourceRoot"
    }

    $ArchiveRootIsInsideSource = Test-IsInsideArchive -Path $ArchiveRoot -ArchiveRoot $SourceRoot

    return @(
        Get-SourceFiles -SourceRoot $SourceRoot -MaxDepth $MaxDepth |
            Where-Object {
                $IsInsideArchive = (
                    $ArchiveRootIsInsideSource -and
                    (Test-IsInsideArchive -Path $_.FullName -ArchiveRoot $ArchiveRoot)
                )
                $ArchiveDate = Get-ArchiveDate -File $_ -DateField $DateField
                $IsOldEnough = $ArchiveDate -lt $CutoffDate
                $IsExtensionAllowed = Test-ExtensionAllowed -File $_ -Extensions $Extensions
                $IsDepthAllowed = Test-FileDepthAllowed -File $_ -SourceRoot $SourceRoot -MaxDepth $MaxDepth
                $IsIgnored = Test-ArchiveIgnoredFile -File $_ -SourceRoot $SourceRoot -IgnorePatterns $IgnorePatterns
                $IsIgnoreFile = Test-IsArchiveIgnoreFile -File $_ -SourceRoot $SourceRoot -IgnoreFile $IgnoreFile -Enabled:$IgnoreFileEnabled

                -not $IsInsideArchive -and -not $IsIgnored -and -not $IsIgnoreFile -and $IsOldEnough -and $IsExtensionAllowed -and $IsDepthAllowed
            }
    )
}

function Remove-EmptySourceDirectories {
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [string]$ArchiveRoot,

        [AllowEmptyCollection()]
        [string[]]$ProtectedPatterns = @()
    )

    $Removed = 0

    $Directories = @(
        Get-ChildItem -LiteralPath $SourceRoot -Directory -Recurse -Force |
            Sort-Object @{ Expression = { $_.FullName.Length }; Descending = $true }
    )

    foreach ($Directory in $Directories) {
        if (Test-IsInsideArchive -Path $Directory.FullName -ArchiveRoot $ArchiveRoot) {
            continue
        }

        if (@(Get-ChildItem -LiteralPath $Directory.FullName -Force).Count -gt 0) {
            continue
        }

        if (Test-ProtectedEmptyDirectory -Directory $Directory.FullName -SourceRoot $SourceRoot -ProtectedPatterns $ProtectedPatterns) {
            continue
        }

        Remove-Item -LiteralPath $Directory.FullName -Force
        $Removed++
    }

    return $Removed
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
