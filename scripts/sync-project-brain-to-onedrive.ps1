param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OneDriveFolderName = "Council Project Brain"
)

$ErrorActionPreference = "Stop"

$OneDriveRoot = $env:OneDrive

if ([string]::IsNullOrWhiteSpace($OneDriveRoot)) {
    $OneDriveRoot = $env:OneDriveConsumer
}

if (
    [string]::IsNullOrWhiteSpace($OneDriveRoot) -or
    -not (Test-Path $OneDriveRoot)
) {
    throw "OneDrive path was not found."
}

$Source = Join-Path $ProjectRoot "project-brain"
$Destination = Join-Path $OneDriveRoot $OneDriveFolderName

if (-not (Test-Path $Source)) {
    throw "Project Brain folder was not found: $Source"
}

New-Item `
    -ItemType Directory `
    -Path $Destination `
    -Force | Out-Null

robocopy `
    $Source `
    $Destination `
    /MIR `
    /R:2 `
    /W:2 `
    /FFT `
    /Z `
    /XJ

$RobocopyExitCode = $LASTEXITCODE

if ($RobocopyExitCode -ge 8) {
    throw "OneDrive synchronization failed. Robocopy exit code: $RobocopyExitCode"
}

$SyncInfo = @"
Project: village_council_app
Source: $Source
Destination: $Destination
Last sync: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

Set-Content `
    -Path (Join-Path $Destination "SYNC_INFO.txt") `
    -Value $SyncInfo `
    -Encoding UTF8

Write-Host ""
Write-Host "Project Brain synchronized successfully." -ForegroundColor Green
Write-Host "Destination: $Destination" -ForegroundColor Cyan
