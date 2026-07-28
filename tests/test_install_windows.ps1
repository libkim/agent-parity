param(
  [Parameter(Position = 0)]
  [string]$Version = "v9.8.7"
)

$ErrorActionPreference = "Stop"
$testRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$dist = Join-Path $testRepoRoot "dist"
if (!(Test-Path -LiteralPath (Join-Path $dist "agent-parity-config-windows-amd64.exe") -PathType Leaf)) {
  throw "build release assets first"
}

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempBase ("ap-win-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$testRoot = (Resolve-Path -LiteralPath $testRoot).Path
if (!$testRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
  throw "unsafe test path: $testRoot"
}

$oldRaw = $env:AGENT_PARITY_RAW
$oldRelease = $env:AGENT_PARITY_RELEASE
$oldVersion = $env:AGENT_PARITY_VERSION
$oldCache = $env:AGENT_PARITY_CACHE

try {
  $base = "https://agent-parity.test"
  $allowDownloads = $true
  function Invoke-WebRequest {
    param(
      [switch]$UseBasicParsing,
      [Parameter(Mandatory = $true)][string]$Uri,
      [string]$OutFile
    )
    if (!$allowDownloads) { throw "network access attempted after the test disabled downloads: $Uri" }
    $prefix = "$base/"
    if (!$Uri.StartsWith($prefix, [StringComparison]::Ordinal)) { throw "unexpected test URL: $Uri" }
    $relative = $Uri.Substring($prefix.Length).Replace('/', [IO.Path]::DirectorySeparatorChar)
    $path = [IO.Path]::GetFullPath((Join-Path $testRepoRoot $relative))
    $repoPrefix = $testRepoRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (!$path.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "test URL does not map to a repository file: $Uri"
    }
    if ($OutFile) {
      Copy-Item -LiteralPath $path -Destination $OutFile -Force
      return
    }
    return [pscustomobject]@{ Content = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) }
  }

  [IO.File]::WriteAllText((Join-Path $testRoot ".mcp.json"), '{"user":true,"mcpServers":{"other":{"command":"other"}}}')
  New-Item -ItemType Directory -Path (Join-Path $testRoot ".cursor") | Out-Null
  [IO.File]::WriteAllText((Join-Path $testRoot ".cursor\cli.json"), '{"theme":"dark","permissions":{"allow":["Shell(git:*)"]}}')
  [IO.File]::WriteAllText((Join-Path $testRoot "AGENTS.md"), "user instructions`n")

  $env:AGENT_PARITY_RAW = $base
  $env:AGENT_PARITY_RELEASE = "$base/dist"
  $env:AGENT_PARITY_VERSION = $null
  $env:AGENT_PARITY_CACHE = Join-Path $testRoot "c"

  Push-Location -LiteralPath $testRoot
  try {
    Invoke-Expression ([IO.File]::ReadAllText((Join-Path $dist "install.ps1"), [Text.Encoding]::UTF8))
  } finally {
    Pop-Location
  }
  if ($LASTEXITCODE -ne 0) { throw "successful install leaked native exit code $LASTEXITCODE" }

  $installedVersion = [IO.File]::ReadAllText((Join-Path $testRoot ".agents\mcp\memory\VERSION")).Trim()
  if ($installedVersion -ne $Version) { throw "installed version is $installedVersion, expected $Version" }
  if (!(Test-Path -LiteralPath (Join-Path $testRoot ".agents\bin\agent-parity.cmd") -PathType Leaf)) { throw "Windows launcher missing" }
  if (Test-Path -LiteralPath (Join-Path $testRoot "c\memory") -PathType Container) { throw "install eagerly downloaded memory-mcp" }

  $mcp = Get-Content -LiteralPath (Join-Path $testRoot ".mcp.json") -Raw | ConvertFrom-Json
  if (!$mcp.user -or !$mcp.mcpServers.other -or !$mcp.mcpServers.memory) { throw "install did not preserve and merge MCP settings" }
  $cursor = Get-Content -LiteralPath (Join-Path $testRoot ".cursor\cli.json") -Raw | ConvertFrom-Json
  if ($cursor.theme -ne "dark" -or $cursor.permissions.allow -notcontains "Shell(git:*)" -or $cursor.permissions.allow -notcontains "Mcp(memory:*)") { throw "install did not preserve and merge Cursor CLI settings" }
  $cursorHooks = Get-Content -LiteralPath (Join-Path $testRoot ".cursor\hooks.json") -Raw | ConvertFrom-Json
  if ($cursorHooks.hooks.sessionStart[0].command -ne ".agents/bin/agent-parity self-heal") { throw "Cursor hook is not platform-neutral" }
  $antigravityHooks = Get-Content -LiteralPath (Join-Path $testRoot ".agents\hooks.json") -Raw | ConvertFrom-Json
  if ($null -ne $antigravityHooks.PreInvocation) { throw "Antigravity hook uses the obsolete root event shape" }
  if ($antigravityHooks.'agent-parity'.enabled -ne $true -or $antigravityHooks.'agent-parity'.PreInvocation[0].command -ne ".agents/bin/agent-parity self-heal") {
    throw "Antigravity managed hook block is missing or not platform-neutral"
  }
  $agentsText = [IO.File]::ReadAllText((Join-Path $testRoot "AGENTS.md"))
  foreach ($requiredInstruction in @(
    "## Shared memory and agent state",
    'This project uses `agent-parity`',
    "repository state, not disposable generated files",
    "Cross-agent bootstrap:",
    ".agents/mcp/memory/run.sh",
    ".agents/mcp/memory/run.cmd",
    "Use built-in file read/edit tools",
    "the current agent must be restarted",
    'call `memory_recent` to verify the current session',
    "every changed agent-parity-managed file"
  )) {
    if (!$agentsText.Contains($requiredInstruction)) { throw "AGENTS.md is missing instruction: $requiredInstruction" }
  }

  $statusPath = Join-Path $testRoot ".agents\scripts\status.ps1"
  [IO.File]::WriteAllText($statusPath, "stale")
  Push-Location -LiteralPath $testRoot
  try {
    $sameVersionOutput = @(Invoke-Expression ([IO.File]::ReadAllText((Join-Path $dist "update.ps1"), [Text.Encoding]::UTF8)) 3>&1)
  } finally {
    Pop-Location
  }
  if ((($sameVersionOutput | Out-String).Trim()) -ne "already up to date: $Version") { throw "same-version update did not stop immediately: $sameVersionOutput" }
  if ([IO.File]::ReadAllText($statusPath) -ne "stale") { throw "same-version update modified managed files" }

  $crlfFiles = @(
    ".agents\scripts\common.ps1",
    ".agents\skills\agent-parity\SKILL.md",
    ".agents\mcp\memory\run.cmd"
  )
  foreach ($relative in $crlfFiles) {
    $path = Join-Path $testRoot $relative
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8).Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
  }
  [IO.File]::WriteAllText((Join-Path $testRoot ".agents\mcp\memory\VERSION"), "v0.0.0-old`r`n", (New-Object Text.UTF8Encoding($false)))
  [IO.File]::WriteAllText((Join-Path $testRoot ".cursorrules"), "")
  Push-Location -LiteralPath $testRoot
  try {
    $updateOutput = @(Invoke-Expression ([IO.File]::ReadAllText((Join-Path $dist "update.ps1"), [Text.Encoding]::UTF8)) 3>&1)
  } finally {
    Pop-Location
  }
  if ($LASTEXITCODE -ne 0) { throw "successful update leaked native exit code $LASTEXITCODE" }
  if ([IO.File]::ReadAllText($statusPath) -eq "stale") { throw "update did not refresh local management scripts" }
  if (!(($updateOutput | Out-String).Contains("parity: .cursorrules exists -- only Cursor reads it, so agents diverge; fold it into AGENTS.md"))) { throw "update did not report the install parity warning" }
  foreach ($relative in @($crlfFiles + ".agents\mcp\memory\VERSION")) {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $testRoot $relative))
    $withoutCrlf = ([Text.Encoding]::UTF8.GetString($bytes)).Replace("`r`n", "")
    if ($withoutCrlf.Contains("`n")) { throw "update introduced bare LF into CRLF file: $relative" }
  }

  $cursorPath = Join-Path $testRoot ".cursor\cli.json"
  $codexPath = Join-Path $testRoot ".codex\config.toml"
  $cursorBeforeWarningTest = [IO.File]::ReadAllText($cursorPath)
  $codexBeforeWarningTest = [IO.File]::ReadAllText($codexPath)
  [IO.File]::WriteAllText($cursorPath, '{"permissions":"user-value"}')
  [IO.File]::WriteAllText($codexPath, "[mcp_servers.memory]`ncommand = `".agents/mcp/memory/run.cmd`"`ndefault_tools_approval_mode = `"prompt`"`n")
  Remove-Item -LiteralPath (Join-Path $testRoot ".agents\hooks.json") -Force
  [IO.File]::WriteAllText((Join-Path $testRoot ".agents\mcp\memory\VERSION"), "v0.0.0-old`n")
  $updateSource = [IO.File]::ReadAllText((Join-Path $dist "update.ps1"), [Text.Encoding]::UTF8)
  $updateBlock = [scriptblock]::Create($updateSource)
  # Match project-agent-parity.cmd exactly: downloaded text becomes a new
  # ScriptBlock and the call operator invokes it in a child scope. The former
  # $script:ConfigEditor assignment left the child-local $ConfigEditor null.
  $warningOutput = @(& $updateBlock "update" $testRoot 3>&1)
  $warningText = ($warningOutput | Out-String)
  if ($LASTEXITCODE -ne 0) { throw "update with configuration warnings failed with $LASTEXITCODE" }
  if (!$warningText.Contains("updated:    .codex/config.toml") -or !$warningText.Contains(".cursor/cli.json")) { throw "configuration ownership results were incorrect: $warningText" }
  if (!$warningText.Contains("configuration: completed with 1 warning(s)")) { throw "configuration warning summary missing: $warningText" }
  if ([IO.File]::ReadAllText($cursorPath) -ne '{"permissions":"user-value"}') { throw "conflicting Cursor config was rewritten" }
  if (![IO.File]::ReadAllText($codexPath).Contains('default_tools_approval_mode = "approve"')) { throw "owned Codex approval did not converge" }
  if (!(Test-Path -LiteralPath (Join-Path $testRoot ".agents\hooks.json"))) { throw "later Antigravity hook did not converge after earlier warnings" }

  [IO.File]::WriteAllText($cursorPath, $cursorBeforeWarningTest)
  [IO.File]::WriteAllText($codexPath, $codexBeforeWarningTest)
  [IO.File]::WriteAllText((Join-Path $testRoot ".agents\mcp\memory\VERSION"), "v0.0.0-old`n")
  & $updateBlock "update" $testRoot | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "cleanup update failed with $LASTEXITCODE" }

  $allowDownloads = $false
  & (Join-Path $testRoot ".agents\bin\agent-parity.cmd") uninstall
  if ($LASTEXITCODE -ne 0) { throw "offline Windows uninstall failed with $LASTEXITCODE" }
  if (Test-Path -LiteralPath (Join-Path $testRoot ".agents\mcp\memory")) { throw "uninstall left the project memory server directory" }
  if (Test-Path -LiteralPath (Join-Path $testRoot ".cursor\hooks.json")) { throw "uninstall left the managed Cursor hook file" }
  if (Test-Path -LiteralPath (Join-Path $testRoot ".agents\hooks.json")) { throw "uninstall left the managed Antigravity hook file" }

  $mcp = Get-Content -LiteralPath (Join-Path $testRoot ".mcp.json") -Raw | ConvertFrom-Json
  if (!$mcp.user -or !$mcp.mcpServers.other -or $mcp.mcpServers.memory) { throw "uninstall damaged MCP settings" }
  $cursor = Get-Content -LiteralPath (Join-Path $testRoot ".cursor\cli.json") -Raw | ConvertFrom-Json
  if ($cursor.theme -ne "dark" -or $cursor.permissions.allow -notcontains "Shell(git:*)" -or $cursor.permissions.allow -contains "Mcp(memory:*)") { throw "uninstall damaged Cursor CLI settings" }
  if (!(Get-Content -LiteralPath (Join-Path $testRoot "AGENTS.md") -Raw).Contains("user instructions")) { throw "uninstall lost user AGENTS.md content" }

  Write-Output "Windows README-style install, update, and offline uninstall: OK"
} finally {
  $env:AGENT_PARITY_RAW = $oldRaw
  $env:AGENT_PARITY_RELEASE = $oldRelease
  $env:AGENT_PARITY_VERSION = $oldVersion
  $env:AGENT_PARITY_CACHE = $oldCache
  if ($testRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
