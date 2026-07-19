param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CliArgs
)

$ErrorActionPreference = "Stop"
if ($CliArgs.Count -gt 0 -and $CliArgs[0] -eq "status") { $CliArgs = @($CliArgs | Select-Object -Skip 1) }
if ($CliArgs.Count -gt 0) { throw "usage: agent-parity status" }
$Target = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
. (Join-Path $PSScriptRoot "common.ps1") -Target $Target

Write-Output "target: $Target"
$installed = Installed-Version
if ($installed -ne "missing" -and (Test-Path -LiteralPath (Path-InTarget "$ServerDir/RELEASE") -PathType Leaf)) { Write-Output "server: $installed (shared cache, downloaded on demand)" } else { $installed = "missing"; Write-Output "server: missing (expected $ServerDir/VERSION and RELEASE)" }
if (Test-Path -LiteralPath (Path-InTarget $Launcher) -PathType Leaf) { Write-Output "launcher: ok" } else { Write-Output "launcher: missing" }
$latest = Latest-Version
Write-Output "latest release: $latest"
Show-UpdateNotice $installed $latest
Status-McpRegistrations
Status-ClaudeWrapper
Status-AgentHooks
Status-AgentDiagnostics
Status-Skills
$cliText = Read-Text (Path-InTarget $CursorCli)
if ($null -eq $cliText) { Write-Output "cursor cli: allowlist missing ($CursorCli)" }
elseif (!(Test-Path -LiteralPath $ConfigEditor -PathType Leaf)) { Write-Output "cursor cli: unknown (local config editor missing)" }
else {
  & $ConfigEditor has-cursor-cli (Path-InTarget $CursorCli) 2>$null
  if ($LASTEXITCODE -eq 0) { Write-Output "cursor cli: memory allowlist present ($CursorCli)" }
  else { Write-Output "cursor cli: $CursorCli exists but is not ours (memory allowlist not confirmed)" }
}
$agText = Read-Text (Path-InTarget "AGENTS.md")
$agState = Get-ManagedBlockState $agText $MarkBegin $MarkEnd
if ($agState -eq "valid") { Write-Output "AGENTS.md: memory block present" }
elseif ($agState -eq "absent") { Write-Output "AGENTS.md: memory block missing" }
else { Write-Output "AGENTS.md: agent-parity markers are incomplete, duplicated, or out of order; repair them manually" }
$gitIgnoreState = Get-ManagedBlockState (Read-Text (Path-InTarget ".gitignore")) $GitIgnoreBegin $GitIgnoreEnd
if ($gitIgnoreState -eq "invalid") { Write-Output ".gitignore: agent-parity markers are incomplete, duplicated, or out of order; repair them manually" }
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
