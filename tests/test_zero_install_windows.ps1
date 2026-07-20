param(
  [Parameter(Position = 0)]
  [string]$Version = "v9.8.7"
)

$ErrorActionPreference = "Stop"
$testRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$dist = Join-Path $testRepoRoot "dist"
$asset = Join-Path $dist "agent-parity-config-windows-amd64.exe"
if (!(Test-Path -LiteralPath $asset -PathType Leaf)) { throw "build release assets first" }

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$root = Join-Path $tempBase ("ap-zero-win-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $root | Out-Null
$root = (Resolve-Path -LiteralPath $root).Path
if (!$root.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) { throw "unsafe test path: $root" }

$oldCache = $env:AGENT_PARITY_CACHE
try {
  # Real file:// URIs instead of an in-process web mock: the pre-warm path runs
  # run.cmd in a separate process where a mocked Invoke-WebRequest cannot reach,
  # and IWR -OutFile handles file:// on PS 5.1.
  $base = "file:///" + ($testRepoRoot.TrimEnd('\') -replace '\\', '/')

  New-Item -ItemType Directory -Force -Path "$root\.agents\scripts", "$root\.agents\mcp\memory", "$root\.cursor", "$root\.codex" | Out-Null
  Copy-Item -LiteralPath (Join-Path $testRepoRoot "templates\common.ps1"),(Join-Path $testRepoRoot "templates\self-heal.ps1") -Destination "$root\.agents\scripts"
  Copy-Item -LiteralPath (Join-Path $testRepoRoot "templates\run.cmd") -Destination "$root\.agents\mcp\memory"
  [IO.File]::WriteAllText("$root\.agents\mcp\memory\VERSION", "$Version`n")
  [IO.File]::WriteAllText("$root\.agents\mcp\memory\RELEASE", "$base/dist`n")
  $json = '{"mcpServers":{"memory":{"command":".agents/mcp/memory/run.sh"}}}'
  [IO.File]::WriteAllText("$root\.mcp.json", $json)
  [IO.File]::WriteAllText("$root\.cursor\mcp.json", $json)
  [IO.File]::WriteAllText("$root\.agents\mcp_config.json", $json)
  [IO.File]::WriteAllText("$root\.codex\config.toml", "[mcp_servers.memory]`ncommand = `".agents/mcp/memory/run.sh`"`n")

  $env:AGENT_PARITY_CACHE = "$root\empty-cache"
  $output = @(& "$root\.agents\scripts\self-heal.ps1")
  if (($output -join "`n") -notmatch 'Restart this agent session') { throw "cross-OS restart notice missing" }
  $editor = "$root\empty-cache\config\$Version\agent-parity-config-windows-amd64.exe"
  if (!(Test-Path -LiteralPath $editor -PathType Leaf)) { throw "self-heal did not download the config editor" }
  $serverBin = "$root\empty-cache\memory-mcp\$Version\memory-mcp-windows-amd64.exe"
  if (!(Test-Path -LiteralPath $serverBin -PathType Leaf)) { throw "self-heal did not pre-warm the memory server binary" }

  foreach ($config in @(".mcp.json", ".cursor\mcp.json", ".codex\config.toml", ".agents\mcp_config.json")) {
    $command = (& $editor command "$root\$config" | Out-String).Trim()
    if ($command -ne ".agents/mcp/memory/run.cmd") { throw "self-heal did not retarget $config" }
  }

  # Warm caches (config editor and pre-warmed binary) must not touch the
  # release URL: any attempt against the invalid URL would fail and notice.
  [IO.File]::WriteAllText("$root\.agents\mcp\memory\RELEASE", "https://invalid.agent-parity.test`n")
  $second = @(& "$root\.agents\scripts\self-heal.ps1")
  if ($second.Count -ne 0) { throw "warm unchanged self-heal was not silent" }

  Write-Output "Windows fresh-pull zero-install self-heal: OK"
} finally {
  $env:AGENT_PARITY_CACHE = $oldCache
  if ($root.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
  }
}
