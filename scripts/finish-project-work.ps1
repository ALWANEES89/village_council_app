param(
    [Parameter(Mandatory = $true)]
    [string]$Title,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Implemented", "Tested", "Deployed")]
    [string]$Status,

    [Parameter(Mandatory = $true)]
    [string]$Summary,

    [string]$Files = "",
    [string]$Tests = "",
    [string]$NextSteps = "",
    [switch]$GitCommit,
    [string]$CommitMessage = ""
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot

$AddUpdateScript = Join-Path $PSScriptRoot "add-project-update.ps1"
$UpdateDashboardScript = Join-Path $PSScriptRoot "update-project-dashboard.ps1"
$SyncOneDriveScript = Join-Path $PSScriptRoot "sync-project-brain-to-onedrive.ps1"

foreach ($ScriptPath in @(
    $AddUpdateScript,
    $UpdateDashboardScript,
    $SyncOneDriveScript
)) {
    if (-not (Test-Path $ScriptPath)) {
        throw "Required script not found: $ScriptPath"
    }
}

& $AddUpdateScript `
    -Title $Title `
    -Status $Status `
    -Summary $Summary `
    -Files $Files `
    -Tests $Tests `
    -NextSteps $NextSteps `
    -ProjectRoot $ProjectRoot

& $UpdateDashboardScript -ProjectRoot $ProjectRoot

& $SyncOneDriveScript -ProjectRoot $ProjectRoot

if ($GitCommit) {
    if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
        $CommitMessage = "docs: update project brain - $Title"
    }

    Push-Location $ProjectRoot

    try {
        git add project-brain scripts

        $Changes = git status --porcelain

        if ([string]::IsNullOrWhiteSpace($Changes)) {
            Write-Host "No changes found for Git commit." -ForegroundColor Yellow
        }
        else {
            git commit -m $CommitMessage

            if ($LASTEXITCODE -ne 0) {
                throw "Git commit failed."
            }

            Write-Host "Git commit created successfully." -ForegroundColor Green
            Write-Host "Review the commit, then run: git push origin main" -ForegroundColor Yellow
        }
    }
    finally {
        Pop-Location
    }
}

Write-Host "Project work record completed successfully." -ForegroundColor Green
