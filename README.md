# Running two Claude Desktop / Claude Code profiles side by side on Windows

If you are trying to run **two Claude accounts at once** (for example work and personal) in Claude Desktop on Windows, with separate logins, separate Claude Code sessions, memory, hooks and settings, this is a working setup plus the scripts to run and maintain it.

Windows needs more than the `--user-data-dir` flag, for the reasons below. For the macOS equivalent of the basic flag approach, see [@stracker-phil's launcher gist](https://gist.github.com/stracker-phil/9f84927a556632c7f9cc06663b534f14), which I read before writing this. It is a separate approach and shares no code with this one.

Audience: anyone running multiple Claude Desktop / Claude Code instances on one machine, including consultants, people with a work and a personal account, and teams that keep client environments apart.

## Two stores to isolate, not one

| Store | Controlled by | Holds |
|---|---|---|
| Electron data | `--user-data-dir=<dir>` | login, session index (the sidebar), app config, VM bundles |
| Claude Code home | `CLAUDE_CONFIG_DIR=<dir>` | transcripts, memory, settings, hooks, skills |

`--user-data-dir` alone separates the logins but leaves both profiles sharing one Claude Code home. Set `CLAUDE_CONFIG_DIR` too, in the launcher's environment. The Claude Code processes the app starts inherit it.

A session appears in the sidebar only when an index record in the Electron data points (via `cliSessionId`) at a transcript file in the Claude Code home. If you ever move or restore one store, check the other.

## The Store trap (Windows)

Observed on a Microsoft Store install of Claude Desktop, October 2026:

1. **The Store build enforces a single instance.** A second launch of the same exe can exit silently or just focus the first window.
2. **`--user-data-dir` is not always honoured.** After an update the app ran a `[user-data-move]` step and relocated one profile's data into a fixed `%LOCALAPPDATA%\Claude-Data\<package-family>` folder. From then on, every launch, even one with `--user-data-dir` pointing elsewhere, loaded that account.
3. **Auto-update restarts carry no flags.** The Store restarts the app itself, not through your shortcut, so it starts with no `--user-data-dir` at all.

I don't know the mechanism behind (2). The flag changed from one state to another without any action on my side, which suggests it is decided outside the machine, but that is an inference.

### What worked

- **Exactly one profile uses the Store exe.** It keeps auto-updates.
- **Every other profile runs from a private copy of the app folder** (`robocopy` the `WindowsApps\Claude_*\app` folder somewhere you own). A copy has no package identity, so it is not subject to the single-instance rule or the data relocation, and it does not auto-update (the log says `App is not installed, not enabling auto-updates`). Update it deliberately with `claude-windows-update-copy.ps1`.
- **Never launch the copy's profile from the Store exe.** It can take over the other profile's data folder.
- **Make `%LOCALAPPDATA%\Claude-Data\<package-family>` a junction to the Store profile's real data folder.** Then a flagless launch (Start menu, taskbar, auto-update restart) still lands in the right profile:

  ```powershell
  New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\Claude-Data\<package-family>" -Target "<store profile data dir>"
  ```

  Package-virtualised paths can make the real data physically live under `%LOCALAPPDATA%\Packages\<package-family>\LocalCache\Local\...` while tools inside the app see a merged view. Check from outside the app tree.
- **After any Store update**, run the diagnose script and look for `[user-data-move]` and `[updater] Version changed` in `main.log`.

This has been stable for the setup it was built on (two profiles, one Store and one private copy). I have not tested it with three or more profiles.

## Windows files

| File | Purpose |
|---|---|
| `claude-windows-launch.ps1` | Start one profile: `-DataDir`, `-ConfigDir`, optional `-AppDir` (private copy; omit for the Store exe) |
| `claude-windows-launch-hidden.vbs` | Wrapper for desktop shortcuts, with no console flash. Takes `<DataDir> <ConfigDir> [AppDir]` |
| `claude-windows-update-copy.ps1` | Stage the Store build, smoke-test it with a throwaway data dir, swap it in, keep a rollback copy. `-SmokeTest` leaves the live copy untouched |
| `claude-windows-diagnose.ps1` | Read-only: versions, which exe and data dir each running instance uses, `Claude-Data` contents, and the relevant `main.log` lines |

Example, two profiles:

```powershell
# Profile A: Store exe, auto-updates
.\claude-windows-launch.ps1 -DataDir "$env:LOCALAPPDATA\Claude-A" -ConfigDir C:\ClaudeProfiles\A\.claude

# Profile B: private copy, pinned
.\claude-windows-launch.ps1 -AppDir C:\ClaudeProfiles\B\app `
    -DataDir C:\ClaudeProfiles\B\electron-data -ConfigDir C:\ClaudeProfiles\B\.claude
```

First-time setup of the copy:

```powershell
$src = (Get-AppxPackage -Name "Claude*" | Select-Object -First 1).InstallLocation + "\app"
robocopy $src C:\ClaudeProfiles\B\app /MIR /R:1 /W:1   # exit codes 0-7 are success
```

If access to `WindowsApps` is denied, run PowerShell as administrator for that step.

## What the diagnose script prints

Healthy setup: Profile B (private copy) running, Profile A (Store) closed, junction in place. Paths shortened.

```
== Versions
Store package : <store version>   (C:\Program Files\WindowsApps\Claude_<store version>_x64__pzs8sxrjxfjjc)
Private copy  : <copy version>   (C:\ClaudeProfiles\B\app)

== Running instances (grouped by exe path)
13 process(es)  exe: C:\ClaudeProfiles\B\app\claude.exe
    user-data-dir: C:\ClaudeProfiles\B\electron-data

== Store data-location trap
Claude-Data exists. A junction here is the intended fix; a real folder means the Store build relocated data:
    claude_pzs8sxrjxfjjc  [Junction -> ...\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Local\Claude-A]

Last relevant lines in ...\Claude\logs\main.log
    [info] [user-data-move] already_moved_behind_link { blocked: null, hosts: null }
    [info] [updater] Version changed since last launch: <old> → <new>
```

A real folder instead of a junction, or an instance with `(none - uses the app default!)` as its data dir, is the signal that something is wrong.

## Questions, problems, other setups

Open an [issue](../../issues), or email info@kainosis.com. If your Store build behaves differently (or the data-location behaviour has changed), the `[user-data-move]` and `token cache location` lines from your `main.log` are the most useful thing to include. Redact any account identifiers first.

## Caveats

- Behaviour described here was observed on Windows 11 with the Store build in October-November 2026. Anthropic can change how the app handles data location or instances at any time. Treat the log lines, not this document, as the source of truth.
- The scripts were run on the author's machine; the diagnose script is read-only, the others change files in the directories you pass.
- No account identifiers, tokens or credentials are involved. Do not commit your own `electron-data` or `.claude` folders anywhere; they hold login state and transcripts.
