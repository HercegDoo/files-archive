if (-not (Test-Path Variable:script:ArchiveLogMaxBytes)) {
    $script:ArchiveLogMaxBytes = [int64](10 * 1MB)
}

if (-not (Test-Path Variable:script:ArchiveLogRotateCount)) {
    $script:ArchiveLogRotateCount = 5
}

function Set-ArchiveLogLimit {
    param(
        [Parameter(Mandatory)]
        [double]$MaxLogSizeMB,

        [Parameter(Mandatory)]
        [int]$LogRotateCount
    )

    if ($MaxLogSizeMB -le 0) {
        throw "Velicina log fajla mora biti veca od 0 MB."
    }

    if ($LogRotateCount -lt 1) {
        throw "Broj rotiranih logova mora biti najmanje 1."
    }

    $script:ArchiveLogMaxBytes = [int64][math]::Ceiling($MaxLogSizeMB * 1MB)
    $script:ArchiveLogRotateCount = $LogRotateCount
}

function Get-ArchiveLogTextByteCount {
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    return [System.Text.Encoding]::UTF8.GetByteCount($Text)
}

function Get-RotatedArchiveLogPath {
    param(
        [Parameter(Mandatory)]
        [string]$LogFile,

        [Parameter(Mandatory)]
        [int]$Index
    )

    return "$LogFile.$Index.zip"
}

function Get-LegacyRotatedArchiveLogPath {
    param(
        [Parameter(Mandatory)]
        [string]$LogFile,

        [Parameter(Mandatory)]
        [int]$Index
    )

    return "$LogFile.$Index"
}

function Compress-ArchiveLogFile {
    param(
        [Parameter(Mandatory)]
        [string]$SourceLogFile,

        [Parameter(Mandatory)]
        [string]$DestinationZipFile,

        [switch]$RemoveSource
    )

    if (Test-Path -LiteralPath $DestinationZipFile -PathType Leaf) {
        Remove-Item -LiteralPath $DestinationZipFile -Force
    }

    Compress-Archive -LiteralPath $SourceLogFile -DestinationPath $DestinationZipFile -Force

    if ($RemoveSource) {
        Remove-Item -LiteralPath $SourceLogFile -Force
    }
}

function Convert-LegacyRotatedArchiveLogs {
    param(
        [Parameter(Mandatory)]
        [string]$LogFile
    )

    for ($Index = 1; $Index -le $script:ArchiveLogRotateCount; $Index++) {
        $LegacyLogFile = Get-LegacyRotatedArchiveLogPath -LogFile $LogFile -Index $Index
        $RotatedLogFile = Get-RotatedArchiveLogPath -LogFile $LogFile -Index $Index

        if (Test-Path -LiteralPath $LegacyLogFile -PathType Leaf) {
            Compress-ArchiveLogFile -SourceLogFile $LegacyLogFile -DestinationZipFile $RotatedLogFile -RemoveSource
        }
    }
}

function Limit-ArchiveLogFile {
    param(
        [Parameter(Mandatory)]
        [string]$LogFile,

        [Parameter(Mandatory)]
        [string]$PendingLine
    )

    Convert-LegacyRotatedArchiveLogs -LogFile $LogFile

    if (-not (Test-Path -LiteralPath $LogFile -PathType Leaf)) {
        return
    }

    $PendingBytes = Get-ArchiveLogTextByteCount -Text ($PendingLine + [Environment]::NewLine)
    $LogItem = Get-Item -LiteralPath $LogFile

    if (($LogItem.Length + $PendingBytes) -le $script:ArchiveLogMaxBytes) {
        return
    }

    $OldestLogFile = Get-RotatedArchiveLogPath -LogFile $LogFile -Index $script:ArchiveLogRotateCount

    if (Test-Path -LiteralPath $OldestLogFile -PathType Leaf) {
        Remove-Item -LiteralPath $OldestLogFile -Force
    }

    for ($Index = $script:ArchiveLogRotateCount - 1; $Index -ge 1; $Index--) {
        $SourceLogFile = Get-RotatedArchiveLogPath -LogFile $LogFile -Index $Index

        if (Test-Path -LiteralPath $SourceLogFile -PathType Leaf) {
            $DestinationLogFile = Get-RotatedArchiveLogPath -LogFile $LogFile -Index ($Index + 1)

            Move-Item -LiteralPath $SourceLogFile -Destination $DestinationLogFile -Force
        }
    }

    $FirstRotatedLogFile = Get-RotatedArchiveLogPath -LogFile $LogFile -Index 1

    Compress-ArchiveLogFile -SourceLogFile $LogFile -DestinationZipFile $FirstRotatedLogFile -RemoveSource
}

function Write-ArchiveLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [string]$LogFile
    )

    $LogDirectory = Split-Path -Parent $LogFile

    if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$Timestamp] $Message"

    Limit-ArchiveLogFile -LogFile $LogFile -PendingLine $Line

    Add-Content -LiteralPath $LogFile -Value $Line -Encoding UTF8
    Write-Host $Line
}
