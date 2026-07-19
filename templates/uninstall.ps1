param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CliArgs
)

$ErrorActionPreference = "Stop"
$Purge = $false
if ($CliArgs.Count -gt 0 -and $CliArgs[0] -eq "uninstall") { $CliArgs = @($CliArgs | Select-Object -Skip 1) }
foreach ($arg in $CliArgs) {
  if ($arg -eq "--purge") { $Purge = $true } else { throw "usage: agent-parity uninstall [--purge]" }
}
$Target = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
. (Join-Path $PSScriptRoot "common.ps1") -Target $Target

Write-Output "configs:"
For-EachConfig "Unreg-Config"
Unreg-CursorCli
Unreg-AgentHooks
Uninstall-Skills
$server = Path-InTarget $ServerDir
if (Test-Path -LiteralPath $server) { Remove-Item -LiteralPath $server -Recurse -Force }
Write-Output "removed: $ServerDir"
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
foreach ($name in @("common.ps1", "status.ps1", "version.ps1", "uninstall.ps1", "sync-claude.ps1", "self-heal.ps1", "common.sh", "status.sh", "version.sh", "uninstall.sh", "sync-claude.sh", "self-heal.sh")) {
  Remove-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Force -ErrorAction SilentlyContinue
}
