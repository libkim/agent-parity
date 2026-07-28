param(
  [Parameter(Position = 0)]
  [string]$Version = "v9.8.7"
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$status = @(& git -C $repo status --porcelain)
if ($LASTEXITCODE -ne 0) { throw "could not read git status" }

$notStaged = @($status | Where-Object {
  $_.Length -lt 2 -or $_[1] -ne ' '
})
if ($notStaged.Count -ne 0) {
  throw "stage every change before testing; the container tests the Git index snapshot:`n$($notStaged -join "`n")"
}

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tempRoot = Join-Path $tempBase ("agent-parity-release-container-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$tempRoot = (Resolve-Path -LiteralPath $tempRoot).Path
if (!$tempRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
  throw "unsafe temporary path: $tempRoot"
}

try {
  $tree = [string](& git -C $repo write-tree)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($tree)) {
    throw "could not create a tree from the Git index"
  }
  $tree = $tree.Trim()

  $archive = Join-Path $tempRoot "source.tar"
  & git -C $repo archive --format=tar "--output=$archive" $tree
  if ($LASTEXITCODE -ne 0) { throw "could not archive the Git index tree" }

  $mount = "type=bind,source=$archive,target=/snapshot/source.tar,readonly"
  $suite = @'
set -euo pipefail
mkdir -p /work
tar -xf /snapshot/source.tar -C /work
cd /work

# A Git archive contains only indexed files, so ignored caches never enter this
# workspace. Git for Windows may still apply checkout EOL conversion while
# archiving, so normalize known text sources inside this disposable copy.
test ! -e .git
test ! -e .cache
test ! -e dist
find . -type f \( \
  -name '*.cmd' -o -name '*.go' -o -name '*.json' -o -name '*.md' -o \
  -name '*.mod' -o -name '*.ps1' -o -name '*.sh' -o -name '*.sum' -o \
  -name '*.toml' -o -name '*.txt' -o -name '*.yaml' -o -name '*.yml' -o \
  -name '.gitattributes' -o -name '.gitignore' -o -name 'RELEASE' -o \
  -name 'VERSION' -o -name 'agent-parity' \
\) -exec sed -i 's/\r$//' {} +

for attempt in 1 2 3; do
  if go mod download; then break; fi
  if [ "$attempt" -eq 3 ]; then exit 1; fi
  sleep $((attempt * 2))
done

go test ./...
go test -tags configeditor ./...
VERSION="$RELEASE_VERSION" bash build.sh
sh tests/test_release_assets.sh "$RELEASE_VERSION"
sh tests/test_markers.sh
sh tests/test_uninstall.sh
sh tests/test_install_markers.sh
sh tests/test_readme_install.sh "$RELEASE_VERSION"
sh tests/test_zero_install.sh "$RELEASE_VERSION"
sh tests/test_memory_merge.sh "$RELEASE_VERSION"
sh tests/test_update.sh
sh tests/test_pre_push.sh
'@

  Write-Output "Testing staged Git snapshot $tree in Linux (version $Version)"
  & docker run --rm `
    --mount $mount `
    --mount "type=volume,source=agent-parity-go-mod-cache,target=/go/pkg/mod" `
    --mount "type=volume,source=agent-parity-go-build-cache,target=/root/.cache/go-build" `
    --env "RELEASE_VERSION=$Version" `
    golang:1.25 bash -c $suite
  if ($LASTEXITCODE -ne 0) { throw "release container tests failed with exit code $LASTEXITCODE" }
} finally {
  if ($tempRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Output "staged Linux release suite: OK"
