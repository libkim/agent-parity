$ErrorActionPreference = "Stop"

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempBase ("agent-parity-atomic-write-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$testRoot = (Resolve-Path -LiteralPath $testRoot).Path
if (!$testRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
  throw "unsafe test path: $testRoot"
}

try {
  . (Join-Path $repo "templates/common.ps1") -Target $testRoot
  $path = Path-InTarget "AGENTS.md"
  [IO.File]::WriteAllText($path, "original`n", (New-Object System.Text.UTF8Encoding($false)))

  Write-Text $path "replacement`n"
  if ((Read-Text $path) -cne "replacement`n") {
    throw "successful atomic write did not replace the target"
  }

  [IO.File]::WriteAllText($path, "original`n", (New-Object System.Text.UTF8Encoding($false)))
  $lock = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
  $failed = $false
  try {
    try {
      Write-Text $path "partial replacement`n"
    } catch {
      $failed = $true
    }
  } finally {
    $lock.Dispose()
  }
  if (!$failed) {
    throw "locked target did not make replacement fail"
  }
  if ((Read-Text $path) -cne "original`n") {
    throw "failed replacement changed the original file"
  }
  $leftovers = @(Get-ChildItem -LiteralPath $testRoot -Filter ".AGENTS.md.agent-parity.*.tmp" -File)
  if ($leftovers.Count -ne 0) {
    throw "failed replacement left staging files: $($leftovers.Name -join ', ')"
  }

  Write-Output "PowerShell atomic user-file write: OK"
} finally {
  if ($testRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
