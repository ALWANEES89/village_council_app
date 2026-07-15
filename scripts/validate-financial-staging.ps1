param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$ProjectId
)

$ErrorActionPreference = 'Stop'

if ($ProjectId -eq 'alrahmat-console') {
  throw 'Production project alrahmat-console is explicitly forbidden.'
}

$requiredFiles = @(
  'firebase.json',
  'firestore.rules',
  'firestore.indexes.json',
  'storage.rules',
  'functions/package.json',
  'scripts/migrate-financial-v1.js'
)

foreach ($file in $requiredFiles) {
  if (-not (Test-Path -LiteralPath $file)) {
    throw "Required file is missing: $file"
  }
}

$firebase = Get-Command firebase -ErrorAction SilentlyContinue
if (-not $firebase) {
  throw 'Firebase CLI was not found. No action was performed.'
}

$null = firebase login:list --json | ConvertFrom-Json
$projects = firebase projects:list --json | ConvertFrom-Json
$knownProjectIds = @($projects.result | ForEach-Object { $_.projectId })
if ($ProjectId -notin $knownProjectIds) {
  throw "The explicit staging project is not visible to the current Firebase account: $ProjectId"
}

$package = Get-Content -Raw -Encoding UTF8 functions/package.json | ConvertFrom-Json
if ($package.engines.node -ne '20') {
  throw 'functions/package.json must require Node 20.'
}

Write-Host 'Validation complete. No deploy, migration, or project switch was performed.'
Write-Host "Validated staging project: $ProjectId"
Write-Host 'Proposed later steps: emulator tests, explicit staging deploy, index wait, migration dry-run, independent approval.'
