@echo off
setlocal
title Cutter Launcher Installer
set SCRIPT_DIR=%~dp0
echo [launcher-install] Starting Windows installer...
echo [launcher-install] Script: "%SCRIPT_DIR%windows_force_cutter_launcher.ps1"
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%windows_force_cutter_launcher.ps1" %*
set EXIT_CODE=%ERRORLEVEL%

echo.
if "%EXIT_CODE%"=="0" (
  echo [launcher-install] Completed successfully.
) else (
  echo [launcher-install] Failed with exit code %EXIT_CODE%.
)

echo.
pause
endlocal
