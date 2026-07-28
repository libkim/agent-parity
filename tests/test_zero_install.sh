#!/usr/bin/env sh
set -eu

version=${1:?usage: test_zero_install.sh <version>}
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
root=$(mktemp -d "${TMPDIR:-/tmp}/agent-parity-zero-install.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM

mkdir -p "$root/.agents/scripts" "$root/.agents/mcp/memory" "$root/.cursor" "$root/.codex"
cp "$repo/templates/common.sh" "$repo/templates/self-heal.sh" "$root/.agents/scripts/"
cp "$repo/templates/run.sh" "$root/.agents/mcp/memory/run.sh"
chmod +x "$root/.agents/mcp/memory/run.sh"
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

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
tests_platform
cache="$root/empty-cache"
output=$(AGENT_PARITY_CACHE="$cache" sh "$root/.agents/scripts/self-heal.sh")
printf '%s\n' "$output" | grep -qF 'Restart this agent session'
editor="$cache/config/$version/$editor_asset"
[ -x "$editor" ]
[ -x "$cache/memory-mcp/$version/$server_asset" ]

for config in .mcp.json .cursor/mcp.json .codex/config.toml .agents/mcp_config.json; do
  [ "$("$editor" command "$root/$config")" = ".agents/mcp/memory/run.sh" ]
done

# Warm caches (config editor and pre-warmed binary) must not touch the release
# URL and an unchanged repair is silent -- any network attempt against the
# invalid URL would fail and print a notice.
printf '%s\n' 'https://invalid.agent-parity.test' > "$root/.agents/mcp/memory/RELEASE"
second=$(AGENT_PARITY_CACHE="$cache" sh "$root/.agents/scripts/self-heal.sh")
[ -z "$second" ]

echo "Unix fresh-pull zero-install self-heal: OK"
