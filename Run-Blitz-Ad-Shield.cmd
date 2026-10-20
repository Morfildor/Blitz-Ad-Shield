@echo off
rem Alternative launcher if Windows Script Host/VBScript is disabled.
rem A command window may flash briefly; the controller remains in the tray.
start "" powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Blitz-Ad-Shield-Tray.ps1"
