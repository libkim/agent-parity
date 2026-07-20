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
Require-LocalConfigEditor

Write-Output "configs:"
For-EachMcpConfig "Unreg-McpConfig"
Unreg-CursorCli
Unreg-ClaudeWrapper
Unreg-AgentHooks
Uninstall-Skills
$server = Path-InTarget $ServerDir
if (Test-Path -LiteralPath $server) { Remove-Item -LiteralPath $server -Recurse -Force }
Write-Output "removed: $ServerDir"
$ag = Path-InTarget "AGENTS.md"
$text = Read-Text $ag
$agState = Get-ManagedBlockState $text $MarkBegin $MarkEnd
if ($agState -eq "valid") {
  $pattern = [regex]::Escape($MarkBegin) + '(?s).*?' + [regex]::Escape($MarkEnd) + "\r?\n?"
  Write-Text $ag ([regex]::Replace($text, $pattern, ""))
  Write-Output "AGENTS.md: removed memory instruction block"
} elseif ($agState -eq "invalid") {
  Write-Output "AGENTS.md: agent-parity markers are incomplete, duplicated, or out of order; file left unchanged -- repair the markers manually"
} elseif ($text -and $text.Contains("memory MCP server")) {
  Write-Output "AGENTS.md: has a memory block without markers -- remove it manually"
}
$gaText = Read-Text (Path-InTarget ".gitattributes")
$gaState = Get-ManagedBlockState $gaText $GitIgnoreBegin $GitIgnoreEnd
if ($gaState -eq "valid") {
  Strip-GitAttributesBlock
  $gaPath = Path-InTarget ".gitattributes"
  if ((Read-Text $gaPath) -match '^\s*$') { Remove-Item -LiteralPath $gaPath -Force -ErrorAction SilentlyContinue }
  Write-Output ".gitattributes: removed agent-parity block"
} elseif ($gaState -eq "invalid") {
  Write-Output ".gitattributes: agent-parity markers are incomplete, duplicated, or out of order; file left unchanged -- repair the markers manually"
}
if (Test-GitRepo) {
  & git -C $Target config --remove-section merge.agent-parity-memory 2>$null
}
$gitIgnoreText = Read-Text (Path-InTarget ".gitignore")
$gitIgnoreState = Get-ManagedBlockState $gitIgnoreText $GitIgnoreBegin $GitIgnoreEnd
if ($gitIgnoreState -eq "valid") {
  Strip-GitIgnoreBlock
  Write-Output ".gitignore: removed agent-parity block"
} elseif ($gitIgnoreState -eq "invalid") {
  Write-Output ".gitignore: agent-parity markers are incomplete, duplicated, or out of order; file left unchanged -- repair the markers manually"
}
if ($Purge) {
  if (Test-Path -LiteralPath (Path-InTarget $StoreDir)) { Remove-Item -LiteralPath (Path-InTarget $StoreDir) -Recurse -Force }
  Write-Output "memory store: deleted ($(Path-InTarget $StoreDir))"
} else {
  Write-Output "memory store: kept at $(Path-InTarget $StoreDir) (pass --purge to delete it)"
}
foreach ($name in @("common.ps1", "status.ps1", "version.ps1", "uninstall.ps1", "sync-claude.ps1", "self-heal.ps1", "common.sh", "status.sh", "version.sh", "uninstall.sh", "sync-claude.sh", "self-heal.sh", "merge-memory.sh")) {
  Remove-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Force -ErrorAction SilentlyContinue
}
