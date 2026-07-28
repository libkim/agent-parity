param(
  [Parameter(Position = 0)]
  [string]$Command = ""
)

$ErrorActionPreference = "Stop"

$RootDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$SkillsSource = Join-Path $RootDir ".agents\skills"
$SkillsTarget = Join-Path $RootDir ".claude\skills"
$SettingsSource = Join-Path $RootDir ".agents\claude\settings.json"
$SettingsTarget = Join-Path $RootDir ".claude\settings.json"

function Usage {
  @"
Usage: .agents\scripts\sync-claude.ps1 <check|sync|clean>

Materialize Claude Code artifacts from the synced .agents source.
  check  Report whether .claude matches .agents (skills + settings).
  sync   Recreate .claude\skills and .claude\settings.json from .agents.
  clean  Remove generated .claude\skills and .claude\settings.json.

Note: .claude\settings.local.json (machine-local) is never touched.
"@
}

function Require-SkillsSource {
  New-Item -ItemType Directory -Force -Path $SkillsSource | Out-Null
}

function Test-DirectorySame([string]$Left, [string]$Right) {
  if (!(Test-Path -LiteralPath $Left -PathType Container) -or !(Test-Path -LiteralPath $Right -PathType Container)) {
    return $false
  }
  $leftFiles = Get-ChildItem -LiteralPath $Left -Recurse -File | Sort-Object FullName
  $rightFiles = Get-ChildItem -LiteralPath $Right -Recurse -File | Sort-Object FullName
  if ($leftFiles.Count -ne $rightFiles.Count) { return $false }
  for ($i = 0; $i -lt $leftFiles.Count; $i++) {
    $lrel = $leftFiles[$i].FullName.Substring($Left.Length).TrimStart('\', '/')
    $rrel = $rightFiles[$i].FullName.Substring($Right.Length).TrimStart('\', '/')
    if ($lrel -ne $rrel) { return $false }
    if ((Get-FileHash -LiteralPath $leftFiles[$i].FullName).Hash -ne (Get-FileHash -LiteralPath $rightFiles[$i].FullName).Hash) {
      return $false
    }
  }
  return $true
}

function Check {
  Require-SkillsSource
  $status = 0
  if (!(Test-Path -LiteralPath $SkillsTarget -PathType Container)) {
    Write-Output "skills:   missing .claude\skills"
    $status = 1
  } elseif (Test-DirectorySame $SkillsSource $SkillsTarget) {
    Write-Output "skills:   ok"
  } else {
    Write-Output "skills:   stale"
    $status = 1
  }

  if (!(Test-Path -LiteralPath $SettingsSource -PathType Leaf)) {
    Write-Output "settings: no source (.agents\claude\settings.json) -- skipped"
  } elseif (!(Test-Path -LiteralPath $SettingsTarget -PathType Leaf)) {
    Write-Output "settings: missing .claude\settings.json"
    $status = 1
  } elseif ((Get-FileHash -LiteralPath $SettingsSource).Hash -eq (Get-FileHash -LiteralPath $SettingsTarget).Hash) {
    Write-Output "settings: ok"
  } else {
    Write-Output "settings: stale"
    $status = 1
  }
  exit $status
}

function Sync {
  Require-SkillsSource
  New-Item -ItemType Directory -Force -Path (Join-Path $RootDir ".claude") | Out-Null
  if (Test-Path -LiteralPath $SkillsTarget) { Remove-Item -LiteralPath $SkillsTarget -Recurse -Force }
  Copy-Item -LiteralPath $SkillsSource -Destination $SkillsTarget -Recurse -Force
  Write-Output "synced:   .claude\skills recreated from .agents\skills"
  if (Test-Path -LiteralPath $SettingsSource -PathType Leaf) {
    Copy-Item -LiteralPath $SettingsSource -Destination $SettingsTarget -Force
    Write-Output "synced:   .claude\settings.json recreated from .agents\claude\settings.json"
  } else {
    Write-Output "settings: no source -- skipped"
  }
}

function Clean {
  if (Test-Path -LiteralPath $SkillsTarget) { Remove-Item -LiteralPath $SkillsTarget -Recurse -Force }
  if (Test-Path -LiteralPath $SettingsTarget) { Remove-Item -LiteralPath $SettingsTarget -Force }
  Write-Output "cleaned:  .claude\skills and .claude\settings.json removed"
}

switch ($Command) {
  "check" { Check }
  "sync" { Sync }
  "clean" { Clean }
  { $_ -in "", "-h", "--help", "help" } { Usage }
  default { Usage; exit 2 }
}
