$ErrorActionPreference = "Stop"

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$root = Join-Path $tempBase ("agent-parity-launcher-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path (Join-Path $root ".agent-parity\bin") -Force | Out-Null

try {
  $launcher = Join-Path $root ".agent-parity\bin\agent-parity.cmd"
  $source = [IO.File]::ReadAllText((Join-Path $repo "templates\project-agent-parity.cmd"), [Text.Encoding]::UTF8)
  $downloadCommand = '  powershell -NoProfile -ExecutionPolicy Bypass -File "%agent_parity_bin%fake-update.ps1" "%AGENT_PARITY_TARGET%"'
  $source = [regex]::Replace($source, '(?m)^  powershell -NoProfile -ExecutionPolicy Bypass -Command .*$', $downloadCommand)
  if (!$source.Contains($downloadCommand)) { throw "could not inject the launcher update fixture" }
  [IO.File]::WriteAllText($launcher, $source, (New-Object Text.UTF8Encoding($false)))

  $replacement = "@echo off`r`nrem replacement launcher`r`nexit /b 0`r`n"
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($replacement))
  $fakeUpdate = @"
param([string]`$Target)
`$bytes = [Convert]::FromBase64String('$encoded')
[IO.File]::WriteAllBytes((Join-Path `$Target '.agent-parity\bin\agent-parity.cmd.new'), `$bytes)
"@
  [IO.File]::WriteAllText((Join-Path $root ".agent-parity\bin\fake-update.ps1"), $fakeUpdate, (New-Object Text.UTF8Encoding($false)))

  & cmd.exe /d /c "`"$launcher`" update"
  if ($LASTEXITCODE -ne 0) { throw "launcher update exited with $LASTEXITCODE" }
  if (Test-Path -LiteralPath "$launcher.new") { throw "launcher left agent-parity.cmd.new behind" }
  if ([IO.File]::ReadAllText($launcher, [Text.Encoding]::UTF8) -cne $replacement) { throw "launcher did not install the staged replacement intact" }

  Write-Output "Windows running launcher replacement: OK"
} finally {
  if ($root.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
  }
}
