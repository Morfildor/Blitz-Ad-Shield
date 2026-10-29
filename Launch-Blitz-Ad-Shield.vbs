' Starts the tray controller without a console window.
Option Explicit
Dim shell, fso, folder, q, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
folder = fso.GetParentFolderName(WScript.ScriptFullName)
q = Chr(34)
command = "powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File " & q & folder & "\Start-Blitz-Ad-Shield.ps1" & q
shell.Run command, 0, False
