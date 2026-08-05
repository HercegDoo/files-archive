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

    if (
        -not (Test-ConfigProperty $Config "BasePath") -or
        [string]::IsNullOrWhiteSpace([string]$Config.BasePath)
    ) {
        throw "Config mora sadržavati BasePath."
    }

    $Config.BasePath = ([string]$Config.BasePath).TrimEnd("\", "/")

    if (-not (Test-Path -LiteralPath $Config.BasePath -PathType Container)) {
        throw "BasePath ne postoji: $($Config.BasePath)"
    }

    return $Config
}

function Get-MachineConfig {
    param(
        [Parameter(Mandatory)]
        [string]$MachineName,

        [AllowNull()]
        [object[]]$Machines
    )

    if ($null -eq $Machines) {
        return $null
    }

    return $Machines |
        Where-Object {
            (Test-ConfigProperty $_ "Name") -and
            ([string]$_.Name).Equals(
                $MachineName,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        } |
        Select-Object -First 1
}
