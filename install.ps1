# agent-parity: native Windows installer for a cross-agent environment.
#
#   irm https://raw.githubusercontent.com/libkim/agent-parity/main/install.ps1 | iex
#
# Commands: install, update, uninstall [-Purge], status, version.

[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$Command = "install",
  [Parameter(Position = 1)]
  [string]$Target = ".",
  [switch]$Purge,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Rest
)

$ErrorActionPreference = "Stop"

$Repo = "libkim/agent-parity"
$Raw = if ($env:AGENT_PARITY_RAW) { $env:AGENT_PARITY_RAW } else { "https://raw.githubusercontent.com/$Repo/main" }
$Release = if ($env:AGENT_PARITY_RELEASE) { $env:AGENT_PARITY_RELEASE } else { "https://github.com/$Repo/releases/latest/download" }
$ServerDir = ".agents/mcp/memory"
$StoreDir = ".agents/memory"
$ProjectCliDir = ".agents/bin"
$SyncScript = ".agents/scripts/sync-claude.ps1"
$CursorCli = ".cursor/cli.json"
$ClaudeSrc = ".agents/claude/settings.json"
$ClaudeTgt = ".claude/settings.json"
$MarkBegin = "<!-- agent-parity:begin -->"
$MarkEnd = "<!-- agent-parity:end -->"
$GitIgnoreBegin = "# agent-parity:begin"
$GitIgnoreEnd = "# agent-parity:end"
$Artifacts = @(".mcp.json", ".cursor", ".codex", ".agents", "AGENTS.md", "CLAUDE.md")
$ParityBreakers = @(
  @{ File = ".cursorrules"; Who = "Cursor" }
)
$AllBins = @(
  "memory-mcp-linux-amd64",
  "memory-mcp-linux-arm64",
  "memory-mcp-darwin-amd64",
  "memory-mcp-darwin-arm64",
  "memory-mcp-windows-amd64.exe"
)
$BinName = "memory-mcp-windows-amd64.exe"
$Launcher = ".agents/mcp/memory/run.cmd"
$OtherLauncher = ".agents/mcp/memory/run.sh"

function Usage {
  @"
usage: agent-parity <command> [dir] [--purge]

  install   [dir]  install the memory server, register agent configs, wire
                   cross-agent skills, create the store
  uninstall [dir]  remove the server, registrations, and skill wiring; keeps
                   the memory store and your skills unless --purge is given
  update    [dir]  refresh the launcher, binary, and managed blocks
  status    [dir]  show what is installed, registered, and stored
  version   [dir]  print installed and latest release versions

[dir] is the target project and defaults to the current directory.

Bootstrap once with:
  irm https://raw.githubusercontent.com/libkim/agent-parity/main/install.ps1 | iex

After that, use:
  .\.agents\bin\agent-parity.cmd status
  .\.agents\bin\agent-parity.cmd update
"@ | Write-Error
  exit 2
}

if ($Command -in @("-h", "--help", "help")) { Usage }

foreach ($arg in $Rest) {
  if ($arg -eq "--purge") {
    $Purge = $true
  } elseif ($arg -in @("-h", "--help", "help")) {
    Usage
  } else {
    Usage
  }
}

if ($Target -eq "--purge") {
  $Target = "."
  $Purge = $true
}

if ($Command -notin @("install", "update", "uninstall", "status", "version")) {
  if ($PSBoundParameters.ContainsKey("Command") -and !$PSBoundParameters.ContainsKey("Target")) {
    $Target = $Command
    $Command = "install"
  } else {
    Usage
  }
}

if (!(Test-Path -LiteralPath $Target -PathType Container)) {
  throw "no such directory: $Target"
}
$Target = (Resolve-Path -LiteralPath $Target).Path
$Bin = Join-Path $Target ($ServerDir.Replace('/', '\') + "\dist\$BinName")

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

function Fetch-Text([string]$Rel) {
  $uri = "$Raw/$Rel"
  $r = Invoke-WebRequest -UseBasicParsing -Uri $uri
  return [string]$r.Content
}

function Download-File([string]$Url, [string]$Path) {
  Ensure-Parent $Path
  Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Path
}

function Install-ProjectCli {
  $d = Path-InTarget $ProjectCliDir
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  Write-Text (Join-Path $d "agent-parity.ps1") ((Fetch-Text "templates/project-agent-parity.ps1").TrimEnd("`r", "`n") + "`n")
  Write-Text (Join-Path $d "agent-parity.cmd") ((Fetch-Text "templates/project-agent-parity.cmd").TrimEnd("`r", "`n") + "`r`n")
  Write-Text (Join-Path $d "agent-parity") ((Fetch-Text "templates/project-agent-parity.sh").TrimEnd("`r", "`n") + "`n")
  Write-Output "cli: wrote $ProjectCliDir/agent-parity.cmd"
}

function Windows-Template([string]$Template) {
  $text = Fetch-Text $Template
  if ($Template -match 'templates/(claude|cursor|codex|antigravity)\.') {
    $text = $text.Replace($OtherLauncher, $Launcher)
  }
  return $text.TrimEnd("`r", "`n")
}

function For-EachConfig([string]$Fn) {
  & $Fn ".mcp.json"               "templates/claude.mcp.json"             $Launcher
  & $Fn ".cursor/mcp.json"        "templates/cursor.mcp.json"             $Launcher
  & $Fn ".codex/config.toml"      "templates/codex.config.toml"           $Launcher
  & $Fn ".agents/mcp_config.json" "templates/antigravity.mcp_config.json" $Launcher
  & $Fn "CLAUDE.md"               "templates/CLAUDE.md"                   "@AGENTS.md"
}

function Invoke-MemoryBin {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$BinArgs)
  & $Bin @BinArgs | Out-Null
  return $LASTEXITCODE
}

function Installed-Version {
  if (!(Test-Path -LiteralPath $Bin -PathType Leaf)) { return "missing" }
  try {
    $v = (& $Bin -version 2>$null)
    if ($LASTEXITCODE -eq 0 -and $v) { return [string]$v }
  } catch {}
  return "unknown (pre-versioning build)"
}

function Latest-Version {
  try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing
    if ($rel.tag_name) { return [string]$rel.tag_name }
  } catch {}
  return "unknown"
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

function Download-Server {
  $dest = Path-InTarget $ServerDir
  New-Item -ItemType Directory -Force -Path (Join-Path $dest "dist") | Out-Null
  Download-File "$Raw/run.sh" (Join-Path $dest "run.sh")
  Download-File "$Raw/run.cmd" (Join-Path $dest "run.cmd")
  Write-Output "downloading server binaries (all platforms) ..."
  foreach ($b in $AllBins) {
    Download-File "$Release/$b" (Join-Path $dest "dist\$b")
  }
}

function Reg-Config([string]$Rel, [string]$Template, [string]$Marker) {
  $t = Path-InTarget $Rel
  $c = Windows-Template $Template
  $existing = Read-Text $t
  if ($null -eq $existing) {
    Write-Text $t ($c + "`n")
    Write-Output "  wrote:      $Rel"
  } elseif ($existing.TrimEnd("`r", "`n") -eq $c) {
    Write-Output "  registered: $Rel (already)"
  } elseif ($existing.Contains($Marker)) {
    Write-Output "  registered: $Rel (already)"
  } elseif ($Marker -eq $Launcher -and $existing.Contains($OtherLauncher)) {
    Write-Text $t ($existing.Replace($OtherLauncher, $Launcher))
    Write-Output "  retargeted: $Rel (Unix launcher -> Windows launcher)"
  } elseif ($Marker -eq $Launcher) {
    $code = Invoke-MemoryBin "-has-memory-config" $t
    if ($code -eq 0) {
      Write-Output "  exists:     $Rel -- its memory entry points at a different server; replace it with:"
      $c -split "`n" | ForEach-Object { Write-Output "    | $_" }
    } else {
      $code = Invoke-MemoryBin "-merge-config" $t "-command" $Launcher
      if ($code -eq 0) {
        Write-Output "  merged:     $Rel (added memory server entry)"
      } else {
        Write-Output "  exists:     $Rel -- merge this in:"
        $c -split "`n" | ForEach-Object { Write-Output "    | $_" }
      }
    }
  } else {
    Write-Output "  exists:     $Rel -- merge this in:"
    $c -split "`n" | ForEach-Object { Write-Output "    | $_" }
  }
}

function Reg-CursorCli {
  $t = Path-InTarget $CursorCli
  $c = (Fetch-Text "templates/cursor.cli.json").TrimEnd("`r", "`n")
  $existing = Read-Text $t
  if ($null -eq $existing) {
    Write-Text $t ($c + "`n")
    Write-Output "  wrote:      $CursorCli"
  } elseif ($existing.TrimEnd("`r", "`n") -eq $c) {
    Write-Output "  registered: $CursorCli (already)"
  } else {
    Write-Output "  exists:     $CursorCli -- merge this in:"
    $c -split "`n" | ForEach-Object { Write-Output "    | $_" }
  }
}

function Unreg-CursorCli {
  $t = Path-InTarget $CursorCli
  $text = Read-Text $t
  if ($null -eq $text) { return }
  $c = (Fetch-Text "templates/cursor.cli.json").TrimEnd("`r", "`n")
  if ($text.TrimEnd("`r", "`n") -eq $c) {
    Remove-Item -LiteralPath $t -Force
    Write-Output "  removed:       $CursorCli"
  } else {
    Write-Output "  edit manually: $CursorCli -- remove our memory allowlist entry"
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

function Sync-GitIgnore {
  if (!(Test-GitRepo)) { return }
  Strip-GitIgnoreBlock
  $rules = New-Object System.Collections.Generic.List[string]
  foreach ($p in $Artifacts) {
    if ((Test-Path -LiteralPath (Path-InTarget $p)) -and (Test-Ignored $p)) {
      if (Test-Path -LiteralPath (Path-InTarget $p) -PathType Container) { $rules.Add("!/$p/") } else { $rules.Add("!/$p") }
    }
  }
  if ((Test-Path -LiteralPath (Path-InTarget $SyncScript)) -and !(Test-Ignored ".claude")) {
    $rules.Add("/.claude/")
  }
  if ($rules.Count -eq 0) { return }
  $gi = Path-InTarget ".gitignore"
  $existing = Read-Text $gi
  if ($null -eq $existing) { $existing = "" }
  if ($existing.Length -gt 0 -and !$existing.EndsWith("`n")) { $existing += "`n" }
  $block = $GitIgnoreBegin + "`n" + (($rules | ForEach-Object { $_ }) -join "`n") + "`n" + $GitIgnoreEnd + "`n"
  Write-Text $gi ($existing + $block)
  Write-Output ".gitignore: updated managed block:"
  $rules | ForEach-Object { Write-Output "  $_" }
}

function Adopt-ClaudeSkills {
  $claudeSkills = Path-InTarget ".claude/skills"
  if (!(Test-Path -LiteralPath $claudeSkills -PathType Container)) { return }
  New-Item -ItemType Directory -Force -Path (Path-InTarget ".agents/skills") | Out-Null
  Get-ChildItem -LiteralPath $claudeSkills -Directory | ForEach-Object {
    $name = $_.Name
    $dest = Path-InTarget ".agents/skills/$name"
    if (!(Test-Path -LiteralPath $dest)) {
      Move-Item -LiteralPath $_.FullName -Destination $dest
      Write-Output "  adopted:    .claude/skills/$name -> .agents/skills/$name (now shared by all agents)"
    } else {
      $conflict = Path-InTarget ".agents/skills/$name.from-claude"
      Move-Item -LiteralPath $_.FullName -Destination $conflict -Force
      Write-Output "  conflict:   .claude/skills/$name saved as .agents/skills/$name.from-claude, merge manually"
    }
  }
}

function Install-Skills {
  Write-Output "skills:"
  New-Item -ItemType Directory -Force -Path (Path-InTarget ".agents/skills") | Out-Null
  Adopt-ClaudeSkills
  if (!(Get-ChildItem -LiteralPath (Path-InTarget ".agents/skills") -Force | Select-Object -First 1)) {
    Write-Text (Path-InTarget ".agents/skills/.gitkeep") ""
  }
  $s = Path-InTarget $SyncScript
  if (!(Test-Path -LiteralPath $s)) {
    Write-Text $s ((Fetch-Text "templates/sync-claude.ps1").TrimEnd("`r", "`n") + "`n")
    Write-Output "  wrote:      $SyncScript"
  } else {
    Write-Output "  exists:     $SyncScript (kept as is)"
  }
  $hook = (Fetch-Text "templates/claude.settings.windows.json").TrimEnd("`r", "`n")
  $src = Path-InTarget $ClaudeSrc
  $tgt = Path-InTarget $ClaudeTgt
  $srcText = Read-Text $src
  if ($null -ne $srcText) {
    if ($srcText.Contains("sync-claude.ps1")) {
      Write-Output "  registered: $ClaudeSrc (hook already)"
    } else {
      Write-Output "  exists:     $ClaudeSrc -- merge this hook in:"
      $hook -split "`n" | ForEach-Object { Write-Output "    | $_" }
    }
  } elseif (Test-Path -LiteralPath $tgt) {
    Write-Output "  exists:     $ClaudeTgt -- move it to $ClaudeSrc and merge this hook in:"
    $hook -split "`n" | ForEach-Object { Write-Output "    | $_" }
  } else {
    Write-Text $src ($hook + "`n")
    Write-Output "  wrote:      $ClaudeSrc"
  }
  & powershell -NoProfile -ExecutionPolicy Bypass -File $s sync 2>&1 | ForEach-Object { Write-Output "  $_" }
}

function Uninstall-Skills {
  $s = Path-InTarget $SyncScript
  if (!(Test-Path -LiteralPath $s)) { return }
  $tpl = (Fetch-Text "templates/sync-claude.ps1").TrimEnd("`r", "`n")
  $cur = (Read-Text $s).TrimEnd("`r", "`n")
  if ($cur -ne $tpl) {
    Write-Output "skills: $SyncScript differs from the packaged one -- wiring left alone"
    return
  }
  $hook = (Fetch-Text "templates/claude.settings.windows.json").TrimEnd("`r", "`n")
  $src = Path-InTarget $ClaudeSrc
  $tgt = Path-InTarget $ClaudeTgt
  if ((Read-Text $tgt) -and ((Read-Text $tgt).TrimEnd("`r", "`n") -eq $hook)) { Remove-Item -LiteralPath $tgt -Force }
  if ((Read-Text $src) -and ((Read-Text $src).TrimEnd("`r", "`n") -eq $hook)) { Remove-Item -LiteralPath $src -Force }
  Remove-Item -LiteralPath $s -Force
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
    $n = @(Get-ChildItem -LiteralPath $skillDir -Directory).Count
  }
  Write-Output "skills: $n in .agents/skills; sync script present"
  $src = Read-Text (Path-InTarget $ClaudeSrc)
  $tgt = Read-Text (Path-InTarget $ClaudeTgt)
  if ($src -and $src.Contains("sync-claude.ps1")) { Write-Output "  hook: registered ($ClaudeSrc)" }
  elseif ($tgt -and $tgt.Contains("sync-claude.ps1")) { Write-Output "  hook: registered ($ClaudeTgt)" }
  else { Write-Output "  hook: missing -- Claude Code will not auto-sync skills" }
}

function Status-CodexMcp {
  if (!(Get-Command codex -ErrorAction SilentlyContinue)) {
    Write-Output "codex mcp: codex CLI not found"
    return
  }
  Push-Location -LiteralPath $Target
  try {
    $out = & codex mcp get memory 2>&1
    $code = $LASTEXITCODE
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

function Sync-AgentsBlock {
  $ag = Path-InTarget "AGENTS.md"
  $snip = (Fetch-Text "templates/AGENTS.snippet.md").TrimEnd("`r", "`n")
  $text = Read-Text $ag
  if ($null -ne $text -and $text.Contains($MarkBegin) -and $text.Contains($MarkEnd)) {
    $pattern = [regex]::Escape($MarkBegin) + '(?s).*?' + [regex]::Escape($MarkEnd)
    $next = [regex]::Replace($text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $snip })
    if ($next -eq $text) { Write-Output "AGENTS.md: memory block up to date" }
    else { Write-Text $ag $next; Write-Output "AGENTS.md: refreshed memory instruction block" }
  } else {
    if ($null -ne $text -and $text -match 'memory_(recent|add|search|get)') {
      Write-Output "AGENTS.md: note -- existing text already mentions the memory tools; check it against the appended block for duplication"
    }
    if ($null -eq $text) { $text = "" }
    Write-Text $ag ($text.TrimEnd("`r", "`n") + "`n`n" + $snip + "`n")
    Write-Output "AGENTS.md: appended memory instruction block"
  }
}

function Cmd-Install {
  New-Item -ItemType Directory -Force -Path (Path-InTarget $ServerDir), (Path-InTarget $StoreDir) | Out-Null
  Download-Server
  Install-ProjectCli
  Write-Output "configs:"
  For-EachConfig "Reg-Config"
  Reg-CursorCli
  Install-Skills
  Sync-AgentsBlock
  Sync-GitIgnore
  Warn-Parity
  Write-Output ""
  Write-Output "installed $(Installed-Version) -> $(Path-InTarget $ServerDir)"
  Write-Output "memory store: $(Path-InTarget $StoreDir)"
  Write-Output "start a new agent session (or restart) to load the memory server."
}

function Cmd-Update {
  if (!(Test-Path -LiteralPath (Path-InTarget $ServerDir) -PathType Container)) { throw "nothing to update: $(Path-InTarget $ServerDir) not found -- run install first" }
  $old = Installed-Version
  Download-Server
  Install-ProjectCli
  Write-Output "configs:"
  For-EachConfig "Reg-Config"
  Reg-CursorCli
  Sync-AgentsBlock
  Sync-GitIgnore
  $s = Path-InTarget $SyncScript
  if (Test-Path -LiteralPath $s) { & powershell -NoProfile -ExecutionPolicy Bypass -File $s sync 2>&1 | ForEach-Object { Write-Output "  $_" } }
  $new = Installed-Version
  if ($old -eq $new) { Write-Output "already up to date: $new" } else { Write-Output "updated: $old -> $new" }
}

function Unreg-Config([string]$Rel, [string]$Template, [string]$Marker) {
  $t = Path-InTarget $Rel
  $text = Read-Text $t
  if ($null -eq $text) { return }
  $c = Windows-Template $Template
  if ($text.TrimEnd("`r", "`n") -eq $c) {
    Remove-Item -LiteralPath $t -Force
    Write-Output "  removed:       $Rel"
  } elseif ($Rel -eq "CLAUDE.md") {
    return
  } elseif ($Marker -eq $Launcher -and $text.Contains($Marker)) {
    $code = Invoke-MemoryBin "-unmerge-config" $t
    if ($code -eq 0) { Write-Output "  unmerged:      $Rel (removed memory server entry, kept the rest)" }
    else { Write-Output "  edit manually: $Rel -- remove its memory-mcp entry ($Marker)" }
  } elseif ($text.Contains($Marker)) {
    Write-Output "  edit manually: $Rel -- remove its memory-mcp entry ($Marker)"
  }
}

function Cmd-Uninstall {
  Write-Output "configs:"
  For-EachConfig "Unreg-Config"
  Unreg-CursorCli
  foreach ($p in @("$ProjectCliDir/agent-parity", "$ProjectCliDir/agent-parity.cmd", "$ProjectCliDir/agent-parity.ps1")) {
    $full = Path-InTarget $p
    if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Force }
  }
  $cliDir = Path-InTarget $ProjectCliDir
  if (Test-Path -LiteralPath $cliDir) {
    try { Remove-Item -LiteralPath $cliDir -Force -ErrorAction Stop } catch {}
  }
  $server = Path-InTarget $ServerDir
  if (Test-Path -LiteralPath $server) { Remove-Item -LiteralPath $server -Recurse -Force }
  Write-Output "removed: $ServerDir"
  Uninstall-Skills
  $ag = Path-InTarget "AGENTS.md"
  $text = Read-Text $ag
  if ($text -and $text.Contains($MarkBegin) -and $text.Contains($MarkEnd)) {
    $pattern = [regex]::Escape($MarkBegin) + '(?s).*?' + [regex]::Escape($MarkEnd) + "\r?\n?"
    Write-Text $ag ([regex]::Replace($text, $pattern, ""))
    Write-Output "AGENTS.md: removed memory instruction block"
  }
  Strip-GitIgnoreBlock
  if ($Purge) {
    if (Test-Path -LiteralPath (Path-InTarget $StoreDir)) { Remove-Item -LiteralPath (Path-InTarget $StoreDir) -Recurse -Force }
    Write-Output "memory store: deleted ($(Path-InTarget $StoreDir))"
  } else {
    Write-Output "memory store: kept at $(Path-InTarget $StoreDir) (pass --purge to delete it)"
  }
}

function Status-Config([string]$Rel, [string]$Template, [string]$Marker) {
  $t = Path-InTarget $Rel
  $text = Read-Text $t
  if ($null -eq $text) { Write-Output "  missing:        $Rel" }
  elseif ($text.Contains($Marker)) { Write-Output "  registered:     $Rel" }
  elseif ($Marker -eq $Launcher -and $text.Contains($OtherLauncher)) { Write-Output "  registered for Unix: $Rel (run install/update here to retarget to run.cmd)" }
  elseif ($Marker -eq $Launcher) {
    $code = Invoke-MemoryBin "-has-memory-config" $t
    if ($code -eq 0) { Write-Output "  points elsewhere: $Rel (memory entry not using $ServerDir)" }
    else { Write-Output "  not registered: $Rel" }
  } else { Write-Output "  not registered: $Rel" }
}

function Status-AgentConfig([string]$Label, [string]$Rel, [string]$Marker) {
  $t = Path-InTarget $Rel
  $text = Read-Text $t
  if ($null -eq $text) { Write-Output "  ${Label}: config missing ($Rel)" }
  elseif ($text.Contains($Marker)) { Write-Output "  ${Label}: registered ($Rel)" }
  elseif ($Marker -eq $Launcher -and $text.Contains($OtherLauncher)) { Write-Output "  ${Label}: registered for Unix ($Rel; run install/update here to retarget to run.cmd)" }
  elseif ($Marker -eq $Launcher) {
    $code = Invoke-MemoryBin "-has-memory-config" $t
    if ($code -eq 0) { Write-Output "  ${Label}: points elsewhere ($Rel has a memory entry not using $ServerDir)" }
    else { Write-Output "  ${Label}: not registered ($Rel)" }
  } else { Write-Output "  ${Label}: not registered ($Rel)" }
}

function Status-McpRegistrations {
  Write-Output "mcp registrations:"
  Status-AgentConfig "Claude Code"     ".mcp.json"               $Launcher
  Status-AgentConfig "Cursor"          ".cursor/mcp.json"        $Launcher
  Status-AgentConfig "Codex"           ".codex/config.toml"      $Launcher
  Status-AgentConfig "Antigravity CLI" ".agents/mcp_config.json" $Launcher
  Status-AgentConfig "Claude wrapper"  "CLAUDE.md"               "@AGENTS.md"
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

function Cmd-Status {
  Write-Output "target: $Target"
  $installed = Installed-Version
  if ($installed -ne "missing") { Write-Output "server: $installed ($ServerDir/dist/$BinName)" } else { Write-Output "server: missing (expected $ServerDir/dist/$BinName)" }
  if (Test-Path -LiteralPath (Path-InTarget $Launcher) -PathType Leaf) { Write-Output "launcher: ok" } else { Write-Output "launcher: missing" }
  $latest = Latest-Version
  Write-Output "latest release: $latest"
  Show-UpdateNotice $installed $latest
  Status-McpRegistrations
  Status-AgentDiagnostics
  Status-Skills
  $cliText = Read-Text (Path-InTarget $CursorCli)
  $cliTpl = (Fetch-Text "templates/cursor.cli.json").TrimEnd("`r", "`n")
  if ($null -eq $cliText) { Write-Output "cursor cli: allowlist missing ($CursorCli)" }
  elseif ($cliText.TrimEnd("`r", "`n") -eq $cliTpl) { Write-Output "cursor cli: memory allowlist present ($CursorCli)" }
  else { Write-Output "cursor cli: $CursorCli exists but is not ours (memory allowlist not confirmed)" }
  $agText = Read-Text (Path-InTarget "AGENTS.md")
  if ($agText -and ($agText.Contains($MarkBegin) -or $agText.Contains("memory MCP server"))) { Write-Output "AGENTS.md: memory block present" } else { Write-Output "AGENTS.md: memory block missing" }
  $store = Path-InTarget $StoreDir
  if (Test-Path -LiteralPath $store -PathType Container) {
    $n = @(Get-ChildItem -LiteralPath $store -Filter "*.md" -File).Count
    Write-Output "memory store: $n entries ($store)"
  } else { Write-Output "memory store: missing ($store)" }
  if (Test-GitRepo) {
    $ignored = @($Artifacts | Where-Object { (Test-Path -LiteralPath (Path-InTarget $_)) -and (Test-Ignored $_) })
    if ($ignored.Count -gt 0) { Write-Output "git: IGNORED and will not sync via git: $($ignored -join ' ') (run install or update to fix)" } else { Write-Output "git: all artifacts tracked" }
  }
  Warn-Parity
}

function Cmd-Version {
  $installed = Installed-Version
  $latest = Latest-Version
  Write-Output "installed: $installed"
  Write-Output "latest:    $latest"
  Show-UpdateNotice $installed $latest
}

switch ($Command) {
  "install" { Cmd-Install }
  "update" { Cmd-Update }
  "uninstall" { Cmd-Uninstall }
  "status" { Cmd-Status }
  "version" { Cmd-Version }
}
