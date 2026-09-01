@echo off
setlocal EnableExtensions EnableDelayedExpansion
title X++ v0.4.1 - AUTO SETUP (does everything)
color 0B
cd /d "%~dp0"

echo.
echo ============================================================
echo        X++ v0.4.1  -  AUTO SETUP  (Windows)
echo   One click. Installs Python, VS Code, g++/MSYS2, the VM,
echo   the x command, file icons, and VS Code integration.
echo ============================================================
echo.

rem ------------------------------------------------------------
rem  0) admin notice
rem ------------------------------------------------------------
net session >nul 2>&1
if errorlevel 1 (
  echo  [i] Running without admin - OK. Every install below is
  echo      user-level or winget-able.
) else (
  echo  [+] Administrator privileges detected.
)
echo.

set "PYTHON_CMD="

rem ------------------------------------------------------------
rem  1) PYTHON  (needed for the `x` command and AI mode)
rem ------------------------------------------------------------
echo  [1/4]  Python 3.9+
call :find_python
if defined PYTHON_CMD goto :python_ok

echo  [X++] Python not found - installing Python 3.12 via winget...
winget install -e --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements --silent >nul 2>&1
if errorlevel 1 (
  echo  [X++] winget failed - downloading the official installer...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe' -OutFile '%TEMP%\xpp-python-setup.exe' -UseBasicParsing } catch { exit 1 }"
  if exist "%TEMP%\xpp-python-setup.exe" (
    "%TEMP%\xpp-python-setup.exe" /quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1 Include_pip=1
    del "%TEMP%\xpp-python-setup.exe" >nul 2>&1
  )
)
call :find_python
if not defined PYTHON_CMD (
  echo  [X] Python still missing. Please install it from python.org and rerun.
  pause
  exit /b 1
)
:python_ok
echo  [+] Python: %PYTHON_CMD%

rem ------------------------------------------------------------
rem  2) VS CODE (editor + run button + file icons)
rem ------------------------------------------------------------
echo.
echo  [2/4]  VS Code
set "CODE_CMD="
where code >nul 2>&1 && set "CODE_CMD=code"
if not defined CODE_CMD if exist "%LOCALAPPDATA%\Programs\Microsoft VS Code\bin\code.cmd" set "CODE_CMD=%LOCALAPPDATA%\Programs\Microsoft VS Code\bin\code.cmd"
if not defined CODE_CMD if exist "%ProgramFiles%\Microsoft VS Code\bin\code.cmd" set "CODE_CMD=%ProgramFiles%\Microsoft VS Code\bin\code.cmd"

if defined CODE_CMD goto code_done
echo  [X++] VS Code not found - installing via winget...
winget install -e --id Microsoft.VisualStudioCode --accept-package-agreements --accept-source-agreements --silent >nul 2>&1
if exist "%LOCALAPPDATA%\Programs\Microsoft VS Code\bin\code.cmd" set "CODE_CMD=%LOCALAPPDATA%\Programs\Microsoft VS Code\bin\code.cmd"
:code_done
if defined CODE_CMD echo  [+] VS Code: %CODE_CMD%
if not defined CODE_CMD echo  [i] VS Code later? Just rerun setup after installing it.

rem ------------------------------------------------------------
rem  3) C++ COMPILER (g++/MinGW) - installed automatically if missing
rem ------------------------------------------------------------
echo.
echo  [3/4]  C++ compiler (g++)
set "GXX="
where g++ >nul 2>&1 && set "GXX=g++"
if not defined GXX if exist "C:\msys64\mingw64\bin\g++.exe" set "GXX=C:\msys64\mingw64\bin\g++.exe"
if not defined GXX if exist "C:\MinGW\bin\g++.exe" set "GXX=C:\MinGW\bin\g++.exe"
if not defined GXX if exist "C:\msys64\usr\bin\g++.exe" set "GXX=C:\msys64\usr\bin\g++.exe"
if defined GXX goto gxx_done

echo  [X++] g++ not found. Installing MSYS2 + MinGW-w64 automatically...
set "MSYS2_BASH="
if exist "C:\msys64\usr\bin\bash.exe" set "MSYS2_BASH=C:\msys64\usr\bin\bash.exe"
if not defined MSYS2_BASH call :install_msys2
if not defined MSYS2_BASH goto gxx_fail_msg

echo  [i] Installing mingw-w64 x86_64 gcc inside MSYS2 (one time, can take a few minutes)...
"%MSYS2_BASH%" -lc "pacman -Sy --noconfirm --needed mingw-w64-x86_64-gcc" >nul 2>&1
if exist "C:\msys64\mingw64\bin\g++.exe" set "GXX=C:\msys64\mingw64\bin\g++.exe"
if not defined GXX goto gxx_fail_msg

echo  [+] g++ installed: %GXX%
rem make the new g++ visible to this session and future terminals
if not "%GXX%"=="g++" (
  for %%D in ("%GXX%") do set "GXX_DIR=%%~dpD"
  set "PATH=%GXX_DIR%;%PATH%"
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$d='C:\msys64\mingw64\bin';$p=[Environment]::GetEnvironmentVariable('Path','User');$parts=@($p -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ne $d.TrimEnd('\') });$new=$d + ';' + ($parts -join ';');[Environment]::SetEnvironmentVariable('Path',$new,'User')" >nul 2>&1
echo  [+] Added C:\msys64\mingw64\bin to user PATH.
goto gxx_done

:install_msys2
echo  [i]  Trying winget first...
winget install -e --id MSYS2.MSYS2 --accept-package-agreements --accept-source-agreements --silent >nul 2>&1
if exist "C:\msys64\usr\bin\bash.exe" set "MSYS2_BASH=C:\msys64\usr\bin\bash.exe"
if defined MSYS2_BASH goto install_msys2_done
echo  [i]  winget failed (or did not finish) - downloading MSYS2 installer...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -Uri 'https://github.com/msys2/msys2-installer/releases/download/2026-06-11/msys2-x86_64-20260611.exe' -OutFile '%TEMP%\msys2-setup.exe' -UseBasicParsing } catch { exit 1 }" >nul 2>&1
if exist "%TEMP%\msys2-setup.exe" (
  echo  [i]  Running MSYS2 installer silently...
  "%TEMP%\msys2-setup.exe" install --root C:\msys64 --confirm-command >nul 2>&1
  del "%TEMP%\msys2-setup.exe" >nul 2>&1
)
if exist "C:\msys64\usr\bin\bash.exe" set "MSYS2_BASH=C:\msys64\usr\bin\bash.exe"
:install_msys2_done
exit /b 0

:gxx_fail_msg
echo  [X]  Could not install g++ automatically. Your network/winget may be blocked.
echo       Run this once yourself, then rerun setup.bat:
echo           winget install -e --id MSYS2.MSYS2 --accept-package-agreements --accept-source-agreements
echo       or download MSYS2 from https://www.msys2.org and install it to C:\msys64.
echo       NOTE: X++ can still run in legacy mode without g++; native X++ needs it.
set "GXX="
goto gxx_done

:gxx_done
if defined GXX echo  [+] g++: %GXX%
if not defined GXX echo  [i] no g++ yet - legacy XCOM/XITR still work; native ZITR/ZJIT need g++.

rem ------------------------------------------------------------
rem  4) RUN THE UNIVERSAL SETUP (builds VM, installs everything,
rem     registers icons, PATH, VS Code theme, run button)
rem ------------------------------------------------------------
echo.
echo  [4/4]  Installing X++ (VM, commands, icons, VS Code)...
"%PYTHON_CMD%" tools\xpp_setup.py --all
if errorlevel 1 (
  echo.
  echo  [X] Setup hit an error. Rerun; the log above shows what failed.
  pause
  exit /b 1
)

rem ------------------------------------------------------------
rem  verify that x + xppvm actually work
rem ------------------------------------------------------------
echo.
echo  [CHECK] Verifying install...
set "XPP_BIN=%USERPROFILE%\.xpp\bin"
if exist "%XPP_BIN%\x.cmd" goto check_x
echo  [X] x command missing at %XPP_BIN%\x.cmd
goto check_xppvm

:check_x
echo  [OK]  x.cmd: %XPP_BIN%\x.cmd
"%XPP_BIN%\x.cmd" version

:check_xppvm
if exist "%XPP_BIN%\xppvm.exe" goto check_xppvm_ok
if exist "%~dp0build\xppvm.exe" goto check_xppvm_repo
echo  [i]  xppvm.exe not built - native mode will fall back to legacy X++ until g++ is installed.
goto done_checks

:check_xppvm_repo
echo  [OK]  xppvm.exe: %~dp0build\xppvm.exe
set "XPPVM_PATH=%~dp0build\xppvm.exe"
"%XPPVM_PATH%" version
goto done_checks

:check_xppvm_ok
echo  [OK]  xppvm.exe: %XPP_BIN%\xppvm.exe
"%XPP_BIN%\xppvm.exe" version

:done_checks
echo.
echo ============================================================
echo   DONE! Open a NEW terminal and type:
echo
echo       x version
echo       x run examples\hello.xp
echo       x run examples\fib_fast.xp --mode ZJIT
echo
echo   VS Code: open this folder, play button = Run.
echo   .xp files now show the X++ logo.
echo ============================================================
pause
exit /b 0

rem ------------------------------------------------------------
:find_python
set "PYTHON_CMD="
for %%P in ("py.exe" "python.exe") do (
  if not defined PYTHON_CMD (
    where %%P >nul 2>&1
    if not errorlevel 1 (
      %%~nP -c "import sys; sys.exit(0 if sys.version_info>=(3,9) else 1)" >nul 2>&1
      if not errorlevel 1 (
        for /f "delims=" %%V in ('%%~nP -c "import sys;print(sys.executable)" 2^>nul') do set "PYTHON_CMD=%%V"
      )
    )
  )
)
rem freshly installed Pythons are not on this session's PATH yet
if not defined PYTHON_CMD (
  for %%P in (
    "%LOCALAPPDATA%\Programs\Python\Launcher\py.exe"
    "%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
    "%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
    "C:\Python312\python.exe"
    "C:\Python311\python.exe"
  ) do (
    if not defined PYTHON_CMD if exist %%P (
      %%~nP -c "import sys; sys.exit(0 if sys.version_info>=(3,9) else 1)" >nul 2>&1
      if not errorlevel 1 for /f "delims=" %%V in ('%%~nP -c "import sys;print(sys.executable)" 2^>nul') do set "PYTHON_CMD=%%V"
    )
  )
)
exit /b 0
