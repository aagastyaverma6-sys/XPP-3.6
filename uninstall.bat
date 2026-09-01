@echo off
rem X++ uninstaller (Windows) - safe by default.
rem
rem   uninstall.bat                     dry-run: list what it would remove
rem   uninstall.bat --yes               remove known X++ installs
rem   uninstall.bat --yes --deep        also scan XPP/Xite-named dirs
rem   uninstall.bat --yes --deep --full scan whole system (slow)
setlocal EnableExtensions
cd /d "%~dp0"

set "PY=python"
where python >nul 2>&1 || set "PY=py"
where %PY% >nul 2>&1 || set "PY="
if not defined PY (
  echo Python not found - install Python 3 from python.org and rerun.
  pause
  exit /b 1
)

%PY% tools\uninstall_xpp.py %*
echo.
pause
exit /b %errorlevel%
