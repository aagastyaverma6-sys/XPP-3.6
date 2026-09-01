@echo off
REM ============================================================
REM  X++ v0.4.1 - Build the native VM (xppvm.exe) on Windows
REM  Requires: MinGW-w64 g++ (or clang++) or MSYS2 g++
REM  Build:    build\xppvm.exe  (+ zjit_runtime.hpp next to it)
REM ============================================================
setlocal
cd /d "%~dp0"

set "GXX="
where g++ >nul 2>&1 && set "GXX=g++"
if not defined GXX if exist "C:\msys64\mingw64\bin\g++.exe" set "GXX=C:\msys64\mingw64\bin\g++.exe"
if not defined GXX if exist "C:\MinGW\bin\g++.exe" set "GXX=C:\MinGW\bin\g++.exe"
if not defined GXX if exist "C:\msys64\usr\bin\g++.exe" set "GXX=C:\msys64\usr\bin\g++.exe"
if not defined GXX goto no_gxx

if not exist build mkdir build

echo [X++] Compiling native VM (xppvm.exe)...
"%GXX%" -O2 -std=c++17 -o build\xppvm.exe ^
  native\xpp_main.cpp native\xpp_parse.cpp native\xpp_codegen.cpp ^
  native\xpp_vm.cpp native\xpp_values.cpp native\xpp_nativegen.cpp
if errorlevel 1 goto build_failed

copy /Y native\zjit_runtime.hpp build\zjit_runtime.hpp >nul
if errorlevel 1 goto copy_failed

echo [X++] Build OK: build\xppvm.exe
echo [X++] Add "%~dp0build" to PATH, or set XPP_NATIVE_DIR=%~dp0build
endlocal
exit /b 0

:no_gxx
echo [X++] g++ not found. Install MinGW-w64 e.g. winget install MSYS2.MSYS2 and retry.
echo       Then run setup.bat again so xppvm can be built.
endlocal
exit /b 1

:build_failed
echo [X++] Build FAILED.
endlocal
exit /b 1

:copy_failed
echo [X++] Could not copy zjit_runtime.hpp.
endlocal
exit /b 1
