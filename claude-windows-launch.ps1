# Launch an isolated Claude Desktop + Claude Code profile on Windows.
#
# Two things must be isolated, and they are separate stores:
#   --user-data-dir     Electron data: login, session index, VM bundles, app config
#   CLAUDE_CONFIG_DIR   Claude Code home: transcripts, memory, settings, hooks, skills
#
# Usage:
#   # Store-installed app (auto-updates) - profile "A"
#   .\claude-windows-launch.ps1 -DataDir "$env:LOCALAPPDATA\Claude-A" -ConfigDir "C:\ClaudeProfiles\A\.claude"
#
#   # Private copy of the app folder (pinned, no Store identity) - profile "B"
#   .\claude-windows-launch.ps1 -AppDir "C:\ClaudeProfiles\B\app" `
#       -DataDir "C:\ClaudeProfiles\B\electron-data" -ConfigDir "C:\ClaudeProfiles\B\.claude"
#
# Rule: at most ONE profile may use the Store exe. Every other profile must use a private copy
# (-AppDir). See README.md for why.
param(
    [Parameter(Mandatory)] [string]$DataDir,
    [Parameter(Mandatory)] [string]$ConfigDir,
    [string]$AppDir    # omit to use the Store package
)

$ErrorActionPreference = 'Stop'

if ($AppDir) {
    $exe = Join-Path $AppDir 'claude.exe'
} else {
    # WindowsApps denies directory listing to standard users, so resolve via the Appx manifest.
    $pkg = Get-AppxPackage -Name 'Claude*' | Select-Object -First 1
    if (-not $pkg) { throw 'No Claude Desktop Store package found. Pass -AppDir to use a private copy.' }
    $exe = Join-Path $pkg.InstallLocation 'app\Claude.exe'
}
if (-not (Test-Path $exe)) { throw "Executable not found: $exe" }

New-Item -ItemType Directory -Force $DataDir, $ConfigDir | Out-Null

# Child processes inherit this; it is scoped to this launcher process only.
$env:CLAUDE_CONFIG_DIR = $ConfigDir
Start-Process $exe -ArgumentList "--user-data-dir=`"$DataDir`""
