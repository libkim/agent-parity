#!/usr/bin/env sh
# The bundled git merge driver resolves concurrent memory reinforcement
# (strength/lastAccessed/tags) without conflict markers, and still surfaces a
# real conflict when both sides changed the body.
set -eu

version=${1:-v9.8.7}
repo=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

ext=""
case "$(uname -s)" in
  Linux) goos=linux ;;
  Darwin) goos=darwin ;;
  MINGW* | MSYS* | CYGWIN*) goos=windows; ext=".exe" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) goarch=amd64 ;;
  aarch64 | arm64) goarch=arm64 ;;
  *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac
editor_asset="agent-parity-config-${goos}-${goarch}${ext}"
[ -x "$repo/dist/$editor_asset" ] || { echo "build release assets first: dist/$editor_asset" >&2; exit 1; }

root=$(mktemp -d "${TMPDIR:-/tmp}/agent-parity-merge.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM

mkdir -p "$root/.agents/scripts" "$root/.agents/mcp/memory" "$root/.agents/memory"
cp "$repo/templates/merge-memory.sh" "$root/.agents/scripts/merge-memory.sh"
chmod +x "$root/.agents/scripts/merge-memory.sh"
printf '%s\n' "$version" > "$root/.agents/mcp/memory/VERSION"

cache="$root/cache"
mkdir -p "$cache/config/$version"
cp "$repo/dist/$editor_asset" "$cache/config/$version/$editor_asset"
AGENT_PARITY_CACHE=$cache
export AGENT_PARITY_CACHE

git -C "$root" init -q -b main
git -C "$root" config user.email test@example.com
git -C "$root" config user.name test
git -C "$root" config core.autocrlf false
git -C "$root" config merge.agent-parity-memory.driver '.agents/scripts/merge-memory.sh %O %A %B'
printf '.agents/memory/*.md merge=agent-parity-memory\n' > "$root/.gitattributes"

mem="$root/.agents/memory/100.md"
write_mem() {
  cat > "$mem" <<EOF
---
created: 2026-07-01T00:00:00Z
tags:
$2
strength: $1
lastAccessed: $3
---
$4
EOF
}

write_mem 3 "    - a" "2026-07-02T00:00:00Z" "shared body"
git -C "$root" add -A
git -C "$root" commit -qm base

git -C "$root" checkout -qb side
write_mem 4 "    - a
    - b" "2026-07-04T00:00:00Z" "shared body"
git -C "$root" commit -qam "side recall"

git -C "$root" checkout -q main
write_mem 5 "    - a" "2026-07-03T00:00:00Z" "shared body"
git -C "$root" commit -qam "main recall"

git -C "$root" merge -q --no-edit side
# base 3, main +2, side +1 -> 6; a max-based merge would lose a recall.
grep -q '^strength: 6$' "$mem"
grep -q -- '- b' "$mem"
grep -q '^lastAccessed: 2026-07-04' "$mem"
grep -q '^shared body$' "$mem"

# Bodies edited to different content on both sides must still conflict.
mem2="$root/.agents/memory/200.md"
mem_saved=$mem; mem=$mem2
write_mem 1 "    - a" "2026-07-02T00:00:00Z" "old body"
git -C "$root" add -A
git -C "$root" commit -qm "second memory"
git -C "$root" checkout -qb side2
write_mem 1 "    - a" "2026-07-02T00:00:00Z" "side body"
git -C "$root" commit -qam "side edit"
git -C "$root" checkout -q main
write_mem 1 "    - a" "2026-07-02T00:00:00Z" "main body"
git -C "$root" commit -qam "main edit"
mem=$mem_saved

if git -C "$root" merge -q --no-edit side2 2>/dev/null; then
  echo "conflicting bodies merged silently" >&2
  exit 1
fi
git -C "$root" status --porcelain | grep -q '^UU .agents/memory/200.md'
git -C "$root" merge --abort

echo "memory merge driver: OK"
