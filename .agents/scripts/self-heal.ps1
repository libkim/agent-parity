param()

$ErrorActionPreference = "Stop"
$target = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
. (Join-Path $PSScriptRoot "common.ps1") -Target $target
$editor = $ConfigEditor
$desired = ".agents/mcp/memory/run.cmd"
$changed = 0
$failed = 0

Ensure-LocalConfigEditor

foreach ($rel in @(".mcp.json", ".cursor/mcp.json", ".codex/config.toml", ".agents/mcp_config.json")) {
  $path = Join-Path $target ($rel.Replace('/', '\'))
  try {
    $result = & $editor ensure $path $desired
    if ($LASTEXITCODE -ne 0) { throw "config editor failed" }
    if (($result | Out-String).Trim() -eq "changed") { $changed++ }
  } catch {
    $failed++
  }
}

if ($changed -eq 0 -and $failed -eq 0) { exit 0 }
if ($failed -gt 0) {
  Write-Output "agent-parity could not repair every MCP configuration. Run agent-parity status for details."
} else {
  Write-Output "agent-parity updated $changed MCP configuration(s) for this OS. Restart this agent session to load the memory tools."
}
