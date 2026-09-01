@echo off
setlocal
cd /d "%~dp0"
set "PY="
where python >nul 2>&1 && set "PY=python"
if not defined PY where py >nul 2>&1 && set "PY=py"
if not defined PY (
  echo Python not found. Install Python 3.9+ from python.org first.
  pause
  exit /b 1
)
%PY% tools\fix_x.py
echo.
pause
endlocal
