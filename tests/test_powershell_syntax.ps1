$ErrorActionPreference = "Stop"

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$files = @(
  Get-ChildItem -LiteralPath (Join-Path $repo "bootstrap") -Filter "*.ps1" -File
  Get-ChildItem -LiteralPath (Join-Path $repo "scripts") -Filter "*.ps1" -File
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

# The release scripts are also evaluated from downloaded text. Keeping the
# config editor path as an explicit function result prevents ScriptBlock child
# scope from splitting $ConfigEditor and $script:ConfigEditor again.
foreach ($name in @("install.ps1", "update.ps1")) {
  $source = [IO.File]::ReadAllText((Join-Path $repo "bootstrap\$name"))
  if ($source.Contains('$script:ConfigEditor')) {
    throw "$name reintroduced script-scope ConfigEditor state"
  }
  if (!$source.Contains('$ConfigEditor = Install-ConfigEditor')) {
    throw "$name does not capture the config editor path explicitly"
  }
}

Write-Output "PowerShell syntax: OK ($($files.Count) files)"
