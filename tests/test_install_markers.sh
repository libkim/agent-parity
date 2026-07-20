#!/usr/bin/env sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
[ -x "$repo/dist/agent-parity-config-linux-amd64" ] || { echo "build release assets first" >&2; exit 1; }
root=$(mktemp -d "${TMPDIR:-/tmp}/agent-parity-install-markers.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM

git -C "$root" init -q
cat > "$root/AGENTS.md" <<'EOF'
user agents content
<!-- agent-parity:begin -->
orphaned managed content
EOF
cat > "$root/.gitignore" <<'EOF'
/user-rule/
# agent-parity:end
# agent-parity:begin
/user-tail/
EOF
cp "$root/AGENTS.md" "$root/AGENTS.before"
cp "$root/.gitignore" "$root/gitignore.before"

AGENT_PARITY_RAW="file://$repo" \
AGENT_PARITY_RELEASE="file://$repo/dist" \
AGENT_PARITY_VERSION=v9.8.7 \
AGENT_PARITY_CACHE="$root/cache" \
  sh "$repo/dist/install.sh" "$root" > "$root/install.out" 2>&1 || { cat "$root/install.out" >&2; exit 1; }
cmp "$root/AGENTS.before" "$root/AGENTS.md"
cmp "$root/gitignore.before" "$root/.gitignore"
grep -q '^AGENTS.md: agent-parity markers are incomplete, duplicated, or out of order; file left unchanged' "$root/install.out"
grep -q '^.gitignore: agent-parity markers are incomplete, duplicated, or out of order; file left unchanged' "$root/install.out"

AGENT_PARITY_RAW="file://$repo" \
AGENT_PARITY_RELEASE="file://$repo/dist" \
AGENT_PARITY_VERSION=v9.8.7 \
AGENT_PARITY_CACHE="$root/cache" \
  sh "$repo/dist/update.sh" "$root" > "$root/update.out" 2>&1 || { cat "$root/update.out" >&2; exit 1; }
cmp "$root/AGENTS.before" "$root/AGENTS.md"
cmp "$root/gitignore.before" "$root/.gitignore"
grep -q '^AGENTS.md: agent-parity markers are incomplete, duplicated, or out of order; file left unchanged' "$root/update.out"
grep -q '^.gitignore: agent-parity markers are incomplete, duplicated, or out of order; file left unchanged' "$root/update.out"

echo "Unix install/update preserve invalid marker files: OK"
