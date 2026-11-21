' Runs claude-windows-launch.ps1 without a flashing console window.
' Point a desktop shortcut at:  wscript.exe "<path>\claude-windows-launch-hidden.vbs" <DataDir> <ConfigDir> [AppDir]
' Paths containing spaces must be quoted in the shortcut's Target field.
Set a = WScript.Arguments
If a.Count < 2 Then
    WScript.Echo "Usage: claude-windows-launch-hidden.vbs <DataDir> <ConfigDir> [AppDir]"
    WScript.Quit 1
End If
here = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & here & "\claude-windows-launch.ps1"" -DataDir """ & a(0) & """ -ConfigDir """ & a(1) & """"
If a.Count >= 3 Then cmd = cmd & " -AppDir """ & a(2) & """"
CreateObject("WScript.Shell").Run cmd, 0, False
