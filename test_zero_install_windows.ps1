param(
  [Parameter(Position = 0)]
  [string]$Version = "v9.8.7"
)

$ErrorActionPreference = "Stop"
$testRepoRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
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
  $base = "https://agent-parity.test"
  function Invoke-WebRequest {
    param(
      [switch]$UseBasicParsing,
      [Parameter(Mandatory = $true)][string]$Uri,
      [string]$OutFile
    )
    $prefix = "$base/"
    if (!$Uri.StartsWith($prefix, [StringComparison]::Ordinal)) { throw "unexpected test URL: $Uri" }
    $relative = $Uri.Substring($prefix.Length).Replace('/', [IO.Path]::DirectorySeparatorChar)
    $path = [IO.Path]::GetFullPath((Join-Path $testRepoRoot $relative))
    $repoPrefix = $testRepoRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (!$path.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "test URL does not map to a repository file: $Uri"
    }
    if (!$OutFile) { throw "zero-install download must use an atomic staging file" }
    Copy-Item -LiteralPath $path -Destination $OutFile -Force
  }

  New-Item -ItemType Directory -Force -Path "$root\.agents\scripts", "$root\.agents\mcp\memory", "$root\.cursor", "$root\.codex" | Out-Null
  Copy-Item -LiteralPath (Join-Path $testRepoRoot "templates\common.ps1"),(Join-Path $testRepoRoot "templates\self-heal.ps1") -Destination "$root\.agents\scripts"
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
  if (Test-Path -LiteralPath "$root\empty-cache\memory-mcp") { throw "self-heal downloaded memory-mcp" }

  foreach ($config in @(".mcp.json", ".cursor\mcp.json", ".codex\config.toml", ".agents\mcp_config.json")) {
    $command = (& $editor command "$root\$config" | Out-String).Trim()
    if ($command -ne ".agents/mcp/memory/run.cmd") { throw "self-heal did not retarget $config" }
  }

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
