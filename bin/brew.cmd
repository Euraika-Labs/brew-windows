@echo off
setlocal
set "BREW_BIN=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BREW_BIN%brew.ps1" %*
exit /b %ERRORLEVEL%
