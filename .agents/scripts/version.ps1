param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CliArgs
)

$ErrorActionPreference = "Stop"
if ($CliArgs.Count -gt 0 -and $CliArgs[0] -eq "version") { $CliArgs = @($CliArgs | Select-Object -Skip 1) }
if ($CliArgs.Count -gt 0) { throw "usage: agent-parity version" }
$Target = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
. (Join-Path $PSScriptRoot "common.ps1") -Target $Target

$installed = Installed-Version
$latest = Latest-Version
Write-Output "installed: $installed"
Write-Output "latest:    $latest"
Show-UpdateNotice $installed $latest
