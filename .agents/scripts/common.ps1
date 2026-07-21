# Shared PowerShell functions for project-local agent-parity commands.
param(
  [Parameter(Mandatory = $true)]
  [string]$Target
)

$ErrorActionPreference = "Stop"

$Repo = "libkim/agent-parity"
$ServerDir = ".agents/mcp/memory"
$StoreDir = ".agents/memory"
$ProjectCliDir = ".agents/bin"
$SyncScript = ".agents/scripts/sync-claude.ps1"
$CursorCli = ".cursor/cli.json"
$ClaudeSrc = ".agents/claude/settings.json"
$ClaudeTgt = ".claude/settings.json"
# SessionStart runs through the project-local launcher. Claude chooses the host
# shell; the launcher absorbs the Unix/Windows difference.
$ClaudeHook = '.agents/bin/agent-parity sync-claude'
$MarkBegin = "<!-- agent-parity:begin -->"
$MarkEnd = "<!-- agent-parity:end -->"
$GitIgnoreBegin = "# agent-parity:begin"
$GitIgnoreEnd = "# agent-parity:end"
$MergeDriverCmd = '.agents/scripts/merge-memory.sh %O %A %B'
$GaLine = ".agents/memory/*.md merge=agent-parity-memory"
$Artifacts = @(".mcp.json", ".cursor", ".codex", ".agents", "AGENTS.md", "CLAUDE.md")
$ParityBreakers = @(
  @{ File = ".cursorrules"; Who = "Cursor" }
)
$Launcher = ".agents/mcp/memory/run.cmd"
$OtherLauncher = ".agents/mcp/memory/run.sh"

$Target = (Resolve-Path -LiteralPath $Target).Path
$editorVersionPath = Join-Path $Target ".agents\mcp\memory\VERSION"
$editorVersion = if (Test-Path -LiteralPath $editorVersionPath -PathType Leaf) { ([IO.File]::ReadAllText($editorVersionPath)).Trim() } else { "missing" }
$cacheRoot = if ($env:AGENT_PARITY_CACHE) { $env:AGENT_PARITY_CACHE } elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "agent-parity\cache" } else { Join-Path $env:USERPROFILE ".cache\agent-parity" }
$ConfigEditor = if ($env:AGENT_PARITY_CONFIG_EDITOR) { $env:AGENT_PARITY_CONFIG_EDITOR } else { Join-Path $cacheRoot "config\$editorVersion\agent-parity-config-windows-amd64.exe" }

function Path-InTarget([string]$Rel) {
  return Join-Path $Target ($Rel.Replace('/', '\'))
}

function To-GitPath([string]$Rel) {
  return $Rel.Replace('\', '/')
}

function Ensure-Parent([string]$Path) {
  $parent = Split-Path -Parent $Path
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
}

function Read-Text([string]$Path) {
  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function New-StagingFile([string]$Path) {
  Ensure-Parent $Path
  $parent = Split-Path -Parent $Path
  $leaf = Split-Path -Leaf $Path
  do {
    $candidate = Join-Path $parent (".$leaf.agent-parity." + [Guid]::NewGuid().ToString("N") + ".tmp")
  } while (Test-Path -LiteralPath $candidate)
  $stream = [System.IO.File]::Open($candidate, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
  $stream.Dispose()
  return $candidate
}

function Write-Text([string]$Path, [string]$Text) {
  Ensure-Parent $Path
  $enc = New-Object System.Text.UTF8Encoding($false)
  $temp = New-StagingFile $Path
  try {
    [System.IO.File]::WriteAllText($temp, $Text, $enc)
    Move-Item -LiteralPath $temp -Destination $Path -Force
    $temp = $null
  } finally {
    if ($temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
  }
}

function Test-ClaudeWrapper([string]$Path) {
  $text = Read-Text $Path
  if ($null -eq $text) { return $false }
  $normalized = $text.Replace("`r`n", "`n")
  return $normalized -ceq "@AGENTS.md`n" -or $normalized -ceq "@AGENTS.md"
}

function For-EachMcpConfig([string]$Fn) {
  & $Fn ".mcp.json"               "templates/claude.mcp.json"             $Launcher
  & $Fn ".cursor/mcp.json"        "templates/cursor.mcp.json"             $Launcher
  & $Fn ".codex/config.toml"      "templates/codex.config.toml"           $Launcher
  & $Fn ".agents/mcp_config.json" "templates/antigravity.mcp_config.json" $Launcher
}

function Require-LocalConfigEditor {
  if (!(Test-Path -LiteralPath $ConfigEditor -PathType Leaf)) {
    throw "missing local config editor: $ConfigEditor"
  }
}

# Only self-heal calls this network-capable resolver. Other local management
# commands keep using Require-LocalConfigEditor, so uninstall stays offline.
function Ensure-LocalConfigEditor {
  if (Test-Path -LiteralPath $ConfigEditor -PathType Leaf) { return }
  if ($env:AGENT_PARITY_CONFIG_EDITOR) { throw "missing local config editor: $ConfigEditor" }
  if ($editorVersion -notmatch '^(v[0-9A-Za-z._-]+|dev)$') { throw "invalid agent-parity release version: $editorVersion" }

  $releasePath = Path-InTarget "$ServerDir/RELEASE"
  if (!(Test-Path -LiteralPath $releasePath -PathType Leaf)) { throw "missing pinned release URL: $releasePath" }
  $release = (Read-Text $releasePath).Trim()
  if (!$release) { throw "empty pinned release URL" }

  $asset = "agent-parity-config-windows-amd64.exe"
  $configDir = Split-Path -Parent $ConfigEditor
  New-Item -ItemType Directory -Force -Path $configDir | Out-Null
  $stage = Join-Path $configDir (".agent-parity-config." + [Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $stage | Out-Null
  try {
    $checksums = Join-Path $stage "checksums.txt"
    $binary = Join-Path $stage $asset
    Invoke-WebRequest -UseBasicParsing -Uri ($release.TrimEnd('/') + "/checksums.txt") -OutFile $checksums
    $line = Get-Content -LiteralPath $checksums | Where-Object { $_ -match "\s\*?$([regex]::Escape($asset))$" } | Select-Object -First 1
    if (!$line) { throw "checksum missing for $asset" }
    $expected = ($line -split '\s+')[0].ToLowerInvariant()
    if ($expected -notmatch '^[0-9a-f]{64}$') { throw "invalid checksum for $asset" }
    Invoke-WebRequest -UseBasicParsing -Uri ($release.TrimEnd('/') + "/" + $asset) -OutFile $binary
    $actual = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "checksum mismatch for $asset" }
    Move-Item -LiteralPath $binary -Destination $ConfigEditor -Force
  } finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Installed-Version {
  $versionFile = Path-InTarget "$ServerDir/VERSION"
  if (!(Test-Path -LiteralPath $versionFile -PathType Leaf)) { return "missing" }
  return (Read-Text $versionFile).Trim()
}

function Latest-Version {
  try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing -TimeoutSec 5
    if ($rel.tag_name) { return [string]$rel.tag_name }
  } catch {}
  return "unknown (network unavailable)"
}

function Compare-SemVer([string]$A, [string]$B) {
  $aa = $A.TrimStart('v') -split '\.'
  $bb = $B.TrimStart('v') -split '\.'
  if ($aa.Count -ne 3 -or $bb.Count -ne 3) { return $null }
  for ($i = 0; $i -lt 3; $i++) {
    if ($aa[$i] -notmatch '^\d+$' -or $bb[$i] -notmatch '^\d+$') { return $null }
    $ai = [int]$aa[$i]; $bi = [int]$bb[$i]
    if ($ai -lt $bi) { return -1 }
    if ($ai -gt $bi) { return 1 }
  }
  return 0
}

function Show-UpdateNotice([string]$Installed, [string]$Latest) {
  $cmp = Compare-SemVer $Installed $Latest
  if ($cmp -ne $null -and $cmp -lt 0) {
    Write-Output ""
    Write-Output "update available: $Installed -> $Latest"
    Write-Output "run from the project root: .\.agents\bin\agent-parity.cmd update"
  }
}


function Unreg-CursorCli {
  $t = Path-InTarget $CursorCli
  if (!(Test-Path -LiteralPath $t -PathType Leaf)) { return }
  $result = & $ConfigEditor unmerge-cursor-cli $t 2>$null
  if ($LASTEXITCODE -ne 0) { throw "could not safely update $CursorCli" }
  if (($result | Out-String).Trim() -eq "changed") {
    Write-Output "  unmerged:      $CursorCli (removed memory allowlist entry, kept the rest)"
  } else {
    Write-Output "  unchanged:     $CursorCli (memory allowlist entry not present)"
  }
}

function Unreg-AgentHooks {
  foreach ($entry in @(
    @{ Kind = "claude"; Path = $ClaudeSrc },
    @{ Kind = "claude"; Path = $ClaudeTgt },
    @{ Kind = "codex"; Path = ".codex/hooks.json" },
    @{ Kind = "cursor"; Path = ".cursor/hooks.json" },
    @{ Kind = "antigravity"; Path = ".agents/hooks.json" }
  )) {
    & $ConfigEditor unmerge-hook (Path-InTarget $entry.Path) $entry.Kind | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not safely remove $($entry.Kind) hook from $($entry.Path)" }
  }
  Write-Output "  hooks:      removed agent-parity self-heal handlers"
}

function Test-GitRepo {
  $isRepo = $false
  try {
    & git -C $Target rev-parse --is-inside-work-tree *> $null
    $isRepo = $LASTEXITCODE -eq 0
  } catch {
    $isRepo = $false
  } finally {
    # A missing repo is an expected probe result, not this script's exit code.
    $global:LASTEXITCODE = 0
  }
  return $isRepo
}

function Test-Ignored([string]$Rel) {
  if (!(Test-GitRepo)) { return $false }
  & git -C $Target check-ignore -q -- (To-GitPath $Rel) *> $null
  $isIgnored = $LASTEXITCODE -eq 0
  $global:LASTEXITCODE = 0
  return $isIgnored
}

function Get-ManagedBlockState([string]$Text, [string]$Begin, [string]$End) {
  if ($null -eq $Text) { return "absent" }
  $beginHits = [regex]::Matches($Text, [regex]::Escape($Begin)).Count
  $endHits = [regex]::Matches($Text, [regex]::Escape($End)).Count
  if ($beginHits -eq 0 -and $endHits -eq 0) { return "absent" }
  $lines = [regex]::Split($Text, "`r`n|`n|`r")
  $beginLine = -1
  $endLine = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -ceq $Begin) { $beginLine = $i }
    if ($lines[$i] -ceq $End) { $endLine = $i }
  }
  if ($beginHits -eq 1 -and $endHits -eq 1 -and $beginLine -ge 0 -and $beginLine -lt $endLine) { return "valid" }
  return "invalid"
}

function Strip-GitIgnoreBlock {
  $gi = Path-InTarget ".gitignore"
  $text = Read-Text $gi
  $lines = $text -split "`r?`n"
  $out = New-Object System.Collections.Generic.List[string]
  $inBlock = $false
  foreach ($line in $lines) {
    if ($line -eq $GitIgnoreBegin) { $inBlock = $true; continue }
    if ($line -eq $GitIgnoreEnd) { $inBlock = $false; continue }
    if (!$inBlock) { $out.Add($line) }
  }
  Write-Text $gi (($out -join "`n").TrimEnd("`n") + "`n")
}


function Strip-GitAttributesBlock {
  $ga = Path-InTarget ".gitattributes"
  $text = Read-Text $ga
  $lines = $text -split "`r?`n"
  $out = New-Object System.Collections.Generic.List[string]
  $inBlock = $false
  foreach ($line in $lines) {
    if ($line -eq $GitIgnoreBegin) { $inBlock = $true; continue }
    if ($line -eq $GitIgnoreEnd) { $inBlock = $false; continue }
    if (!$inBlock) { $out.Add($line) }
  }
  Write-Text $ga (($out -join "`n").TrimEnd("`n") + "`n")
}

function Test-MergeDriverRegistered {
  $current = & git -C $Target config merge.agent-parity-memory.driver 2>$null
  return ($LASTEXITCODE -eq 0 -and ($current | Out-String).Trim() -eq $MergeDriverCmd)
}

function Uninstall-Skills {
  $s = Path-InTarget $SyncScript
  # Strip our keys even when a partial installation has already lost its sync
  # script.
  foreach ($f in @($ClaudeTgt, $ClaudeSrc)) {
    $full = Path-InTarget $f
    if (!(Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    & $ConfigEditor unmerge-claude-settings $full | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not safely update $f" }
  }
  Remove-Item -LiteralPath $s -Force -ErrorAction SilentlyContinue
  # The skills we ship are our wiring, not user skills: remove both the source
  # and Claude's synced copy so no dangling copy survives uninstall.
  foreach ($sk in @("agent-parity", "write-requirement", "write-governance")) {
    Remove-Item -LiteralPath (Path-InTarget ".agents/skills/$sk") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Path-InTarget ".claude/skills/$sk") -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Output "skills: removed sync wiring"
}

function Warn-Parity {
  foreach ($p in $ParityBreakers) {
    if (Test-Path -LiteralPath (Path-InTarget $p.File)) {
      Write-Output "parity: $($p.File) exists -- only $($p.Who) reads it, so agents diverge; fold it into AGENTS.md"
    }
  }
}

function Status-Skills {
  if (!(Test-Path -LiteralPath (Path-InTarget $SyncScript))) {
    Write-Output "skills: sync wiring missing"
    return
  }
  $skillDir = Path-InTarget ".agents/skills"
  $n = 0
  if (Test-Path -LiteralPath $skillDir) {
    $n = @(Get-ChildItem -LiteralPath $skillDir -Directory | Where-Object { $_.Name -notin @("agent-parity", "write-requirement", "write-governance") }).Count
  }
  Write-Output "skills: $n in .agents/skills; sync script present"
  foreach ($sk in @("agent-parity", "write-requirement", "write-governance")) {
    if (Test-Path -LiteralPath (Join-Path $skillDir "$sk/SKILL.md")) {
      Write-Output "  shipped skill $sk`: present"
    } else {
      Write-Output "  shipped skill $sk`: missing"
    }
  }
  if (!(Test-Path -LiteralPath $ConfigEditor -PathType Leaf)) { Write-Output "  hook: unknown (local config editor missing)"; return }
  & $ConfigEditor has-sync-hook (Path-InTarget $ClaudeSrc) $ClaudeHook 2>$null
  $srcCode = $LASTEXITCODE
  & $ConfigEditor has-sync-hook (Path-InTarget $ClaudeTgt) $ClaudeHook 2>$null
  $tgtCode = $LASTEXITCODE
  if ($srcCode -eq 0) { Write-Output "  hook: registered ($ClaudeSrc)" }
  elseif ($tgtCode -eq 0) { Write-Output "  hook: registered ($ClaudeTgt)" }
  else { Write-Output "  hook: missing -- Claude Code will not auto-sync skills" }
}

function Status-CodexMcp {
  if (!(Get-Command codex -ErrorAction SilentlyContinue)) {
    Write-Output "codex mcp: codex CLI not found"
    return
  }
  Push-Location -LiteralPath $Target
  $out = @()
  $code = 1
  try {
    try {
      $out = & codex mcp get memory 2>&1
      $code = $LASTEXITCODE
    } catch {
      $out = @($_.Exception.Message)
      $code = 1
    }
  } finally {
    Pop-Location
  }
  if ($code -ne 0) {
    Write-Output "codex mcp: memory not registered/enabled for this project"
    $out | ForEach-Object { Write-Output "  $_" }
    return
  }
  $text = ($out | Out-String)
  if ($text -match 'enabled:\s+true') { Write-Output "codex mcp: memory registered/enabled" }
  else { Write-Output "codex mcp: memory found but not enabled" }
  if ($text.Contains($Launcher)) { Write-Output "  command: $Launcher" }
  else { Write-Output "  command: check with 'codex mcp get memory'" }
  Write-Output "  note: Codex loads MCP tools when a session starts; restart the agent session if memory_recent/memory_add are not visible."
}


function Unreg-McpConfig([string]$Rel, [string]$Template, [string]$Marker) {
  $t = Path-InTarget $Rel
  $text = Read-Text $t
  if ($null -eq $text) { return }
  if (!(Test-Path -LiteralPath $ConfigEditor -PathType Leaf)) { Write-Output "  edit manually: $Rel -- local config editor missing"; return }
  $result = & $ConfigEditor unmerge $t 2>$null
  if ($LASTEXITCODE -eq 0 -and ($result | Out-String).Trim() -eq "changed") {
    Write-Output "  unmerged:      $Rel (removed memory server entry, kept the rest)"
  } elseif ($LASTEXITCODE -ne 0) {
    Write-Output "  edit manually: $Rel -- invalid JSON/TOML"
  }
}

function Unreg-ClaudeWrapper {
  $path = Path-InTarget "CLAUDE.md"
  $text = Read-Text $path
  if ($null -eq $text) { return }
  if (Test-ClaudeWrapper $path) {
    Remove-Item -LiteralPath $path -Force
    Write-Output "claude wrapper: removed CLAUDE.md"
  } else {
    Write-Output "claude wrapper: existing CLAUDE.md preserved"
  }
}

function Status-McpRegistration([string]$Label, [string]$Rel, [string]$Marker) {
  $t = Path-InTarget $Rel
  $text = Read-Text $t
  if ($null -eq $text) { Write-Output "  ${Label}: config missing ($Rel)" }
  elseif ($Marker -eq $Launcher) {
    if (!(Test-Path -LiteralPath $ConfigEditor -PathType Leaf)) { Write-Output "  ${Label}: unknown (local config editor missing)"; return }
    $command = & $ConfigEditor command $t 2>$null
    $code = $LASTEXITCODE
    $command = ($command | Out-String).Trim()
    if ($code -eq 0 -and $command -eq $Marker) { Write-Output "  ${Label}: registered ($Rel)" }
    elseif ($code -eq 0 -and $command -eq $OtherLauncher) { Write-Output "  ${Label}: registered for Unix ($Rel; self-heal will retarget it when the next session starts)" }
    elseif ($code -eq 0) { Write-Output "  ${Label}: points elsewhere ($Rel has a memory entry not using $ServerDir)" }
    elseif ($code -eq 1) { Write-Output "  ${Label}: not registered ($Rel)" }
    else { Write-Output "  ${Label}: invalid JSON/TOML ($Rel)" }
  } else {
    Write-Output "  ${Label}: not registered ($Rel)"
  }
}

function Status-McpRegistrations {
  Write-Output "mcp registrations:"
  Status-McpRegistration "Claude Code"     ".mcp.json"               $Launcher
  Status-McpRegistration "Cursor"          ".cursor/mcp.json"        $Launcher
  Status-McpRegistration "Codex"           ".codex/config.toml"      $Launcher
  Status-McpRegistration "Antigravity CLI" ".agents/mcp_config.json" $Launcher
}

function Status-ClaudeWrapper {
  $text = Read-Text (Path-InTarget "CLAUDE.md")
  if ($null -eq $text) {
    Write-Output "claude wrapper: missing (CLAUDE.md)"
  } elseif (Test-ClaudeWrapper (Path-InTarget "CLAUDE.md")) {
    Write-Output "claude wrapper: registered (CLAUDE.md)"
  } else {
    Write-Output "claude wrapper: not registered (existing CLAUDE.md preserved)"
  }
}

function Status-AgentHooks {
  Write-Output "self-heal hooks:"
  foreach ($entry in @(
    @{ Kind = "claude"; Path = $ClaudeSrc },
    @{ Kind = "codex"; Path = ".codex/hooks.json" },
    @{ Kind = "cursor"; Path = ".cursor/hooks.json" },
    @{ Kind = "antigravity"; Path = ".agents/hooks.json" }
  )) {
    if (!(Test-Path -LiteralPath $ConfigEditor -PathType Leaf)) {
      Write-Output "  $($entry.Kind): unknown (local config editor missing)"
      continue
    }
    & $ConfigEditor has-agent-hook (Path-InTarget $entry.Path) $entry.Kind 2>$null
    if ($LASTEXITCODE -eq 0) {
      Write-Output "  $($entry.Kind): registered ($($entry.Path))"
    } else {
      Write-Output "  $($entry.Kind): missing ($($entry.Path))"
    }
  }
  Write-Output "  note: Codex project hooks must be reviewed and trusted before they run"
}

function Status-AgentDiagnostics {
  Write-Output "agent-specific diagnostics:"
  if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Output "  Claude Code: CLI found; no noninteractive MCP tool-visibility check implemented"
    Write-Output "    check inside Claude Code with /mcp if memory tools are not visible."
  } else { Write-Output "  Claude Code: CLI not found" }
  if (Get-Command cursor -ErrorAction SilentlyContinue) {
    Write-Output "  Cursor: CLI found; no noninteractive MCP tool-visibility check implemented"
  } else { Write-Output "  Cursor: CLI not found" }
  $codex = @(Status-CodexMcp)
  if ($codex.Count -gt 0) {
    Write-Output "  Codex: $($codex[0])"
    if ($codex.Count -gt 1) { $codex[1..($codex.Count - 1)] | ForEach-Object { Write-Output "         $_" } }
  }
  if (Get-Command antigravity -ErrorAction SilentlyContinue) {
    Write-Output "  Antigravity CLI: CLI found; no noninteractive MCP tool-visibility check implemented"
  } else { Write-Output "  Antigravity CLI: CLI not found" }
}
