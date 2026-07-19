:; exec "$(dirname "$0")/agent-parity" "$@"
@echo off
setlocal
set "AGENT_PARITY_CMD_ACTIVE=1"
set "agent_parity_bin=%~dp0"
set "agent_parity_scripts=%~dp0..\scripts"
if "%~1"=="sync-claude" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%agent_parity_scripts%\sync-claude.ps1" sync >nul
  exit /b %ERRORLEVEL%
)
if "%~1"=="self-heal" (
  if not "%~2"=="" (
    echo usage: agent-parity self-heal 1>&2
    exit /b 2
  )
  powershell -NoProfile -ExecutionPolicy Bypass -File "%agent_parity_scripts%\self-heal.ps1"
  exit /b %ERRORLEVEL%
)
if "%~1"=="update" goto remote_update
if "%~1"=="uninstall" goto run
if "%~1"=="status" goto run
if "%~1"=="version" goto run
echo usage: agent-parity ^<sync-claude^|self-heal^|update^|uninstall^|status^|version^> 1>&2
exit /b 2

:remote_update
if not "%~2"=="" (
  echo usage: agent-parity update 1>&2
  exit /b 2
)
set "AGENT_PARITY_TARGET=%~dp0..\.."
powershell -NoProfile -ExecutionPolicy Bypass -Command "$repo='libkim/agent-parity'; if ($env:AGENT_PARITY_RAW) { $raw=$env:AGENT_PARITY_RAW.TrimEnd('/') } else { $tag=(Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $repo + '/releases/latest')).tag_name; if ($tag -notmatch '^v') { throw 'could not resolve latest agent-parity release' }; $raw='https://raw.githubusercontent.com/' + $repo + '/' + $tag; $env:AGENT_PARITY_RAW=$raw; $env:AGENT_PARITY_VERSION=$tag; if (-not $env:AGENT_PARITY_RELEASE) { $env:AGENT_PARITY_RELEASE='https://github.com/' + $repo + '/releases/download/' + $tag } }; $response=Invoke-WebRequest -UseBasicParsing -Uri ($raw + '/update.ps1'); $source=$response.Content; if ($source -is [byte[]]) { $source=[Text.Encoding]::UTF8.GetString($source) }; & ([scriptblock]::Create([string]$source)) update $env:AGENT_PARITY_TARGET"
set "agent_parity_exit=%ERRORLEVEL%"
if not "%agent_parity_exit%"=="0" (
  if exist "%agent_parity_bin%agent-parity.cmd.new" del /q "%agent_parity_bin%agent-parity.cmd.new" >nul 2>&1
  exit /b %agent_parity_exit%
)
if exist "%agent_parity_bin%agent-parity.cmd.new" (
  move /y "%agent_parity_bin%agent-parity.cmd.new" "%agent_parity_bin%agent-parity.cmd" >nul || (del /q "%agent_parity_bin%agent-parity.cmd.new" >nul 2>&1 & exit /b 1)
)
exit /b %agent_parity_exit%

:run
set "agent_parity_command=%~1"
shift
powershell -NoProfile -ExecutionPolicy Bypass -File "%agent_parity_scripts%\%agent_parity_command%.ps1" %*
set "agent_parity_exit=%ERRORLEVEL%"
if "%agent_parity_command%"=="uninstall" (
  start "" /b cmd /d /c "ping -n 2 127.0.0.1 >nul & del /q ""%agent_parity_bin%agent-parity"" ""%agent_parity_bin%agent-parity.ps1"" ""%agent_parity_bin%agent-parity.cmd"" >nul 2>&1 & rmdir ""%agent_parity_bin%"" >nul 2>&1"
  exit /b %agent_parity_exit%
)
if exist "%agent_parity_bin%agent-parity.cmd.new" (
  if not "%agent_parity_exit%"=="0" (
    del /q "%agent_parity_bin%agent-parity.cmd.new" >nul 2>&1
    exit /b %agent_parity_exit%
  )
  move /y "%agent_parity_bin%agent-parity.cmd.new" "%agent_parity_bin%agent-parity.cmd" >nul || (del /q "%agent_parity_bin%agent-parity.cmd.new" >nul 2>&1 & exit /b 1)
  exit /b %agent_parity_exit%
)
exit /b %agent_parity_exit%
