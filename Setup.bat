@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
where git >nul 2>nul || (echo 找不到 git，請先安裝 Git for Windows。& pause & exit /b 5)
echo 初始化 submodule ...
if /i "%~1"=="--include-private" (
    git -c protocol.file.allow=always submodule update --init
) else (
    echo 略過 private 工具：HLK-Viewer、Script-Editor。
    git -c protocol.file.allow=always submodule update --init -- ^
        tools/Agents-Cfg-Manager tools/Build-Runner tools/Git-Ref-Manager tools/Key-Manager
)
if errorlevel 1 (echo submodule 初始化失敗。& pause & exit /b 1)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0hub\hub.ps1" doctor
pause
endlocal
