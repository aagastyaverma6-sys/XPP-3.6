@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================
::  X++ (XPP) v0.3.x  –  FULL WINDOWS INSTALLER
::  Repo: https://github.com/aagastyaverma6-sys/XPP
::
::  Installs / verifies:
::    - Python 3.9+  (winget or official installer)
::    - pip + deps: lark, requests  (+ editable package install)
::    - NASM + MinGW/GCC  (optional, for AI assembly mode)
::    - PATH registration for the `x` command
::    - OPENROUTER_API_KEY  (optional, for RNM=ITR)
::    - VS Code .xp syntax highlighting
:: ============================================================

title X++ Full System Setup
color 0B
cd /d "%~dp0"

set "LANG_PATH=%~dp0"
if "%LANG_PATH:~-1%"=="\" set "LANG_PATH=%LANG_PATH:~0,-1%"
set "ERR_COUNT=0"
set "INSTALLED_PYTHON=0"
set "PYTHON_CMD="
set "PY_OK=0"

echo.
echo ============================================================
echo           X++ v0.3  FULL AUTOMATED SYSTEM SETUP
echo                  Atom Software / XPP
echo ============================================================
echo.
echo  [i] Install folder: %LANG_PATH%
echo.

:: ------------------------------------------------------------
:: 0) Admin notice (not required, but winget/MSI are smoother)
:: ------------------------------------------------------------
net session >nul 2>&1
if errorlevel 1 (
  echo  [!] Not running as Administrator.
  echo      Python / NASM / GCC installs may prompt UAC or fail
  echo      on locked machines. Right-click -^> Run as administrator
  echo      if anything fails below.
  echo.
) else (
  echo  [+] Running with Administrator privileges.
  echo.
)

:: ------------------------------------------------------------
:: 1) Find a working Python 3.9+
:: ------------------------------------------------------------
echo ============================================================
echo  [1/7]  PYTHON 3.9+
echo ============================================================
echo.

call :FindPython
if "!PY_OK!"=="1" goto :PythonReady

echo  [!] Python 3.9+ not found. Installing...
call :InstallPython
call :RefreshPath
call :FindPython

if not "!PY_OK!"=="1" (
  echo.
  echo  [X] FATAL: Could not install or detect Python.
  echo      Install manually from https://www.python.org/downloads/
  echo      IMPORTANT: tick "Add python.exe to PATH", then re-run setup.bat
  set /a ERR_COUNT+=1
  goto :AfterPython
)

:PythonReady
for /f "tokens=*" %%V in ('!PYTHON_CMD! -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')" 2^>nul') do set "PY_VER=%%V"
echo  [+] Python ready: !PYTHON_CMD!  (v!PY_VER!)
echo.

:AfterPython

:: ------------------------------------------------------------
:: 2) pip + project dependencies
:: ------------------------------------------------------------
echo ============================================================
echo  [2/7]  PIP + X++ DEPENDENCIES  (lark, requests)
echo ============================================================
echo.

if "!PY_OK!"=="1" (
  echo  [+] Upgrading pip / setuptools / wheel...
  !PYTHON_CMD! -m ensurepip --upgrade >nul 2>&1
  !PYTHON_CMD! -m pip install --upgrade pip setuptools wheel
  if errorlevel 1 (
    echo  [!] pip upgrade had issues – continuing anyway...
  )

  echo  [+] Installing runtime deps: lark requests...
  !PYTHON_CMD! -m pip install "lark>=1.1.5" "requests>=2.28"
  if errorlevel 1 (
    echo  [X] Failed to install lark/requests
    set /a ERR_COUNT+=1
  ) else (
    echo  [+] lark + requests installed.
  )

  :: Editable install so `x` / `xpp` / `xite` console scripts work if desired
  if exist "%LANG_PATH%\pyproject.toml" (
    echo  [+] Installing X++ package in editable mode  (pip install -e .)
    !PYTHON_CMD! -m pip install -e "%LANG_PATH%"
    if errorlevel 1 (
      echo  [!] Editable install failed – `x.bat` shim will still work.
      echo      ^(You can ignore this if lark/requests installed fine.^)
    ) else (
      echo  [+] Editable package install OK  (x / xpp / xite entry points).
    )
  )

  :: Verify imports
  !PYTHON_CMD! -c "import lark, requests; print('[+] Import check OK: lark', lark.__version__, '| requests', requests.__version__)" 2>nul
  if errorlevel 1 (
    echo  [X] Python can run but lark/requests import failed.
    set /a ERR_COUNT+=1
  )

  !PYTHON_CMD! -c "import sys; sys.path.insert(0, r'%LANG_PATH%'); import xpp_core; print('[+] xpp_core package import OK')" 2>nul
  if errorlevel 1 (
    echo  [!] Could not import xpp_core – make sure you run setup from the XPP repo root.
    set /a ERR_COUNT+=1
  )
) else (
  echo  [!] Skipping pip deps – Python unavailable.
)
echo.

:: ------------------------------------------------------------
:: 3) Optional toolchain: NASM + GCC (AI assembly / RNM=ITR asm)
:: ------------------------------------------------------------
echo ============================================================
echo  [3/7]  OPTIONAL: NASM + GCC  (AI assembly mode)
echo ============================================================
echo.
echo  Strict modes XCOM / XITR only need Python.
echo  AI assembly backend needs nasm + gcc on PATH.
echo.

set "WANT_ASM=Y"
set /p "WANT_ASM=Install NASM + MinGW GCC now? [Y/n]: "
if /i "!WANT_ASM!"=="n" (
  echo  [i] Skipped assembly toolchain.
  goto :AfterAsm
)

call :EnsureNasm
call :EnsureGcc
call :RefreshPath

where nasm >nul 2>&1
if errorlevel 1 (
  echo  [!] nasm still not on PATH. Assembly mode may fail until you restart the PC.
) else (
  for /f "tokens=*" %%A in ('nasm -v 2^>nul') do echo  [+] %%A
)

where gcc >nul 2>&1
if errorlevel 1 (
  echo  [!] gcc still not on PATH. Assembly link step may fail until restart.
) else (
  for /f "tokens=*" %%A in ('gcc --version 2^>nul ^| findstr /i "gcc"') do echo  [+] %%A
)

:AfterAsm
echo.

:: ------------------------------------------------------------
:: 4) Register repo folder + Scripts on User PATH
:: ------------------------------------------------------------
echo ============================================================
echo  [4/7]  PATH  (`x` command)
echo ============================================================
echo.

:: Ensure x.bat exists
if not exist "%LANG_PATH%\x.bat" (
  echo  [!] x.bat missing – writing a minimal launcher...
  (
    echo @echo off
    echo setlocal
    echo set "XPP_HOME=%%~dp0"
    echo if "%%XPP_HOME:~-1%%"=="\" set "XPP_HOME=%%XPP_HOME:~0,-1%%"
    echo where py ^>nul 2^>^&1 ^&^& ^(
    echo   py -3 "%%XPP_HOME%%\x_engine.py" %%*
    echo   exit /b %%ERRORLEVEL%%
    echo ^)
    echo where python ^>nul 2^>^&1 ^&^& ^(
    echo   python "%%XPP_HOME%%\x_engine.py" %%*
    echo   exit /b %%ERRORLEVEL%%
    echo ^)
    echo echo X++ Error: Python not found on PATH. Run setup.bat
    echo exit /b 1
  ) > "%LANG_PATH%\x.bat"
)

:: User PATH: add LANG_PATH if missing
call :AddToUserPath "%LANG_PATH%"

:: Also add Python Scripts dirs so `x` entry-point from pip works
if "!PY_OK!"=="1" (
  for /f "tokens=*" %%S in ('!PYTHON_CMD! -c "import sysconfig,os; print(sysconfig.get_path('scripts') or '')" 2^>nul') do (
    if not "%%S"=="" call :AddToUserPath "%%S"
  )
  for /f "tokens=*" %%S in ('!PYTHON_CMD! -c "import site,os; print(os.path.join(site.USER_BASE, 'Scripts'))" 2^>nul') do (
    if not "%%S"=="" if exist "%%S" call :AddToUserPath "%%S"
  )
)

:: Session PATH so the rest of this script can call `x`
set "PATH=%LANG_PATH%;%PATH%"
echo  [+] PATH updated for this user. New terminals will see `x`.
echo.

:: ------------------------------------------------------------
:: 5) OpenRouter API key (RNM=ITR only)
:: ------------------------------------------------------------
echo ============================================================
echo  [5/7]  OPENROUTER API KEY  (only for RNM=ITR / AI mode)
echo ============================================================
echo.
echo  Free key: https://openrouter.ai
echo  Skip if you only use XCOM / XITR strict modes.
echo.

set "USER_KEY="
set /p "USER_KEY=Paste OpenRouter API key [Enter to skip]: "
if not "!USER_KEY!"=="" (
  setx OPENROUTER_API_KEY "!USER_KEY!" >nul
  set "OPENROUTER_API_KEY=!USER_KEY!"
  echo  [+] Saved OPENROUTER_API_KEY for your user account.
) else (
  echo  [i] Skipped. Set later with:
  echo      setx OPENROUTER_API_KEY "sk-or-..."
)
echo.

:: ------------------------------------------------------------
:: 6) VS Code / Cursor syntax highlighting
:: ------------------------------------------------------------
echo ============================================================
echo  [6/7]  EDITOR SYNTAX HIGHLIGHTING  (.xp)
echo ============================================================
echo.

set "EXT_ID=xpp-lang-0.3.0"
set "COPIED_ANY=0"

for %%D in (
  "%USERPROFILE%\.vscode\extensions"
  "%USERPROFILE%\.vscode-insiders\extensions"
  "%USERPROFILE%\.cursor\extensions"
) do (
  if exist %%~D (
    set "TARGET=%%~D\%EXT_ID%"
    if not exist "!TARGET!\syntaxes" mkdir "!TARGET!\syntaxes"
    if exist "%LANG_PATH%\package.json" copy /Y "%LANG_PATH%\package.json" "!TARGET!\package.json" >nul
    if exist "%LANG_PATH%\xp.tmLanguage.json" (
      copy /Y "%LANG_PATH%\xp.tmLanguage.json" "!TARGET!\syntaxes\xp.tmLanguage.json" >nul
      copy /Y "%LANG_PATH%\xp.tmLanguage.json" "!TARGET!\xp.tmLanguage.json" >nul 2>&1
    )
    if exist "%LANG_PATH%\language-configuration.json" copy /Y "%LANG_PATH%\language-configuration.json" "!TARGET!\language-configuration.json" >nul
    echo  [+] Installed grammar -^> !TARGET!
    set "COPIED_ANY=1"
  )
)

if "!COPIED_ANY!"=="0" (
  set "TARGET=%USERPROFILE%\.vscode\extensions\%EXT_ID%"
  if not exist "!TARGET!\syntaxes" mkdir "!TARGET!\syntaxes"
  if exist "%LANG_PATH%\package.json" copy /Y "%LANG_PATH%\package.json" "!TARGET!\package.json" >nul
  if exist "%LANG_PATH%\xp.tmLanguage.json" copy /Y "%LANG_PATH%\xp.tmLanguage.json" "!TARGET!\syntaxes\xp.tmLanguage.json" >nul
  if exist "%LANG_PATH%\language-configuration.json" copy /Y "%LANG_PATH%\language-configuration.json" "!TARGET!\language-configuration.json" >nul
  echo  [+] Installed grammar -^> !TARGET!
  echo  [i] Open / reload VS Code or Cursor to activate highlighting.
)
echo.

:: ------------------------------------------------------------
:: 7) Final verification
:: ------------------------------------------------------------
echo ============================================================
echo  [7/7]  VERIFY INSTALL
echo ============================================================
echo.

if "!PY_OK!"=="1" (
  echo  -- Engine version --
  !PYTHON_CMD! "%LANG_PATH%\x_engine.py" --version 2>nul
  if errorlevel 1 (
    !PYTHON_CMD! "%LANG_PATH%\x_engine.py" 2>nul
  )
  echo.
  echo  -- Smoke test: transpile/check if examples exist --
  if exist "%LANG_PATH%\examples\hello.xp" (
    !PYTHON_CMD! "%LANG_PATH%\x_engine.py" check "%LANG_PATH%\examples\hello.xp" 2>nul
    if errorlevel 1 (
      !PYTHON_CMD! "%LANG_PATH%\x_engine.py" run "%LANG_PATH%\examples\hello.xp" --mode XITR 2>nul
    )
  ) else if exist "%LANG_PATH%\test.xp" (
    !PYTHON_CMD! "%LANG_PATH%\x_engine.py" run "%LANG_PATH%\test.xp" --mode XITR 2>nul
  ) else (
    echo  [i] No examples\hello.xp or test.xp found – skipped smoke run.
  )
) else (
  echo  [X] Python missing – cannot verify engine.
)

echo.
echo ============================================================
if "!ERR_COUNT!"=="0" (
  echo  [+] SUCCESS! X++ is ready on this machine.
) else (
  echo  [!] Finished with !ERR_COUNT! warning^(s^)/error^(s^).
  echo      Read the log above – most often PATH needs a full sign-out.
)
echo.
echo  Quick start ^(open a NEW terminal^):
echo.
echo    x run examples\hello.xp --mode XITR
echo    x run examples\fib.xp --mode XCOM
echo    x run examples\ai_demo.xp --mode ITR
echo    xite
echo.
echo  [!] RESTART terminals, VS Code, and Cursor so PATH + env apply.
echo ============================================================
echo.
pause
endlocal
exit /b 0


:: ============================================================
::  HELPERS
:: ============================================================

:FindPython
set "PY_OK=0"
set "PYTHON_CMD="

:: Prefer py launcher with 3.9+
where py >nul 2>&1
if not errorlevel 1 (
  py -3 -c "import sys; raise SystemExit(0 if sys.version_info >= (3,9) else 1)" >nul 2>&1
  if not errorlevel 1 (
    set "PYTHON_CMD=py -3"
    set "PY_OK=1"
    exit /b 0
  )
)

where python >nul 2>&1
if not errorlevel 1 (
  python -c "import sys; raise SystemExit(0 if sys.version_info >= (3,9) else 1)" >nul 2>&1
  if not errorlevel 1 (
    set "PYTHON_CMD=python"
    set "PY_OK=1"
    exit /b 0
  )
)

where python3 >nul 2>&1
if not errorlevel 1 (
  python3 -c "import sys; raise SystemExit(0 if sys.version_info >= (3,9) else 1)" >nul 2>&1
  if not errorlevel 1 (
    set "PYTHON_CMD=python3"
    set "PY_OK=1"
    exit /b 0
  )
)

:: Common install locations
for %%P in (
  "%LocalAppData%\Programs\Python\Python312\python.exe"
  "%LocalAppData%\Programs\Python\Python311\python.exe"
  "%LocalAppData%\Programs\Python\Python310\python.exe"
  "%LocalAppData%\Programs\Python\Python313\python.exe"
  "%LocalAppData%\Programs\Python\Python39\python.exe"
  "%ProgramFiles%\Python312\python.exe"
  "%ProgramFiles%\Python311\python.exe"
  "%ProgramFiles%\Python310\python.exe"
  "C:\Python312\python.exe"
  "C:\Python311\python.exe"
) do (
  if exist %%~P (
    %%~P -c "import sys; raise SystemExit(0 if sys.version_info >= (3,9) else 1)" >nul 2>&1
    if not errorlevel 1 (
      set "PYTHON_CMD=%%~P"
      set "PY_OK=1"
      exit /b 0
    )
  )
)
exit /b 1


:InstallPython
echo  [+] Trying winget (Python 3.12)...
where winget >nul 2>&1
if not errorlevel 1 (
  winget install -e --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements --disable-interactivity
  if not errorlevel 1 (
    set "INSTALLED_PYTHON=1"
    echo  [+] winget reported success for Python 3.12.
    exit /b 0
  )
  echo  [!] winget Python.Python.3.12 failed – trying 3.11...
  winget install -e --id Python.Python.3.11 --accept-package-agreements --accept-source-agreements --disable-interactivity
  if not errorlevel 1 (
    set "INSTALLED_PYTHON=1"
    exit /b 0
  )
)

echo  [+] winget unavailable/failed – downloading official Python 3.12 installer...
set "PY_MSI=%TEMP%\xpp-python312-installer.exe"
set "PY_URL=https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe"

where curl >nul 2>&1
if not errorlevel 1 (
  curl -L --retry 3 -o "%PY_MSI%" "%PY_URL%"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "try { Invoke-WebRequest -Uri '%PY_URL%' -OutFile '%PY_MSI%' -UseBasicParsing } catch { exit 1 }"
)

if not exist "%PY_MSI%" (
  echo  [X] Download failed.
  exit /b 1
)

echo  [+] Running Python installer (silent, Add to PATH, pip)...
:: PrependPath + Include_pip + InstallAllUsers=0 for per-user reliability
"%PY_MSI%" /quiet InstallAllUsers=0 PrependPath=1 Include_test=0 Include_launcher=1 Include_pip=1 SimpleInstall=1
set "RC=!ERRORLEVEL!"
del "%PY_MSI%" >nul 2>&1
if not "!RC!"=="0" (
  echo  [X] Python installer exited with code !RC!
  exit /b 1
)
set "INSTALLED_PYTHON=1"
echo  [+] Python installer finished.
exit /b 0


:EnsureNasm
where nasm >nul 2>&1
if not errorlevel 1 (
  echo  [+] nasm already installed.
  exit /b 0
)
echo  [+] Installing NASM...
where winget >nul 2>&1
if not errorlevel 1 (
  winget install -e --id NASM.NASM --accept-package-agreements --accept-source-agreements --disable-interactivity
  if not errorlevel 1 exit /b 0
)
:: Fallback: portable-ish via chocolatey if present
where choco >nul 2>&1
if not errorlevel 1 (
  choco install nasm -y
  if not errorlevel 1 exit /b 0
)
echo  [!] Could not auto-install NASM.
echo      Download: https://www.nasm.us/  and add it to PATH.
exit /b 1


:EnsureGcc
where gcc >nul 2>&1
if not errorlevel 1 (
  echo  [+] gcc already installed.
  exit /b 0
)
echo  [+] Installing MinGW-w64 GCC (linker for Windows asm)...
where winget >nul 2>&1
if not errorlevel 1 (
  :: Common package IDs across winget sources
  winget install -e --id BrechtSanders.WinLibs.POSIX.UCRT --accept-package-agreements --accept-source-agreements --disable-interactivity
  if not errorlevel 1 exit /b 0
  winget install -e --id MartinStorsjo.LLVM-MinGW.UCRT --accept-package-agreements --accept-source-agreements --disable-interactivity
  if not errorlevel 1 exit /b 0
  winget install -e --id MSYS2.MSYS2 --accept-package-agreements --accept-source-agreements --disable-interactivity
  if not errorlevel 1 (
    echo  [i] MSYS2 installed. Open "MSYS2 UCRT64" and run:
    echo      pacman -S --needed mingw-w64-ucrt-x86_64-gcc nasm
    echo      then add C:\msys64\ucrt64\bin to User PATH.
    exit /b 0
  )
)
where choco >nul 2>&1
if not errorlevel 1 (
  choco install mingw -y
  if not errorlevel 1 exit /b 0
)
echo  [!] Could not auto-install GCC.
echo      Install WinLibs/MinGW or MSYS2 and add gcc to PATH.
exit /b 1


:AddToUserPath
set "ADD_DIR=%~1"
if "%ADD_DIR%"=="" exit /b 0
if not exist "%ADD_DIR%" exit /b 0

set "ADD_DIR_ENV=%ADD_DIR%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$dir = $env:ADD_DIR_ENV;" ^
  "if ([string]::IsNullOrWhiteSpace($dir)) { exit 0 };" ^
  "$userPath = [Environment]::GetEnvironmentVariable('Path','User'); if ($null -eq $userPath) { $userPath = '' };" ^
  "$parts = $userPath -split ';' | Where-Object { $_ -and $_.Trim() -ne '' };" ^
  "$norm = $dir.TrimEnd('\');" ^
  "if ($parts | Where-Object { $_.TrimEnd('\') -ieq $norm }) { Write-Host '  [=] PATH already has' $norm; exit 0 };" ^
  "$newPath = if ($userPath.Trim() -eq '') { $norm } else { $userPath.TrimEnd(';') + ';' + $norm };" ^
  "[Environment]::SetEnvironmentVariable('Path', $newPath, 'User');" ^
  "Write-Host '  [+] Added to User PATH:' $norm"

:: Also expose in current process
set "PATH=%ADD_DIR%;%PATH%"
exit /b 0


:RefreshPath
:: Pull latest User + Machine PATH into this CMD session
for /f "usebackq tokens=*" %%P in (`powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')"`) do set "PATH=%%P"
:: Re-add common Python locations immediately after install
for %%P in (
  "%LocalAppData%\Programs\Python\Python313"
  "%LocalAppData%\Programs\Python\Python312"
  "%LocalAppData%\Programs\Python\Python311"
  "%LocalAppData%\Programs\Python\Python310"
  "%LocalAppData%\Programs\Python\Python39"
  "%LocalAppData%\Programs\Python\Python313\Scripts"
  "%LocalAppData%\Programs\Python\Python312\Scripts"
  "%LocalAppData%\Programs\Python\Python311\Scripts"
  "%LocalAppData%\Programs\Python\Python310\Scripts"
  "%LocalAppData%\Programs\Python\Python39\Scripts"
) do (
  if exist "%%~P" set "PATH=%%~P;%PATH%"
)
exit /b 0
