$ErrorActionPreference = "Stop"

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$files = @(
  Get-ChildItem -LiteralPath (Join-Path $repo "installers") -Filter "*.ps1" -File
  Get-ChildItem -LiteralPath (Join-Path $repo "templates") -Filter "*.ps1" -File
  Get-ChildItem -LiteralPath (Join-Path $repo "tests") -Filter "*.ps1" -File
)
if (Test-Path -LiteralPath (Join-Path $repo "dist") -PathType Container) {
  $files += @(Get-ChildItem -LiteralPath (Join-Path $repo "dist") -Filter "*.ps1" -File)
}

foreach ($file in $files) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) {
    $messages = ($errors | ForEach-Object { $_.Message }) -join "; "
    throw "$($file.FullName): $messages"
  }
}

Write-Output "PowerShell syntax: OK ($($files.Count) files)"
