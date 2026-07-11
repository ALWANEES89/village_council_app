param(
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][ValidateSet("Planned","Implemented","Tested","Deployed","Rolled Back")][string]$Status,
    [Parameter(Mandatory=$true)][string]$Summary,
    [string]$Files = "",
    [string]$Tests = "",
    [string]$NextSteps = "",
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$changeLog = Join-Path $ProjectRoot "project-brain\10_CHANGELOG.md"
$date = Get-Date -Format "yyyy-MM-dd HH:mm"

$entry = @"

## $date — $Title
- الحالة: **$Status**
- الملخص: $Summary
- الملفات المتأثرة: $Files
- الاختبارات: $Tests
- الخطوات القادمة: $NextSteps
"@

Add-Content -Path $changeLog -Value $entry -Encoding UTF8
Write-Host "تمت إضافة التحديث إلى سجل المشروع." -ForegroundColor Green
