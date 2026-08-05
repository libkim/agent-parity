param(
  [Parameter(Position = 0)]
  [string]$Version = "v9.8.7"
)

# The PowerShell install path (Reg-PrePushHook) installs .git/hooks/pre-push only
# when the entry point is empty or already ours; the hook just runs the tracked
# guard. A pre-existing user hook and a core.hooksPath manager are left untouched,
# with a message telling the user to wire the guard in. The unix test
# (test_pre_push.sh) covers the shell installer; this covers the ps1 one.
$ErrorActionPreference = "Stop"
$testRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$dist = Join-Path $testRepoRoot "dist"
if (!(Test-Path -LiteralPath (Join-Path $dist "agent-parity-config-windows-amd64.exe") -PathType Leaf)) {
  throw "build release assets first"
}

$marker = "# agent-parity managed pre-push hook"

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())

function New-TestRepo {
  $root = Join-Path $tempBase ("ap-prepush-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
  New-Item -ItemType Directory -Path $root | Out-Null
  $root = (Resolve-Path -LiteralPath $root).Path
  if (!$root.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) { throw "unsafe test path: $root" }
  & git -C $root init -q
  if ($LASTEXITCODE -ne 0) { throw "git init failed" }
  return $root
}

function Invoke-Install {
  param([string]$Root)
  $base = "https://agent-parity.test"
  function Invoke-WebRequest {
    param([switch]$UseBasicParsing, [Parameter(Mandatory = $true)][string]$Uri, [string]$OutFile)
    $prefix = "$base/"
    if (!$Uri.StartsWith($prefix, [StringComparison]::Ordinal)) { throw "unexpected test URL: $Uri" }
    $relative = $Uri.Substring($prefix.Length).Replace('/', [IO.Path]::DirectorySeparatorChar)
    $path = [IO.Path]::GetFullPath((Join-Path $testRepoRoot $relative))
    $repoPrefix = $testRepoRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (!$path.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "test URL does not map to a repository file: $Uri"
    }
    if ($OutFile) { Copy-Item -LiteralPath $path -Destination $OutFile -Force; return }
    return [pscustomobject]@{ Content = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) }
  }
  $env:AGENT_PARITY_RAW = $base
  $env:AGENT_PARITY_RELEASE = "$base/dist"
  $env:AGENT_PARITY_VERSION = $null
  $env:AGENT_PARITY_CACHE = Join-Path $Root "c"
  Push-Location -LiteralPath $Root
  try {
    $out = Invoke-Expression ([IO.File]::ReadAllText((Join-Path $dist "install.ps1"), [Text.Encoding]::UTF8)) *>&1
  } finally { Pop-Location }
  if ($LASTEXITCODE -ne 0) { throw "install leaked native exit code $LASTEXITCODE" }
  return ($out | Out-String)
}

$oldRaw = $env:AGENT_PARITY_RAW
$oldRelease = $env:AGENT_PARITY_RELEASE
$oldVersion = $env:AGENT_PARITY_VERSION
$oldCache = $env:AGENT_PARITY_CACHE
$roots = @()

try {
  # 1) Fresh git repo, no prior hook: install writes our guard hook with the marker.
  $r1 = New-TestRepo; $roots += $r1
  Invoke-Install -Root $r1 | Out-Null
  $hook1 = Join-Path $r1 ".git\hooks\pre-push"
  if (!(Test-Path -LiteralPath $hook1 -PathType Leaf)) { throw "install did not write the pre-push guard" }
  if (![IO.File]::ReadAllText($hook1).Contains($marker)) { throw "guard missing the managed marker" }

  # 2) Pre-existing user hook: install leaves it untouched, does not rename it,
  # and reports how to wire the guard in.
  $r2 = New-TestRepo; $roots += $r2
  $hook2 = Join-Path $r2 ".git\hooks\pre-push"
  New-Item -ItemType Directory -Force -Path (Split-Path $hook2) | Out-Null
  [IO.File]::WriteAllText($hook2, "#!/bin/sh`necho MINE-RAN`n")
  $out2 = Invoke-Install -Root $r2
  if (![IO.File]::ReadAllText($hook2).Contains("MINE-RAN")) { throw "install clobbered the user's pre-push hook" }
  if ([IO.File]::ReadAllText($hook2).Contains($marker)) { throw "install overwrote the user hook with ours" }
  if (Test-Path -LiteralPath "$hook2.user") { throw "install created pre-push.user (should not rename)" }
  if (($out2 -join "`n") -notmatch "your own pre-push hook is in place") { throw "install did not report the user hook" }
  # uninstall leaves the user's own hook alone.
  & (Join-Path $r2 ".agents\bin\agent-parity.cmd") uninstall *> $null
  if (![IO.File]::ReadAllText($hook2).Contains("MINE-RAN")) { throw "uninstall removed the user's own pre-push hook" }

  # 3) core.hooksPath set (a hook manager owns the dir): install does not touch it.
  $r3 = New-TestRepo; $roots += $r3
  New-Item -ItemType Directory -Force -Path (Join-Path $r3 ".husky") | Out-Null
  & git -C $r3 config core.hooksPath .husky
  Invoke-Install -Root $r3 | Out-Null
  if (Test-Path -LiteralPath (Join-Path $r3 ".git\hooks\pre-push")) { throw "install wrote into .git/hooks despite core.hooksPath" }
  if (Get-ChildItem -LiteralPath (Join-Path $r3 ".husky") -ErrorAction SilentlyContinue) { throw "install wrote into the hook manager's dir" }

  Write-Output "pre-push (PowerShell path): guard install, user-hook left alone, core.hooksPath deferral: OK"
} finally {
  $env:AGENT_PARITY_RAW = $oldRaw
  $env:AGENT_PARITY_RELEASE = $oldRelease
  $env:AGENT_PARITY_VERSION = $oldVersion
  $env:AGENT_PARITY_CACHE = $oldCache
  foreach ($r in $roots) {
    if ($r -and $r.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}
