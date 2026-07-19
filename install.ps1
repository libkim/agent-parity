# agent-parity: native Windows installer.
[CmdletBinding()]
param(
  [Parameter(Position = 0)] [string]$Command = "install",
  [Parameter(Position = 1)] [string]$Target = ".",
  [Parameter(ValueFromRemainingArguments = $true)] [string[]]$Rest
)

$ErrorActionPreference = "Stop"

function Usage {
  Write-Error "usage: install.ps1 [install] [dir]"
  exit 2
}

if ($Command -in @("-h", "--help", "help")) { Usage }
if ($Rest.Count -gt 0) { Usage }
if ($Command -ne "install") {
  if ($PSBoundParameters.ContainsKey("Command") -and !$PSBoundParameters.ContainsKey("Target")) { $Target=$Command } else { Usage }
}
$ErrorActionPreference = "Stop"

$Repo = "libkim/agent-parity"
$Raw = $env:AGENT_PARITY_RAW
$Release = $env:AGENT_PARITY_RELEASE
$Version = $env:AGENT_PARITY_VERSION
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

if (!(Test-Path -LiteralPath $Target -PathType Container)) { throw "no such directory: $Target" }
$Target=(Resolve-Path -LiteralPath $Target).Path
$MemoryRun=Join-Path $Target ($ServerDir.Replace('/','\') + "\run.cmd")

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

function Fetch-Text([string]$Rel) {
  $uri = "$Raw/$Rel"
  $r = Invoke-WebRequest -UseBasicParsing -Uri $uri
  if ($r.Content -is [byte[]]) { return [System.Text.Encoding]::UTF8.GetString($r.Content) }
  return [string]$r.Content
}

function Download-File([string]$Url, [string]$Path) {
  Ensure-Parent $Path
  $temp = New-StagingFile $Path
  try {
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $temp
    Move-Item -LiteralPath $temp -Destination $Path -Force
    $temp = $null
  } finally {
    if ($temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
  }
}

function Install-ProjectCli {
  $d = Path-InTarget $ProjectCliDir
  $s = Path-InTarget ".agents/scripts"
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  New-Item -ItemType Directory -Force -Path $s | Out-Null
  foreach ($name in @("common.ps1", "status.ps1", "version.ps1", "uninstall.ps1", "sync-claude.ps1", "self-heal.ps1")) {
    Write-Text (Join-Path $s $name) ((Fetch-Text "templates/$name").TrimEnd("`r", "`n") + "`n")
  }
  foreach ($name in @("common.sh", "status.sh", "version.sh", "uninstall.sh", "sync-claude.sh", "self-heal.sh")) {
    Write-Text (Join-Path $s $name) ((Fetch-Text "templates/$name").TrimEnd("`r", "`n") + "`n")
  }
  Remove-Item -LiteralPath (Join-Path $d "agent-parity.ps1") -Force -ErrorAction SilentlyContinue
  Write-Text (Join-Path $d "agent-parity.cmd") ((Fetch-Text "templates/project-agent-parity.cmd").TrimEnd("`r", "`n") + "`r`n")
  Write-Text (Join-Path $d "agent-parity") ((Fetch-Text "templates/project-agent-parity.sh").TrimEnd("`r", "`n") + "`n")
  Write-Output "cli: wrote project launchers and local command scripts"
}

function Install-ConfigEditor {
  if ($env:PROCESSOR_ARCHITECTURE -ne "AMD64" -and $env:PROCESSOR_ARCHITEW6432 -ne "AMD64") { throw "unsupported Windows architecture: $env:PROCESSOR_ARCHITECTURE" }
  $asset = "agent-parity-config-windows-amd64.exe"
  $cacheRoot = if ($env:AGENT_PARITY_CACHE) { $env:AGENT_PARITY_CACHE } elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "agent-parity\cache" } else { Join-Path $env:USERPROFILE ".cache\agent-parity" }
  $configDir = Join-Path $cacheRoot "config\$Version"
  $dest = Join-Path $configDir $asset
  New-Item -ItemType Directory -Force -Path $configDir | Out-Null
  $stage = Join-Path $configDir (".agent-parity-config." + [Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $stage | Out-Null
  try {
    $checksums = Join-Path $stage "checksums.txt"
    $binary = Join-Path $stage $asset
    Download-File "$($Release.TrimEnd('/'))/checksums.txt" $checksums
    Download-File "$($Release.TrimEnd('/'))/$asset" $binary
    $line = Get-Content -LiteralPath $checksums | Where-Object { $_ -match "\s\*?$([regex]::Escape($asset))$" } | Select-Object -First 1
    if (!$line) { throw "checksum missing for $asset" }
    $expected = ($line -split '\s+')[0].ToLowerInvariant()
    $actual = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "checksum mismatch for $asset" }
    Move-Item -LiteralPath $binary -Destination $dest -Force
  } finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Output "cli: installed local JSON/TOML config editor"
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
  & $MemoryRun @BinArgs | Out-Null
  return $LASTEXITCODE
}

function Installed-Version {
  $versionFile = Path-InTarget "$ServerDir/VERSION"
  if (!(Test-Path -LiteralPath $versionFile -PathType Leaf)) { return "missing" }
  return (Read-Text $versionFile).Trim()
}

function Latest-Version {
  try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing
    if ($rel.tag_name) { return [string]$rel.tag_name }
  } catch {}
  return "unknown"
}

# Pin scripts, templates, and binaries to one release tag. The supported
# bootstrap passes both URLs explicitly; direct invocation resolves them here.
# There is deliberately no main fallback.
if ((-not $Raw) -or (-not $Release)) {
  $pinnedTag = Latest-Version
  if ($pinnedTag -notmatch '^v') { throw "could not resolve latest agent-parity release" }
  if (-not $Raw)     { $Raw = "https://raw.githubusercontent.com/$Repo/$pinnedTag" }
  if (-not $Release) { $Release = "https://github.com/$Repo/releases/download/$pinnedTag" }
}

if (-not $Version) {
  $rawLeaf = $Raw.TrimEnd('/').Split('/')[-1]
  $Version = if ($rawLeaf -match '^v') { $rawLeaf } else { "dev" }
}
if ($Version -notmatch '^(v[0-9A-Za-z._-]+|dev)$') { throw "invalid agent-parity release version: $Version" }


function Install-Server {
  $dest = Path-InTarget $ServerDir
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  $stage = Join-Path $dest (".agent-parity-runtime." + [Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $stage | Out-Null
  try {
    Download-File "$Raw/run.sh" (Join-Path $stage "run.sh")
    Download-File "$Raw/run.cmd" (Join-Path $stage "run.cmd")
    Write-Text (Join-Path $stage "VERSION") ($Version + "`n")
    Write-Text (Join-Path $stage "RELEASE") ($Release.TrimEnd('/') + "`n")
    & (Join-Path $stage "run.cmd") -version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not prepare the shared memory-mcp cache" }
    foreach ($name in @("run.sh", "run.cmd", "VERSION", "RELEASE")) {
      Move-Item -LiteralPath (Join-Path $stage $name) -Destination (Join-Path $dest $name) -Force
    }
  } finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
  }
  # Remove a legacy vendored copy only after the verified cache and launchers
  # are ready.
  Remove-Item -LiteralPath (Join-Path $dest "dist") -Recurse -Force -ErrorAction SilentlyContinue
  Write-Output "server: pinned $Version (current platform binary verified in the shared cache)"
}

function Reg-Config([string]$Rel, [string]$Template, [string]$Marker) {
  $t = Path-InTarget $Rel
  $c = Windows-Template $Template
  $existing = Read-Text $t
  if ($null -eq $existing) {
    Write-Text $t ($c + "`n")
    Write-Output "  wrote:      $Rel"
  } elseif ($Marker -eq $Launcher) {
    $cacheRoot = if ($env:AGENT_PARITY_CACHE) { $env:AGENT_PARITY_CACHE } elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "agent-parity\cache" } else { Join-Path $env:USERPROFILE ".cache\agent-parity" }
    $editor = Join-Path $cacheRoot "config\$Version\agent-parity-config-windows-amd64.exe"
    $current = & $editor command $t 2>$null
    $code = $LASTEXITCODE
    if ($code -eq 0) {
      $result = & $editor ensure $t $Launcher
      if ($LASTEXITCODE -ne 0) { throw "could not safely update $Rel" }
      if (($result | Out-String).Trim() -eq "changed") {
        Write-Output "  retargeted: $Rel (launcher -> Windows launcher)"
      } elseif (($current | Out-String).Trim() -eq $Launcher) {
        Write-Output "  registered: $Rel (already)"
      } else {
        Write-Output "  exists:     $Rel -- its memory entry points at a different server; replace it with:"
        $c -split "`n" | ForEach-Object { Write-Output "    | $_" }
      }
    } elseif ($code -eq 1) {
      & $editor ensure $t $Launcher | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "could not safely merge $Rel" }
      Write-Output "  merged:     $Rel (added memory server entry)"
    } else {
      Write-Output "  exists:     $Rel -- invalid JSON/TOML; merge this in:"
      $c -split "`n" | ForEach-Object { Write-Output "    | $_" }
    }
  } elseif ($existing.TrimEnd("`r", "`n") -eq $c) {
    Write-Output "  registered: $Rel (already)"
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

function Reg-AgentHooks {
  foreach ($entry in @(
    @{ Kind = "claude"; Path = $ClaudeSrc },
    @{ Kind = "claude"; Path = $ClaudeTgt },
    @{ Kind = "codex"; Path = ".codex/hooks.json" },
    @{ Kind = "cursor"; Path = ".cursor/hooks.json" },
    @{ Kind = "antigravity"; Path = ".agents/hooks.json" }
  )) {
    $kind = $entry.Kind
    $path = $entry.Path
    if ((Invoke-MemoryBin "-merge-agent-hook" (Path-InTarget $path) "-hook-kind" $kind) -ne 0) {
      throw "could not register $kind self-heal hook"
    }
  }
  Write-Output "  hooks:      Claude, Codex, Cursor, Antigravity self-heal registered"
  Write-Output "  note:       Codex requires review/trust for the project hook before it runs"
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
  # Legacy installs may still have a vendored dist directory. Keep it out of
  # Git even if an interrupted migration leaves files behind.
  $rules.Add("/.agents/mcp/memory/dist/")
  foreach ($p in $Artifacts) {
    if ((Test-Path -LiteralPath (Path-InTarget $p)) -and (Test-Ignored $p)) {
      if (Test-Path -LiteralPath (Path-InTarget $p) -PathType Container) { $rules.Add("!/$p/") } else { $rules.Add("!/$p") }
    }
  }
  # Keep .claude/settings.json tracked so a fresh pull already carries the hook
  # and self-syncs (no manual first-run bootstrap); ignore the generated copies.
  # Git can't re-include under a fully ignored dir, so ignore .claude/* and
  # un-ignore settings.json.
  if ((Test-Path -LiteralPath (Path-InTarget $SyncScript)) -and !(Test-Ignored ".claude/skills")) {
    $rules.Add("/.claude/*")
    $rules.Add("!/.claude/settings.json")
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

function Adopt-AgentSkills {
  New-Item -ItemType Directory -Force -Path (Path-InTarget ".agents/skills") | Out-Null
  foreach ($pair in @(@(".claude/skills", "claude"), @(".codex/skills", "codex"), @(".cursor/skills", "cursor"))) {
    $dir = $pair[0]; $label = $pair[1]
    $src = Path-InTarget $dir
    if (!(Test-Path -LiteralPath $src -PathType Container)) { continue }
    Get-ChildItem -LiteralPath $src -Directory | ForEach-Object {
      $name = $_.Name
      if ($name -eq "agent-parity") { return }
      $dest = Path-InTarget ".agents/skills/$name"
      if (!(Test-Path -LiteralPath $dest)) {
        Move-Item -LiteralPath $_.FullName -Destination $dest
        Write-Output "  adopted:    $dir/$name -> .agents/skills/$name (now shared by all agents)"
      } else {
        $conflict = Path-InTarget ".agents/skills/$name.from-$label"
        Move-Item -LiteralPath $_.FullName -Destination $conflict -Force
        Write-Output "  conflict:   $dir/$name saved as .agents/skills/$name.from-$label, merge manually"
      }
    }
  }
}

function Install-Skills {
  Write-Output "skills:"
  New-Item -ItemType Directory -Force -Path (Path-InTarget ".agents/skills") | Out-Null
  Adopt-AgentSkills
  # The agent-parity skill lets any agent run the management commands without the
  # user typing OS-specific paths. It is a generated shim we own outright (like
  # run.cmd), so overwrite it every run to keep it current.
  $msk = Path-InTarget ".agents/skills/agent-parity"
  New-Item -ItemType Directory -Force -Path $msk | Out-Null
  Write-Text (Join-Path $msk "SKILL.md") ((Fetch-Text "templates/agent-parity.skill.md").TrimEnd("`r", "`n") + "`n")
  Write-Output "  wrote:      .agents/skills/agent-parity/SKILL.md"
  if (!(Get-ChildItem -LiteralPath (Path-InTarget ".agents/skills") -Force | Select-Object -First 1)) {
    Write-Text (Path-InTarget ".agents/skills/.gitkeep") ""
  }
  # sync-claude.ps1 is a generated shim we own outright (like run.cmd), so
  # overwrite it every run to keep it current -- user skills live in
  # .agents/skills, never here.
  $s = Path-InTarget $SyncScript
  Write-Text $s ((Fetch-Text "templates/sync-claude.ps1").TrimEnd("`r", "`n") + "`n")
  Write-Output "  wrote:      $SyncScript"
  # Merge our keys into the settings source, preserving any the user set. If only
  # the generated .claude copy exists, seed the source from it first so nothing
  # there is lost when sync regenerates the copy.
  $src = Path-InTarget $ClaudeSrc
  $tgt = Path-InTarget $ClaudeTgt
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $src) | Out-Null
  if (!(Test-Path -LiteralPath $src) -and (Test-Path -LiteralPath $tgt)) {
    Copy-Item -LiteralPath $tgt -Destination $src -Force
    Write-Output "  migrated:   $ClaudeTgt -> $ClaudeSrc"
  }
  if ((Invoke-MemoryBin "-merge-claude-settings" $src "-hook-command" $ClaudeHook) -eq 0) {
    Write-Output "  merged:     $ClaudeSrc (memory keys + sync hook)"
  } else {
    Write-Output "  warn:       could not merge $ClaudeSrc"
  }
  & powershell -NoProfile -ExecutionPolicy Bypass -File $s sync 2>&1 | ForEach-Object { Write-Output "  $_" }
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

function Warn-Parity {
  foreach ($p in $ParityBreakers) {
    if (Test-Path -LiteralPath (Path-InTarget $p.File)) {
      Write-Output "parity: $($p.File) exists -- only $($p.Who) reads it, so agents diverge; fold it into AGENTS.md"
    }
  }
}


function Cmd-Install {
  New-Item -ItemType Directory -Force -Path (Path-InTarget $ServerDir), (Path-InTarget $StoreDir) | Out-Null
  Install-Server
  Install-ProjectCli
  Install-ConfigEditor
  Write-Output "configs:"
  For-EachConfig "Reg-Config"
  Reg-CursorCli
  Install-Skills
  Reg-AgentHooks
  Sync-AgentsBlock
  Sync-GitIgnore
  Warn-Parity
  Write-Output ""
  Write-Output "installed $(Installed-Version) -> $(Path-InTarget $ServerDir)"
  Write-Output "memory store: $(Path-InTarget $StoreDir)"
  Write-Output "start a new agent session (or restart) to load the memory server."
}


Cmd-Install
