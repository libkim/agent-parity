@echo off
rem Launcher for native Windows: exec the windows binary. Resolves the binary and
rem the default memory dir relative to this script so the committed launcher works
rem regardless of where the repo is checked out.
setlocal
set "HERE=%~dp0"
set "BIN=%HERE%dist\memory-mcp-windows-amd64.exe"
if not exist "%BIN%" (
  echo memory-mcp: binary not found: %BIN% 1>&2
  exit /b 1
)
if "%MEMORY_DIR%"=="" set "MEMORY_DIR=%HERE%..\..\..\.agents\memory"
"%BIN%" -dir "%MEMORY_DIR%" %*
