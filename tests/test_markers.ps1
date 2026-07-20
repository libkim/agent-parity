$ErrorActionPreference = "Stop"

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempBase ("agent-parity-markers-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$testRoot = (Resolve-Path -LiteralPath $testRoot).Path
if (!$testRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
  throw "unsafe test path: $testRoot"
}

try {
  . (Join-Path $repo "templates/common.ps1") -Target $testRoot
  $cases = @(
    @{ Name = "missing"; Expected = "absent"; Text = $null },
    @{ Name = "clean"; Expected = "absent"; Text = "user content`n" },
    @{ Name = "valid"; Expected = "valid"; Text = "<!-- agent-parity:begin -->`r`nmanaged`r`n<!-- agent-parity:end -->`r`n" },
    @{ Name = "begin-only"; Expected = "invalid"; Text = "<!-- agent-parity:begin -->`nmanaged`n" },
    @{ Name = "end-only"; Expected = "invalid"; Text = "<!-- agent-parity:end -->`n" },
    @{ Name = "reversed"; Expected = "invalid"; Text = "<!-- agent-parity:end -->`nmanaged`n<!-- agent-parity:begin -->`n" },
    @{ Name = "duplicate"; Expected = "invalid"; Text = "<!-- agent-parity:begin -->`nmanaged`n<!-- agent-parity:end -->`n<!-- agent-parity:begin -->`n" },
    @{ Name = "embedded"; Expected = "invalid"; Text = "note: <!-- agent-parity:begin -->`n<!-- agent-parity:end -->`n" }
  )
  foreach ($case in $cases) {
    $actual = Get-ManagedBlockState $case.Text "<!-- agent-parity:begin -->" "<!-- agent-parity:end -->"
    if ($actual -ne $case.Expected) {
      throw "$($case.Name): expected $($case.Expected), got $actual"
    }
  }
  Write-Output "PowerShell managed marker states: OK"
} finally {
  if ($testRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
