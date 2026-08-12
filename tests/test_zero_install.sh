#!/usr/bin/env sh
set -eu

version=${1:?usage: test_zero_install.sh <version>}
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
root=$(mktemp -d "${TMPDIR:-/tmp}/agent-parity-zero-install.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM

mkdir -p "$root/.agent-parity/scripts" "$root/.agent-parity/mcp/memory" "$root/.agents" "$root/.cursor" "$root/.codex"
cp "$repo/templates/common.sh" "$repo/templates/self-heal.sh" "$root/.agent-parity/scripts/"
cp "$repo/templates/run.sh" "$root/.agent-parity/mcp/memory/run.sh"
chmod +x "$root/.agent-parity/mcp/memory/run.sh"
printf '%s\n' "$version" > "$root/.agent-parity/mcp/memory/VERSION"
printf 'file://%s/dist\n' "$repo" > "$root/.agent-parity/mcp/memory/RELEASE"
cat > "$root/.mcp.json" <<'EOF'
{"mcpServers":{"memory":{"command":".agent-parity/mcp/memory/run.cmd"}}}
EOF
cp "$root/.mcp.json" "$root/.cursor/mcp.json"
cp "$root/.mcp.json" "$root/.agents/mcp_config.json"
cat > "$root/.codex/config.toml" <<'EOF'
[mcp_servers.memory]
command = ".agent-parity/mcp/memory/run.cmd"
EOF

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
tests_platform
cache="$root/empty-cache"
output=$(AGENT_PARITY_CACHE="$cache" sh "$root/.agent-parity/scripts/self-heal.sh")
printf '%s\n' "$output" | grep -qF 'Restart this agent session'
editor="$cache/config/$version/$editor_asset"
[ -x "$editor" ]
[ -x "$cache/memory-mcp/$version/$server_asset" ]

for config in .mcp.json .cursor/mcp.json .codex/config.toml .agents/mcp_config.json; do
  [ "$("$editor" command "$root/$config")" = ".agent-parity/mcp/memory/run.sh" ]
done

# A per-agent run (the shape each SessionStart hook uses) repairs only the
# config that agent reads; the other three keep their launcher so a different-OS
# agent sharing this working tree is not clobbered.
cat > "$root/.mcp.json" <<'EOF'
{"mcpServers":{"memory":{"command":".agent-parity/mcp/memory/run.cmd"}}}
EOF
cp "$root/.mcp.json" "$root/.cursor/mcp.json"
cp "$root/.mcp.json" "$root/.agents/mcp_config.json"
cat > "$root/.codex/config.toml" <<'EOF'
[mcp_servers.memory]
command = ".agent-parity/mcp/memory/run.cmd"
EOF
AGENT_PARITY_CACHE="$cache" sh "$root/.agent-parity/scripts/self-heal.sh" cursor >/dev/null
[ "$("$editor" command "$root/.cursor/mcp.json")" = ".agent-parity/mcp/memory/run.sh" ]
for other in .mcp.json .codex/config.toml .agents/mcp_config.json; do
  [ "$("$editor" command "$root/$other")" = ".agent-parity/mcp/memory/run.cmd" ]
done
# Reconverge every config for this OS so the silent-rerun check below holds.
AGENT_PARITY_CACHE="$cache" sh "$root/.agent-parity/scripts/self-heal.sh" >/dev/null

# Warm caches (config editor and pre-warmed binary) must not touch the release
# URL and an unchanged repair is silent -- any network attempt against the
# invalid URL would fail and print a notice.
printf '%s\n' 'https://invalid.agent-parity.test' > "$root/.agent-parity/mcp/memory/RELEASE"
second=$(AGENT_PARITY_CACHE="$cache" sh "$root/.agent-parity/scripts/self-heal.sh")
[ -z "$second" ]

echo "Unix fresh-pull zero-install self-heal: OK"
