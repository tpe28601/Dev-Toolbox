@echo off
setlocal
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0hub\hub.ps1" %*
if "%~1"=="" pause
endlocal
