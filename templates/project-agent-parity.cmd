@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0agent-parity.ps1" %*
exit /b %ERRORLEVEL%
