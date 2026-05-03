@echo off
setlocal

:: ----------------------------------------------------------------
:: EnvironmentCheck launcher for Windows (cmd / PowerShell)
:: Finds Git Bash and runs EnvironmentCheck.sh with it.
:: ----------------------------------------------------------------

set "BASH_EXE="

:: 1. Check registry (works for any install location)
for /f "tokens=2*" %%A in (
    'reg query "HKLM\SOFTWARE\GitForWindows" /v "InstallPath" 2^>nul'
) do set "BASH_EXE=%%B\bin\bash.exe"

:: 2. Fall back to common default paths
if not exist "%BASH_EXE%" set "BASH_EXE=C:\Program Files\Git\bin\bash.exe"
if not exist "%BASH_EXE%" set "BASH_EXE=C:\Program Files (x86)\Git\bin\bash.exe"

if not exist "%BASH_EXE%" (
    echo.
    echo [ERROR] Git Bash not found.
    echo         Install Git for Windows and re-run this script.
    echo         https://git-scm.com/download/win
    echo.
    pause
    exit /b 1
)

"%BASH_EXE%" "%~dp0EnvironmentCheck.sh"
