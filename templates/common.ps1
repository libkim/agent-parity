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
$Artifacts = @(".mcp.json", ".cursor", ".codex", ".agents", "AGENTS.md", "CLAUDE.md")
$ParityBreakers = @(
  @{ File = ".cursorrules"; Who = "Cursor" }
)
$Launcher = ".agents/mcp/memory/run.cmd"
$OtherLauncher = ".agents/mcp/memory/run.sh"
$ManagedLaunchers = @($Launcher, $OtherLauncher)
$ManagedSelfHealCommands = @(
  '.agents/bin/agent-parity self-heal',
  'sh -c ''root=$(git rev-parse --show-toplevel) && exec "$root/.agents/bin/agent-parity" self-heal''',
  'powershell -NoProfile -ExecutionPolicy Bypass -Command "& (Join-Path (git rev-parse --show-toplevel) ''.agents/bin/agent-parity.cmd'') self-heal"',
  '.agents/bin/agent-parity.cmd self-heal'
)
$ManagedSyncCommands = @(
  'bash "$CLAUDE_PROJECT_DIR/.agents/scripts/sync-claude.sh" sync',
  'powershell -NoProfile -ExecutionPolicy Bypass -Command "& \"$env:CLAUDE_PROJECT_DIR/.agents/scripts/sync-claude.ps1\" sync"',
  '.agents/bin/agent-parity sync-claude'
)
$MemoryPermissions = @(
  'mcp__memory__memory_add',
  'mcp__memory__memory_recent',
  'mcp__memory__memory_search',
  'mcp__memory__memory_get'
)

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

function Write-Text([string]$Path, [string]$Text) {
  Ensure-Parent $Path
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function For-EachConfig([string]$Fn) {
  & $Fn ".mcp.json"               "templates/claude.mcp.json"             $Launcher
  & $Fn ".cursor/mcp.json"        "templates/cursor.mcp.json"             $Launcher
  & $Fn ".codex/config.toml"      "templates/codex.config.toml"           $Launcher
  & $Fn ".agents/mcp_config.json" "templates/antigravity.mcp_config.json" $Launcher
  & $Fn "CLAUDE.md"               "templates/CLAUDE.md"                   "@AGENTS.md"
}

function Normalize-ManagedCommand([object]$Command) {
  if ($Command -isnot [string]) { return "" }
  return $Command.Trim().Replace('\', '/')
}

function Test-ManagedCommand([object]$Command, [string[]]$Candidates) {
  $normalized = Normalize-ManagedCommand $Command
  return $Candidates | Where-Object { (Normalize-ManagedCommand $_) -eq $normalized } | Select-Object -First 1
}

function Remove-JsonProperty([object]$Object, [string]$Name) {
  if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) {
    $Object.PSObject.Properties.Remove($Name)
  }
}

function Test-JsonObjectEmpty([object]$Object) {
  return $null -eq $Object -or @($Object.PSObject.Properties).Count -eq 0
}

function Write-JsonOrRemove([string]$Path, [object]$Root, [hashtable]$Ignorable = @{}) {
  $properties = @($Root.PSObject.Properties)
  $onlyIgnorable = $properties.Count -eq $Ignorable.Count
  if ($onlyIgnorable) {
    foreach ($property in $properties) {
      if (!$Ignorable.ContainsKey($property.Name) -or $Ignorable[$property.Name] -ne $property.Value) {
        $onlyIgnorable = $false
        break
      }
    }
  }
  if ($properties.Count -eq 0 -or $onlyIgnorable) {
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  } else {
    Write-Text $Path (($Root | ConvertTo-Json -Depth 100) + "`n")
  }
}

function Remove-NestedHandlers([object]$Root, [string]$Event, [string[]]$Commands) {
  $hooks = $Root.hooks
  if ($null -eq $hooks -or $null -eq $hooks.$Event) { return $false }
  $changed = $false
  $keptGroups = @()
  foreach ($group in @($hooks.$Event)) {
    if ($null -eq $group.hooks) { $keptGroups += $group; continue }
    $kept = @()
    foreach ($handler in @($group.hooks)) {
      if (Test-ManagedCommand $handler.command $Commands) { $changed = $true } else { $kept += $handler }
    }
    if ($kept.Count -gt 0) { $group.hooks = $kept; $keptGroups += $group }
  }
  if ($changed) {
    if ($keptGroups.Count -gt 0) { $hooks.$Event = $keptGroups } else { Remove-JsonProperty $hooks $Event }
    if (Test-JsonObjectEmpty $hooks) { Remove-JsonProperty $Root "hooks" }
  }
  return $changed
}

function Remove-FlatHandlers([object]$Root, [string]$Event, [string[]]$Commands, [bool]$Cursor = $false) {
  $container = if ($Cursor) { $Root.hooks } else { $Root }
  if ($null -eq $container -or $null -eq $container.$Event) { return $false }
  $original = @($container.$Event)
  $kept = @($original | Where-Object { -not (Test-ManagedCommand $_.command $Commands) })
  if ($kept.Count -eq $original.Count) { return $false }
  if ($kept.Count -gt 0) { $container.$Event = $kept } else { Remove-JsonProperty $container $Event }
  if ($Cursor -and (Test-JsonObjectEmpty $container)) { Remove-JsonProperty $Root "hooks" }
  return $true
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
  $text = Read-Text $t
  if ($null -eq $text) { return }
  try { $root = $text | ConvertFrom-Json } catch { Write-Output "  edit manually: $CursorCli -- invalid JSON"; return }
  if ($null -eq $root.permissions -or $null -eq $root.permissions.allow) {
    Write-Output "  unchanged:     $CursorCli (memory allowlist entry not present)"
    return
  }
  $original = @($root.permissions.allow)
  $allow = @($original | Where-Object { $_ -ne 'Mcp(memory:*)' })
  if ($allow.Count -eq $original.Count) {
    Write-Output "  unchanged:     $CursorCli (memory allowlist entry not present)"
    return
  }
  if ($allow.Count -gt 0) { $root.permissions.allow = $allow } else { Remove-JsonProperty $root.permissions "allow" }
  if ($null -ne $root.permissions.deny -and @($root.permissions.deny).Count -eq 0) { Remove-JsonProperty $root.permissions "deny" }
  if (Test-JsonObjectEmpty $root.permissions) { Remove-JsonProperty $root "permissions" }
  Write-JsonOrRemove $t $root
  Write-Output "  unmerged:      $CursorCli (removed memory allowlist entry, kept the rest)"
}

function Unreg-AgentHooks {
  Unreg-AgentHook (Path-InTarget $ClaudeSrc) "claude"
  Unreg-AgentHook (Path-InTarget $ClaudeTgt) "claude"
  Unreg-AgentHook (Path-InTarget ".codex/hooks.json") "codex"
  Unreg-AgentHook (Path-InTarget ".cursor/hooks.json") "cursor"
  Unreg-AgentHook (Path-InTarget ".agents/hooks.json") "antigravity"
  Write-Output "  hooks:      removed agent-parity self-heal handlers"
}

function Unreg-AgentHook([string]$Path, [string]$Kind) {
  $text = Read-Text $Path
  if ($null -eq $text) { return }
  try { $root = $text | ConvertFrom-Json } catch { Write-Output "  edit manually: $Path -- invalid hook JSON"; return }
  if ($Kind -in @("claude", "codex")) {
    $changed = Remove-NestedHandlers $root "SessionStart" $ManagedSelfHealCommands
  } elseif ($Kind -eq "cursor") {
    $changed = Remove-FlatHandlers $root "sessionStart" $ManagedSelfHealCommands $true
  } else {
    $changed = Remove-FlatHandlers $root "PreInvocation" $ManagedSelfHealCommands
  }
  if ($changed) {
    $ignorable = if ($Kind -eq "cursor") { @{ version = 1 } } elseif ($Kind -eq "antigravity") { @{ enabled = $true } } else { @{} }
    Write-JsonOrRemove $Path $root $ignorable
  }
}

function Test-GitRepo {
  try {
    & git -C $Target rev-parse --is-inside-work-tree *> $null
    return $LASTEXITCODE -eq 0
  } catch { return $false }
}

function Test-Ignored([string]$Rel) {
  if (!(Test-GitRepo)) { return $false }
  & git -C $Target check-ignore -q -- (To-GitPath $Rel) *> $null
  return $LASTEXITCODE -eq 0
}

function Strip-GitIgnoreBlock {
  $gi = Path-InTarget ".gitignore"
  $text = Read-Text $gi
  if ($null -eq $text -or !$text.Contains($GitIgnoreBegin) -or !$text.Contains($GitIgnoreEnd)) { return }
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


function Uninstall-Skills {
  $s = Path-InTarget $SyncScript
  # Strip our keys even when a partial installation has already lost its sync
  # script.
  foreach ($f in @($ClaudeTgt, $ClaudeSrc)) {
    $full = Path-InTarget $f
    if (Test-Path -LiteralPath $full) { Unreg-ClaudeSettings $full }
  }
  Remove-Item -LiteralPath $s -Force -ErrorAction SilentlyContinue
  # The agent-parity skill is our wiring, not a user skill: remove both the
  # source and Claude's synced copy so no dangling copy survives uninstall.
  Remove-Item -LiteralPath (Path-InTarget ".agents/skills/agent-parity") -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Path-InTarget ".claude/skills/agent-parity") -Recurse -Force -ErrorAction SilentlyContinue
  Write-Output "skills: removed sync wiring"
}

function Unreg-ClaudeSettings([string]$Path) {
  $text = Read-Text $Path
  if ($null -eq $text) { return }
  try { $root = $text | ConvertFrom-Json } catch { Write-Output "  edit manually: $Path -- invalid Claude settings JSON"; return }
  $before = $root | ConvertTo-Json -Depth 100 -Compress
  Remove-JsonProperty $root "autoMemoryEnabled"
  if ($null -ne $root.enabledMcpjsonServers) {
    $servers = @($root.enabledMcpjsonServers | Where-Object { $_ -ne "memory" })
    if ($servers.Count -gt 0) { $root.enabledMcpjsonServers = $servers } else { Remove-JsonProperty $root "enabledMcpjsonServers" }
  }
  if ($null -ne $root.permissions -and $null -ne $root.permissions.allow) {
    $allow = @($root.permissions.allow | Where-Object { $_ -notin $MemoryPermissions })
    if ($allow.Count -gt 0) { $root.permissions.allow = $allow } else { Remove-JsonProperty $root.permissions "allow" }
    if (Test-JsonObjectEmpty $root.permissions) { Remove-JsonProperty $root "permissions" }
  }
  [void](Remove-NestedHandlers $root "SessionStart" ($ManagedSyncCommands + $ManagedSelfHealCommands))
  $after = $root | ConvertTo-Json -Depth 100 -Compress
  if ($before -ne $after) { Write-JsonOrRemove $Path $root }
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
    $n = @(Get-ChildItem -LiteralPath $skillDir -Directory | Where-Object { $_.Name -ne "agent-parity" }).Count
  }
  Write-Output "skills: $n in .agents/skills; sync script present"
  if (Test-Path -LiteralPath (Join-Path $skillDir "agent-parity/SKILL.md")) {
    Write-Output "  management skill: present"
  } else {
    Write-Output "  management skill: missing"
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


function Unreg-Config([string]$Rel, [string]$Template, [string]$Marker) {
  $t = Path-InTarget $Rel
  $text = Read-Text $t
  if ($null -eq $text) { return }
  if ($Rel -eq "CLAUDE.md") {
    if ($text.TrimEnd([char[]]"`r`n") -ceq "@AGENTS.md") {
      Remove-Item -LiteralPath $t -Force
      Write-Output "  removed:       $Rel"
    }
    return
  }
  if ($Marker -eq $Launcher) {
    if (!(Test-Path -LiteralPath $ConfigEditor -PathType Leaf)) { Write-Output "  edit manually: $Rel -- local config editor missing"; return }
    $result = & $ConfigEditor unmerge $t 2>$null
    if ($LASTEXITCODE -eq 0 -and ($result | Out-String).Trim() -eq "changed") {
      Write-Output "  unmerged:      $Rel (removed memory server entry, kept the rest)"
    } elseif ($LASTEXITCODE -ne 0) {
      Write-Output "  edit manually: $Rel -- invalid JSON/TOML"
    }
  }
}

function Status-AgentConfig([string]$Label, [string]$Rel, [string]$Marker) {
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
  } elseif ($Rel -eq "CLAUDE.md" -and $text.TrimEnd([char[]]"`r`n") -ceq "@AGENTS.md") {
    Write-Output "  ${Label}: registered ($Rel)"
  } else {
    Write-Output "  ${Label}: not registered ($Rel)"
  }
}

function Status-McpRegistrations {
  Write-Output "mcp registrations:"
  Status-AgentConfig "Claude Code"     ".mcp.json"               $Launcher
  Status-AgentConfig "Cursor"          ".cursor/mcp.json"        $Launcher
  Status-AgentConfig "Codex"           ".codex/config.toml"      $Launcher
  Status-AgentConfig "Antigravity CLI" ".agents/mcp_config.json" $Launcher
  Status-AgentConfig "Claude wrapper"  "CLAUDE.md"               "@AGENTS.md"
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
