#!/usr/bin/env sh
set -eu

version=${1:?usage: test_zero_install.sh <version>}
repo=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(mktemp -d "${TMPDIR:-/tmp}/agent-parity-zero-install.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM

mkdir -p "$root/.agents/scripts" "$root/.agents/mcp/memory" "$root/.cursor" "$root/.codex"
cp "$repo/templates/common.sh" "$repo/templates/self-heal.sh" "$root/.agents/scripts/"
printf '%s\n' "$version" > "$root/.agents/mcp/memory/VERSION"
printf 'file://%s/dist\n' "$repo" > "$root/.agents/mcp/memory/RELEASE"
cat > "$root/.mcp.json" <<'EOF'
{"mcpServers":{"memory":{"command":".agents/mcp/memory/run.cmd"}}}
EOF
cp "$root/.mcp.json" "$root/.cursor/mcp.json"
cp "$root/.mcp.json" "$root/.agents/mcp_config.json"
cat > "$root/.codex/config.toml" <<'EOF'
[mcp_servers.memory]
command = ".agents/mcp/memory/run.cmd"
EOF

cache="$root/empty-cache"
output=$(AGENT_PARITY_CACHE="$cache" sh "$root/.agents/scripts/self-heal.sh")
printf '%s\n' "$output" | grep -qF 'Restart this agent session'
editor="$cache/config/$version/agent-parity-config-linux-amd64"
[ -x "$editor" ]
[ ! -e "$cache/memory-mcp" ]

for config in .mcp.json .cursor/mcp.json .codex/config.toml .agents/mcp_config.json; do
  [ "$("$editor" command "$root/$config")" = ".agents/mcp/memory/run.sh" ]
done

# A warm cache must not touch the release URL and an unchanged repair is silent.
printf '%s\n' 'https://invalid.agent-parity.test' > "$root/.agents/mcp/memory/RELEASE"
second=$(AGENT_PARITY_CACHE="$cache" sh "$root/.agents/scripts/self-heal.sh")
[ -z "$second" ]

echo "Unix fresh-pull zero-install self-heal: OK"
