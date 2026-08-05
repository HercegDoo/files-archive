function Test-ConfigProperty {
    param(
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory)]
        [string]$Name
    )

    return (
        $null -ne $Object -and
        $Object.PSObject.Properties.Name -contains $Name
    )
}

function Resolve-ArchivePath {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$BaseDirectory
    )

    $TrimmedPath = ([string]$Path).TrimEnd("\", "/")

    if ([System.IO.Path]::IsPathRooted($TrimmedPath)) {
        return [System.IO.Path]::GetFullPath($TrimmedPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BaseDirectory $TrimmedPath))
}

function Import-ArchiveConfig {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Config fajl ne postoji: $Path"
    }

    try {
        $Config = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 |
            ConvertFrom-Json
    }
    catch {
        throw "Config nije ispravan JSON: $($_.Exception.Message)"
    }

    $ConfigDirectory = Split-Path -Parent $Path
    $HasBasePath = (
        (Test-ConfigProperty $Config "BasePath") -and
        -not [string]::IsNullOrWhiteSpace([string]$Config.BasePath)
    )
    $HasTargets = (
        (Test-ConfigProperty $Config "Targets") -and
        @($Config.Targets).Count -gt 0
    )

    if (-not $HasBasePath -and -not $HasTargets) {
        throw "Config mora sadrzavati Targets ili BasePath."
    }

    if ($HasBasePath) {
        $Config.BasePath = Resolve-ArchivePath -Path $Config.BasePath -BaseDirectory $ConfigDirectory

        if (-not (Test-Path -LiteralPath $Config.BasePath -PathType Container)) {
            throw "BasePath ne postoji: $($Config.BasePath)"
        }
    }

    if ($HasTargets) {
        foreach ($Target in @($Config.Targets)) {
            if (
                -not (Test-ConfigProperty $Target "Path") -or
                [string]::IsNullOrWhiteSpace([string]$Target.Path)
            ) {
                throw "Svaki Targets unos mora sadrzavati Path."
            }

            $Target.Path = Resolve-ArchivePath -Path $Target.Path -BaseDirectory $ConfigDirectory

            if (-not (Test-Path -LiteralPath $Target.Path -PathType Container)) {
                throw "Target putanja ne postoji: $($Target.Path)"
            }
        }
    }

    return $Config
}

function Get-ArchiveTargets {
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    if (
        (Test-ConfigProperty $Config "Targets") -and
        @($Config.Targets).Count -gt 0
    ) {
        return @($Config.Targets)
    }

    return @(
        [PSCustomObject]@{
            Name = "Default"
            Path = $Config.BasePath
        }
    )
}

function Get-ArchiveTargetName {
    param(
        [Parameter(Mandatory)]
        [object]$Target
    )

    if (
        (Test-ConfigProperty $Target "Name") -and
        -not [string]::IsNullOrWhiteSpace([string]$Target.Name)
    ) {
        return [string]$Target.Name
    }

    $LeafName = Split-Path -Path ([string]$Target.Path) -Leaf

    if (-not [string]::IsNullOrWhiteSpace($LeafName)) {
        return $LeafName
    }

    return [string]$Target.Path
}
