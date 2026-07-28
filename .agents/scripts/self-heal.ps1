param()

$ErrorActionPreference = "Stop"
$target = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
. (Join-Path $PSScriptRoot "common.ps1") -Target $target
$editor = $ConfigEditor
$desired = ".agents/mcp/memory/run.cmd"
$changed = 0
$failed = 0

# Every failure below becomes a notice instead of a nonzero exit: this runs as
# a session-start hook and Antigravity can crash the turn on nonzero, and a
# hook that dies mid-script reports nothing -- exactly the silent outage this
# script exists to prevent.
$editorOk = $true
try { Ensure-LocalConfigEditor } catch { $editorOk = $false; $failed++ }

if ($editorOk) {
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
}

# The merge driver definition lives in .git/config, which git never carries,
# and machines that only pull never run install -- re-register it here.
# Registration is not a user-facing change, so stay silent either way.
try {
  if ((Test-GitRepo) -and !(Test-MergeDriverRegistered)) {
    & git -C $target config merge.agent-parity-memory.name "agent-parity memory merge" 2>$null
    & git -C $target config merge.agent-parity-memory.driver $MergeDriverCmd 2>$null
  }
  if ((Test-GitRepo) -and !(Test-PrePushHookRegistered)) {
    Register-PrePushHook
  }
} catch { }

# Fill the binary cache ahead of the real MCP launch so a pruned or fresh
# cache never turns into a silent memory outage.
$warm = "ok"
try {
  & (Join-Path $target ".agents\mcp\memory\run.cmd") prewarm *> $null
  if ($LASTEXITCODE -ne 0) { $warm = "failed" }
} catch {
  $warm = "failed"
}

if ($changed -eq 0 -and $failed -eq 0 -and $warm -eq "ok") { exit 0 }
if ($failed -gt 0) {
  Write-Output "agent-parity could not repair every MCP configuration. Run agent-parity status for details."
} elseif ($changed -gt 0) {
  Write-Output "agent-parity updated $changed MCP configuration(s) for this OS. Restart this agent session to load the memory tools."
}
if ($warm -eq "failed") {
  Write-Output "agent-parity could not prepare the memory server binary, so the memory tools may be offline this session. Check the network and restart this agent session."
}
exit 0
