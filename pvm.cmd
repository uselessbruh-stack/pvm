@echo off
:: PVM - Python Version Manager (CMD shim)
:: This batch file forwards all arguments to the PowerShell script.

setlocal

set "PVM_SCRIPT=%~dp0pvm.ps1"

:: Check if the PowerShell script exists next to this .cmd
if not exist "%PVM_SCRIPT%" (
    :: Fall back to the installed location
    set "PVM_SCRIPT=%USERPROFILE%\.pvm\pvm.ps1"
)

if not exist "%PVM_SCRIPT%" (
    echo [PVM] Error: Cannot find pvm.ps1
    echo [PVM] Please reinstall PVM by running install.ps1
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PVM_SCRIPT%" %*
