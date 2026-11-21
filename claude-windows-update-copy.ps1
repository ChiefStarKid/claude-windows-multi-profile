# Update a pinned private copy of Claude Desktop from the Store-installed package.
# The Store profile updates itself; the copy only changes when you run this.
#
# Usage (quit the copy first):
#   .\claude-windows-update-copy.ps1 -AppDir C:\ClaudeProfiles\B\app -SmokeTest   # stage + test only, live copy untouched
#   .\claude-windows-update-copy.ps1 -AppDir C:\ClaudeProfiles\B\app              # stage + test + swap
#
# Rollback: delete "app", rename "app.old-<version>" back to "app".
param(
    [Parameter(Mandatory)] [string]$AppDir,
    [switch]$SmokeTest
)

$ErrorActionPreference = 'Stop'
$live    = $AppDir.TrimEnd('\')
$parent  = Split-Path $live
$suffix  = [guid]::NewGuid().ToString('N').Substring(0, 8)
$staged  = if ($SmokeTest) { Join-Path $env:TEMP "claude-smoke-$suffix" } else { Join-Path $parent 'app.new' }
$tmpData = Join-Path $env:TEMP "claude-smoke-data-$suffix"

function Fail($m) { Write-Host "FAIL: $m" -ForegroundColor Red; exit 1 }
function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }

Step 'Locate Store package'
$pkg = Get-AppxPackage -Name 'Claude*' | Select-Object -First 1
if (-not $pkg) { Fail 'Store package not found' }
$src = Join-Path $pkg.InstallLocation 'app'
if (-not (Test-Path "$src\claude.exe")) { Fail "claude.exe not found in $src" }
$newVer = (Get-Item "$src\claude.exe").VersionInfo.ProductVersion
$oldVer = if (Test-Path "$live\claude.exe") { (Get-Item "$live\claude.exe").VersionInfo.ProductVersion } else { 'none' }
Write-Host "Store: $newVer   Copy: $oldVer   Source: $src"
if ($newVer -eq $oldVer -and -not $SmokeTest) { Write-Host 'Already up to date.'; exit 0 }

Step 'Check the copy is not running'
$running = Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath -like "$live\*" }
if ($running -and -not $SmokeTest) { Fail "Copy is running (PIDs: $($running.ProcessId -join ', ')). Quit it and re-run." }

Step "Stage copy -> $staged"
if (Test-Path $staged) { Remove-Item $staged -Recurse -Force }
robocopy $src $staged /MIR /NJH /NJS /NFL /NDL /NP /R:1 /W:1 | Out-Null
if ($LASTEXITCODE -ge 8) { Fail "robocopy failed (exit $LASTEXITCODE). If access denied, run PowerShell as administrator." }
if (-not (Test-Path "$staged\claude.exe")) { Fail 'staged claude.exe missing' }
$srcCount = (Get-ChildItem $src -Recurse -File).Count
$dstCount = (Get-ChildItem $staged -Recurse -File).Count
if ($srcCount -ne $dstCount) { Fail "file count mismatch: source $srcCount vs staged $dstCount" }

Step 'Smoke test: start staged app with a throwaway data dir'
Start-Process "$staged\claude.exe" -ArgumentList "--user-data-dir=$tmpData" | Out-Null
Start-Sleep -Seconds 15
$alive = @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath -like "$staged\*" })
$dataMade = Test-Path $tmpData
$alive | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 3
Remove-Item $tmpData -Recurse -Force -ErrorAction SilentlyContinue
if (-not ($alive.Count -gt 0 -and $dataMade)) {
    if ($SmokeTest) { Remove-Item $staged -Recurse -Force -ErrorAction SilentlyContinue }
    Fail "staged app did not start cleanly (processes: $($alive.Count), data dir created: $dataMade)"
}
Write-Host "PASS: staged app started ($($alive.Count) processes)" -ForegroundColor Green

if ($SmokeTest) {
    Remove-Item $staged -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "`nSMOKE TEST PASSED. Live copy untouched." -ForegroundColor Green
    exit 0
}

Step 'Swap staged copy into place'
$backup = Join-Path $parent "app.old-$oldVer"
if (Test-Path $backup) { Remove-Item $backup -Recurse -Force }
Rename-Item $live $backup
Rename-Item $staged $live
Write-Host "`nUPDATED: $oldVer -> $((Get-Item "$live\claude.exe").VersionInfo.ProductVersion)" -ForegroundColor Green
Write-Host "Rollback copy kept at: $backup (delete once stable). Relaunch only via the copy's own launcher."
