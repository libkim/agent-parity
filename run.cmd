@echo off
rem Download the pinned Windows binary into a shared cache, verify its release
rem checksum, then run it for this project.
setlocal
set "HERE=%~dp0"
if not exist "%HERE%VERSION" (
  echo memory-mcp: missing %HERE%VERSION 1>&2
  exit /b 1
)
if not exist "%HERE%RELEASE" (
  echo memory-mcp: missing %HERE%RELEASE 1>&2
  exit /b 1
)
set "VERSION="
set "AGENT_PARITY_CACHE_RELEASE="
set /p "VERSION="<"%HERE%VERSION"
set /p "AGENT_PARITY_CACHE_RELEASE="<"%HERE%RELEASE"
if "%VERSION%"=="" (
  echo memory-mcp: empty pinned version 1>&2
  exit /b 1
)
if "%AGENT_PARITY_CACHE_RELEASE%"=="" (
  echo memory-mcp: empty release URL 1>&2
  exit /b 1
)
if defined AGENT_PARITY_CACHE (
  set "CACHE_ROOT=%AGENT_PARITY_CACHE%"
) else if defined LOCALAPPDATA (
  set "CACHE_ROOT=%LOCALAPPDATA%\agent-parity\cache"
) else (
  set "CACHE_ROOT=%USERPROFILE%\.cache\agent-parity"
)
set "AGENT_PARITY_CACHE_ASSET=memory-mcp-windows-amd64.exe"
set "AGENT_PARITY_CACHE_DIR=%CACHE_ROOT%\memory-mcp\%VERSION%"
set "AGENT_PARITY_CACHE_BIN=%AGENT_PARITY_CACHE_DIR%\%AGENT_PARITY_CACHE_ASSET%"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $version=$env:VERSION; if ($version -notmatch '^(v[0-9A-Za-z._-]+|dev)$') { throw ('memory-mcp: invalid pinned version: ' + $version) }; $dir=$env:AGENT_PARITY_CACHE_DIR; $bin=$env:AGENT_PARITY_CACHE_BIN; $asset=$env:AGENT_PARITY_CACHE_ASSET; $release=$env:AGENT_PARITY_CACHE_RELEASE.TrimEnd('/'); $sum=$bin + '.sha256'; $valid=$false; if ((Test-Path -LiteralPath $bin -PathType Leaf) -and (Test-Path -LiteralPath $sum -PathType Leaf)) { $expected=(Get-Content -Raw -LiteralPath $sum).Trim().ToLowerInvariant(); if ($expected -match '^[0-9a-f]{64}$') { $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $bin).Hash.ToLowerInvariant(); $valid=($actual -eq $expected) } }; if (-not $valid) { New-Item -ItemType Directory -Force -Path $dir | Out-Null; $id=[Guid]::NewGuid().ToString('N'); $tmpBin=Join-Path $dir ('.' + $asset + '.' + $id + '.tmp'); $tmpSums=Join-Path $dir ('.checksums.' + $id + '.tmp'); try { Invoke-WebRequest -UseBasicParsing -Uri ($release + '/checksums.txt') -OutFile $tmpSums; $expected=$null; foreach ($line in Get-Content -LiteralPath $tmpSums) { $parts=$line.Trim() -split '\s+'; if ($parts.Count -ge 2 -and $parts[-1].TrimStart('*') -eq $asset) { $expected=$parts[0].ToLowerInvariant(); break } }; if (-not $expected -or $expected -notmatch '^[0-9a-f]{64}$') { throw ('memory-mcp: checksum missing for ' + $asset) }; Invoke-WebRequest -UseBasicParsing -Uri ($release + '/' + $asset) -OutFile $tmpBin; $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $tmpBin).Hash.ToLowerInvariant(); if ($actual -ne $expected) { throw ('memory-mcp: checksum mismatch for ' + $asset) }; Move-Item -LiteralPath $tmpBin -Destination $bin -Force; [IO.File]::WriteAllText($tmpSums, $expected + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false))); Move-Item -LiteralPath $tmpSums -Destination $sum -Force } finally { Remove-Item -LiteralPath $tmpBin,$tmpSums -Force -ErrorAction SilentlyContinue } }; exit 0"
if errorlevel 1 exit /b %ERRORLEVEL%

if "%MEMORY_DIR%"=="" set "MEMORY_DIR=%HERE%..\..\..\.agents\memory"
"%AGENT_PARITY_CACHE_BIN%" -dir "%MEMORY_DIR%" %*
