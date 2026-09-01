@echo off
setlocal
set "PYTHONPATH=%~dp0;%PYTHONPATH%"
python "%~dp0x_engine.py" %*
endlocal
