$ErrorActionPreference = "Stop"

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempBase ("agent-parity-wrapper-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$testRoot = (Resolve-Path -LiteralPath $testRoot).Path
if (!$testRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
  throw "unsafe test path: $testRoot"
}

try {
  . (Join-Path $repo "templates/common.ps1") -Target $testRoot
  $claudePath = Path-InTarget "CLAUDE.md"

  [IO.File]::WriteAllText($claudePath, "@AGENTS.md`r`n")
  $mcpOutput = @(Status-McpRegistrations)
  $wrapperOutput = @(Status-ClaudeWrapper)
  if (($mcpOutput -join "`n") -match 'wrapper|CLAUDE\.md') {
    throw "Claude wrapper leaked into MCP status: $($mcpOutput -join '; ')"
  }
  if (($wrapperOutput -join "`n") -ne "claude wrapper: registered (CLAUDE.md)") {
    throw "unexpected wrapper status: $wrapperOutput"
  }

  Unreg-ClaudeWrapper | Out-Null
  if (Test-Path -LiteralPath $claudePath) {
    throw "exact Claude wrapper was not removed"
  }

  [IO.File]::WriteAllText($claudePath, "@AGENTS.md`r`n`r`n")
  $wrapperOutput = @(Status-ClaudeWrapper)
  if (($wrapperOutput -join "`n") -ne "claude wrapper: not registered (existing CLAUDE.md preserved)") {
    throw "non-exact Claude file was treated as the wrapper: $wrapperOutput"
  }
  Unreg-ClaudeWrapper | Out-Null
  if (!(Test-Path -LiteralPath $claudePath)) {
    throw "user-owned CLAUDE.md was removed"
  }

  Write-Output "PowerShell Claude wrapper separation: OK"
} finally {
  if ($testRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
