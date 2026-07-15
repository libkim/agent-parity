param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CliArgs
)

$ErrorActionPreference = "Stop"

$Repo = "libkim/agent-parity"
$Raw = if ($env:AGENT_PARITY_RAW) { $env:AGENT_PARITY_RAW } else { "https://raw.githubusercontent.com/$Repo/main" }
$Target = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path

if ($CliArgs.Count -eq 0) {
  $CliArgs = @("--help")
}

$script = (Invoke-WebRequest -UseBasicParsing -Uri "$Raw/install.ps1").Content
if ($CliArgs[0] -in @("install", "update", "uninstall", "status", "version")) {
  $cmd = $CliArgs[0]
  $rest = @()
  if ($CliArgs.Count -gt 1) { $rest = $CliArgs[1..($CliArgs.Count - 1)] }
  & ([scriptblock]::Create($script)) $cmd $Target @rest
} else {
  & ([scriptblock]::Create($script)) @CliArgs $Target
}
exit $LASTEXITCODE
