# Read-only health check for a Store profile + private-copy profile setup. Changes nothing.
#
# Usage:
#   .\claude-windows-diagnose.ps1 -StoreDataDir "$env:LOCALAPPDATA\Claude-A" -CopyAppDir C:\ClaudeProfiles\B\app
#
# Checks: Store/copy versions, which exe each running claude.exe came from, and the log lines
# that signal the Store build relocating profile data (see README.md "The Store trap").
param(
    [string]$StoreDataDir = (Join-Path $env:LOCALAPPDATA 'Claude-A'),
    [string]$CopyAppDir
)

function Section($m) { Write-Host "`n== $m" -ForegroundColor Cyan }

Section 'Versions'
$pkg = Get-AppxPackage -Name 'Claude*' | Select-Object -First 1
if ($pkg) { Write-Host "Store package : $($pkg.Version)   ($($pkg.InstallLocation))" } else { Write-Host 'Store package : not installed' }
if ($CopyAppDir -and (Test-Path "$CopyAppDir\claude.exe")) {
    Write-Host "Private copy  : $((Get-Item "$CopyAppDir\claude.exe").VersionInfo.ProductVersion)   ($CopyAppDir)"
} elseif ($CopyAppDir) { Write-Host "Private copy  : claude.exe NOT FOUND in $CopyAppDir" -ForegroundColor Red }

Section 'Running instances (grouped by exe path)'
$procs = Get-CimInstance Win32_Process -Filter "Name='claude.exe'" | Where-Object { $_.ExecutablePath -and $_.ExecutablePath -notmatch '\\claude-code\\' }  # skip the embedded Claude Code CLI
if (-not $procs) { Write-Host '(none running)' }
$procs | Group-Object ExecutablePath | ForEach-Object {
    $main = $_.Group | Where-Object { $_.CommandLine -notmatch '--type=' } | Select-Object -First 1
    $dd = '(none - uses the app default!)'
    if ($main -and $main.CommandLine -match '--user-data-dir=(?:"([^"]+)"|(\S+))') {
        $dd = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
    }
    Write-Host ("{0} process(es)  exe: {1}`n    user-data-dir: {2}" -f $_.Count, $_.Name, $dd)
}

Section 'Store data-location trap'
$claudeData = Join-Path $env:LOCALAPPDATA 'Claude-Data'
if (Test-Path $claudeData) {
    Write-Host "Claude-Data exists. A junction here is the intended fix; a real folder means the Store build relocated data:" -ForegroundColor Yellow
    Get-ChildItem $claudeData -Force | ForEach-Object {
        $kind = if ($_.LinkType) { "$($_.LinkType) -> $($_.Target)" } else { 'real folder' }
        Write-Host "    $($_.Name)  [$kind]"
    }
} else { Write-Host 'No Claude-Data folder (good - nothing relocated).' }

foreach ($dir in @($StoreDataDir, (Join-Path $env:LOCALAPPDATA 'Claude'))) {
    $log = Join-Path $dir 'logs\main.log'
    if (Test-Path $log) {
        Write-Host "`nLast relevant lines in $log"
        Select-String -Path $log -Pattern 'user-data-move|token cache location|Version changed|not enabling auto-updates' |
            Select-Object -Last 6 | ForEach-Object { Write-Host "    $($_.Line.Trim())" }
    }
}
