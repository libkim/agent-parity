#!/usr/bin/env bash
# Cross-compile static, runtime-free binaries for each target OS/arch.
# CGO_ENABLED=0 keeps the build pure-Go so all targets build from one machine.
set -euo pipefail

APP="memory-mcp"
OUT="dist"
# Release CI passes VERSION from the git tag; local builds fall back to git.
VERSION="${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"

# OS/arch targets. Add more (e.g. linux/arm64, darwin/amd64) as needed.
TARGETS="linux/amd64 linux/arm64 windows/amd64 darwin/amd64 darwin/arm64"

rm -rf "$OUT"
mkdir -p "$OUT"

for t in $TARGETS; do
  os="${t%/*}"
  arch="${t#*/}"
  ext=""
  [ "$os" = "windows" ] && ext=".exe"
  echo "building ${os}/${arch}..."
  # CGO_ENABLED=0 yields a fully static ELF with no PT_INTERP. The kernel loads
  # it directly without a dynamic linker, which also lets linux/arm64 run on
  # Termux/Android: Android's PIE requirement is enforced by the linker, and a
  # static no-interpreter binary never invokes it. (A PIE build would instead
  # request /lib/ld-linux-aarch64.so.1, which Termux lacks.)
  CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" \
    go build -buildvcs=false -trimpath -ldflags="-s -w -X main.version=${VERSION}" \
    -o "${OUT}/${APP}-${os}-${arch}${ext}" .
  CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" \
    go build -tags configeditor -buildvcs=false -trimpath -ldflags="-s -w" \
    -o "${OUT}/agent-parity-config-${os}-${arch}${ext}" .
done

# The launchers verify every downloaded release binary before caching it.
(cd "$OUT" && sha256sum memory-mcp-* agent-parity-config-* | LC_ALL=C sort -k2 > checksums.txt)

# Installers and updaters are release assets. Bake the tag into each copy so
# the downloaded bootstrap and every file it installs use one release.
sed "s/^PACKAGED_VERSION=\"dev\"$/PACKAGED_VERSION=\"$VERSION\"/" install.sh > "$OUT/install.sh"
sed "s/^\\\$PackagedVersion = \"dev\"$/\\\$PackagedVersion = \"$VERSION\"/" install.ps1 > "$OUT/install.ps1"
sed "s/^PACKAGED_VERSION=\"dev\"$/PACKAGED_VERSION=\"$VERSION\"/" update.sh > "$OUT/update.sh"
sed "s/^\\\$PackagedVersion = \"dev\"$/\\\$PackagedVersion = \"$VERSION\"/" update.ps1 > "$OUT/update.ps1"
grep -q "^PACKAGED_VERSION=\"$VERSION\"$" "$OUT/install.sh"
grep -q "^\\\$PackagedVersion = \"$VERSION\"$" "$OUT/install.ps1"
grep -q "^PACKAGED_VERSION=\"$VERSION\"$" "$OUT/update.sh"
grep -q "^\\\$PackagedVersion = \"$VERSION\"$" "$OUT/update.ps1"

echo "done -> ${OUT}/"
ls -lh "$OUT"
