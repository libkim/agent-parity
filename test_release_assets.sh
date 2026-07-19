#!/usr/bin/env sh
set -eu

version=${1:?usage: test_release_assets.sh <version>}
repo=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
dist="$repo/dist"

expected='agent-parity-config-darwin-amd64
agent-parity-config-darwin-arm64
agent-parity-config-linux-amd64
agent-parity-config-linux-arm64
agent-parity-config-windows-amd64.exe
checksums.txt
install.ps1
install.sh
memory-mcp-darwin-amd64
memory-mcp-darwin-arm64
memory-mcp-linux-amd64
memory-mcp-linux-arm64
memory-mcp-windows-amd64.exe
update.ps1
update.sh'
actual=$(find "$dist" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
[ "$actual" = "$expected" ] || {
  echo "release asset set differs" >&2
  printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
  exit 1
}

(cd "$dist" && sha256sum -c checksums.txt)
grep -qxF "PACKAGED_VERSION=\"$version\"" "$dist/install.sh"
grep -qxF "PACKAGED_VERSION=\"$version\"" "$dist/update.sh"
grep -qxF "\$PackagedVersion = \"$version\"" "$dist/install.ps1"
grep -qxF "\$PackagedVersion = \"$version\"" "$dist/update.ps1"
[ "$("$dist/memory-mcp-linux-amd64" -version)" = "$version" ]

unix_command='curl -fsSL https://github.com/libkim/agent-parity/releases/latest/download/install.sh | sh'
windows_command='irm https://github.com/libkim/agent-parity/releases/latest/download/install.ps1 | iex'
for readme in "$repo/README.md" "$repo/README.ko.md"; do
  [ "$(grep -Fxc "$unix_command" "$readme")" -eq 1 ]
  [ "$(grep -Fxc "$windows_command" "$readme")" -eq 1 ]
  grep -qF '`memory-mcp`' "$readme"
  grep -qF '`agent-parity-config`' "$readme"
done
grep -qF '**Dependency-free**' "$repo/README.md"
grep -qF '**Non-invasive**' "$repo/README.md"
grep -qF '**Zero-install**' "$repo/README.md"
grep -qF '**의존성 없음**' "$repo/README.ko.md"
grep -qF '**비침습**' "$repo/README.ko.md"
grep -qF '**무설치**' "$repo/README.ko.md"
! grep -qiF 'single static binary' "$repo/README.md"
! grep -qF '정적 바이너리 하나' "$repo/README.ko.md"

echo "release assets, embedded version, checksums, and README architecture: OK"
