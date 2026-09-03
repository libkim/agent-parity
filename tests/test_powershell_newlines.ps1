$ErrorActionPreference = "Stop"

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$root = Join-Path $tempBase ("agent-parity-newlines-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $root | Out-Null

try {
  foreach ($scriptName in @("install.ps1", "update.ps1")) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repo "bootstrap\$scriptName"), [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "$scriptName did not parse" }
    $wanted = @("Ensure-Parent", "New-StagingFile", "Match-Newlines", "Test-LfRequired", "Write-Text")
    $definitions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $node.Name }, $true))
    if ($definitions.Count -ne $wanted.Count) { throw "$scriptName is missing a newline-writing function" }
    Invoke-Expression (($definitions | ForEach-Object { $_.Extent.Text }) -join "`n")

    foreach ($newline in @("`n", "`r`n")) {
      $path = Join-Path $root ($scriptName + $(if ($newline -eq "`r`n") { ".crlf" } else { ".lf" }))
      [IO.File]::WriteAllText($path, "old${newline}text${newline}", (New-Object Text.UTF8Encoding($false)))
      Write-Text $path "new`ntext`n"
      $actual = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
      if ($actual -cne "new${newline}text${newline}") { throw "$scriptName did not preserve the existing newline convention" }
    }

    # Our own shell entry points are the exception: sh has to be able to run
    # them, so a CRLF file left by an older install must be rewritten as LF
    # rather than matched. The launcher and the generated hook carry no .sh
    # suffix, so they are named explicitly.
    foreach ($name in @("pre-push.sh", "agent-parity", "pre-push")) {
      # The name is matched as a leaf, so each case needs its own directory.
      $dir = Join-Path $root ($scriptName + "." + [Guid]::NewGuid().ToString("N"))
      New-Item -ItemType Directory -Path $dir | Out-Null
      $path = Join-Path $dir $name
      [IO.File]::WriteAllText($path, "#!/bin/sh`r`nold`r`n", (New-Object Text.UTF8Encoding($false)))
      Write-Text $path "#!/bin/sh`nnew`n"
      $actual = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
      if ($actual.Contains("`r")) { throw "$scriptName kept CRLF in $name" }
    }
  }
  Write-Output "PowerShell atomic writes preserve existing LF/CRLF, force LF for our scripts: OK"
} finally {
  if ($root.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
  }
}
