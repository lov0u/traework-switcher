' Trae Work Account Switcher - Silent Launcher (with auto-elevation for MachineGuid reset)
Dim shell, fso, scriptDir
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)

' Check if running as admin, if not, auto-elevate
Dim psScript
psScript = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & scriptDir & "\TraeWorkAccountSwitcher-GUI.ps1" & Chr(34)

' Use ShellExecute with "runas" to request admin privileges
shell.ShellExecute "powershell.exe", "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & scriptDir & "\TraeWorkAccountSwitcher-GUI.ps1" & Chr(34), "", "runas", 0
