@echo off
rem X++ v0.4.1 setup launcher - just runs setup.ps1 (PowerShell is more forgiving).
setlocal
cd /d "%~dp0"
echo.
echo  Launching X++ v0.4.1 setup via PowerShell...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
exit /b %errorlevel%
