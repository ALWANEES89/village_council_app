$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$brainRoot = Join-Path $projectRoot "project-brain"
$tasksPath = Join-Path $brainRoot "tasks.json"
$dashboardPath = Join-Path $brainRoot "PROJECT_DASHBOARD.md"

if (-not (Test-Path $tasksPath)) {
    throw "لم يتم العثور على ملف المهام: $tasksPath"
}

$tasks = Get-Content -Path $tasksPath -Raw -Encoding UTF8 | ConvertFrom-Json
$tasks = @($tasks)

$totalTasks = $tasks.Count
$doneTasks = @($tasks | Where-Object { $_.status -eq "done" }).Count
$inProgressTasks = @($tasks | Where-Object { $_.status -eq "in_progress" }).Count
$pendingTasks = @($tasks | Where-Object { $_.status -eq "pending" }).Count
$blockedTasks = @($tasks | Where-Object { $_.status -eq "blocked" }).Count

if ($totalTasks -gt 0) {
    $overallProgress = [math]::Round(
        (($tasks | ForEach-Object {
            if ($null -eq $_.progress) { 0 } else { [double]$_.progress }
        } | Measure-Object -Average).Average),
        0
    )
}
else {
    $overallProgress = 0
}

$areaRows = @()

$areas = $tasks | Group-Object area | Sort-Object Name

foreach ($area in $areas) {
    $areaTasks = @($area.Group)
    $areaTotal = $areaTasks.Count

    if ($areaTotal -gt 0) {
        $areaProgress = [math]::Round(
            (($areaTasks | ForEach-Object {
                if ($null -eq $_.progress) { 0 } else { [double]$_.progress }
            } | Measure-Object -Average).Average),
            0
        )
    }
    else {
        $areaProgress = 0
    }

    $areaRows += "| $($area.Name) | $areaTotal | $($areaProgress)% |"
}

$taskRows = @()

foreach ($task in ($tasks | Sort-Object area, id)) {
    $progress = if ($null -eq $task.progress) { 0 } else { $task.progress }
    $priority = if ([string]::IsNullOrWhiteSpace([string]$task.priority)) { "-" } else { $task.priority }

    $taskRows += "| $($task.id) | $($task.title) | $($task.area) | $($task.status) | $($progress)% | $priority |"
}

if ($areaRows.Count -eq 0) {
    $areaRows = @("| لا توجد أقسام | 0 | 0% |")
}

if ($taskRows.Count -eq 0) {
    $taskRows = @("| - | لا توجد مهام | - | - | 0% | - |")
}

$updatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$dashboard = @"
# لوحة متابعة مشروع تطبيق المجلس

آخر تحديث: $updatedAt

## الملخص العام

| البيان | القيمة |
|---|---:|
| إجمالي المهام | $totalTasks |
| المهام المكتملة | $doneTasks |
| قيد التنفيذ | $inProgressTasks |
| لم تبدأ | $pendingTasks |
| متوقفة | $blockedTasks |
| نسبة الإنجاز الكلية | $($overallProgress)% |

## التقدم حسب القسم

| القسم | عدد المهام | نسبة الإنجاز |
|---|---:|---:|
$($areaRows -join "`r`n")

## تفاصيل المهام

| الرقم | المهمة | القسم | الحالة | الإنجاز | الأولوية |
|---|---|---|---|---:|---|
$($taskRows -join "`r`n")

## حالات المهام

- done: مكتملة
- in_progress: قيد التنفيذ
- pending: لم تبدأ
- blocked: متوقفة

## ملف المصدر

تم إنشاء هذه اللوحة من الملف:

project-brain/tasks.json

لا تعدل هذه اللوحة يدويًا. عدل ملف tasks.json ثم شغّل السكربت مرة أخرى.
"@

Set-Content -Path $dashboardPath -Value $dashboard -Encoding UTF8

Write-Host ""
Write-Host "تم تحديث لوحة متابعة المشروع بنجاح." -ForegroundColor Green
Write-Host "المسار: $dashboardPath" -ForegroundColor Green
Write-Host "نسبة الإنجاز الكلية: $($overallProgress)%" -ForegroundColor Cyan
Write-Host "المهام المكتملة: $doneTasks من $totalTasks" -ForegroundColor Cyan
