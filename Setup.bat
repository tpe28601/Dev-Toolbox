@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
where git >nul 2>nul || (echo 找不到 git，請先安裝 Git for Windows。& pause & exit /b 5)
echo 初始化 submodule ...
git -c protocol.file.allow=always submodule update --init
if errorlevel 1 (echo submodule 初始化失敗。& pause & exit /b 1)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0hub\hub.ps1" doctor
pause
endlocal
