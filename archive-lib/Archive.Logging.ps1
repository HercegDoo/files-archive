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

    Add-Content -LiteralPath $LogFile -Value $Line -Encoding UTF8
    Write-Host $Line
}
