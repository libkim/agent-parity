#!/usr/bin/env sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
tests_platform
config_editor=${AGENT_PARITY_CONFIG_EDITOR:-"$repo/dist/$editor_asset"}
[ -x "$config_editor" ] || { echo "build the Linux config editor first: $config_editor" >&2; exit 1; }
root=$(mktemp -d "${TMPDIR:-/tmp}/agent-parity-uninstall-test.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM

mkdir -p "$root/.agents/scripts" "$root/.agents/mcp/memory" "$root/.agents/claude" \
  "$root/.agents/skills/agent-parity" "$root/.claude/skills/agent-parity" \
  "$root/.codex" "$root/.cursor" "$root/fake-bin"
cp "$repo/templates/common.sh" "$repo/templates/uninstall.sh" "$root/.agents/scripts/"
cp "$repo/templates/status.sh" "$root/.agents/scripts/"
: > "$root/.agents/scripts/sync-claude.sh"
: > "$root/.agents/skills/agent-parity/SKILL.md"
: > "$root/.claude/skills/agent-parity/SKILL.md"
printf '%s\n' vtest > "$root/.agents/mcp/memory/VERSION"

cat > "$root/.agents/mcp/memory/run.sh" <<'EOF'
#!/usr/bin/env sh
touch "$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)/mcp-binary-called"
exit 92
EOF
chmod +x "$root/.agents/mcp/memory/run.sh"
cat > "$root/fake-bin/curl" <<EOF
#!/usr/bin/env sh
touch "$root/network-called"
exit 91
EOF
chmod +x "$root/fake-bin/curl"

cat > "$root/.mcp.json" <<'EOF'
{"keep":true,"mcpServers":{"memory":{"command":".agents/mcp/memory/run.sh"},"other":{"command":"other"}}}
EOF
cat > "$root/.codex/config.toml" <<'EOF'
# keep
[mcp_servers.other]
command = "other"

[mcp_servers.memory]
command = ".agents/mcp/memory/run.sh"

[mcp_servers.memory.tools.memory_add]
approval_mode = "approve"
EOF
cat > "$root/.agents/claude/settings.json" <<'EOF'
{"model":"opus","autoMemoryEnabled":false,"enabledMcpjsonServers":["memory"],"hooks":{"SessionStart":[{"hooks":[{"command":"echo user"}]},{"hooks":[{"command":".agents/bin/agent-parity sync-claude"},{"command":".agents/bin/agent-parity self-heal"}]}]}}
EOF
cat > "$root/.cursor/cli.json" <<'EOF'
{"theme":"dark","permissions":{"allow":["Shell(git:*)","Mcp(memory:*)"],"deny":["Shell(rm:*)"]}}
EOF
printf '%s\n' '@AGENTS.md' > "$root/CLAUDE.md"
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
agents_before=$(cat "$root/AGENTS.md")
gitignore_before=$(cat "$root/.gitignore")

status_output=$(PATH="$root/fake-bin:$PATH" AGENT_PARITY_CONFIG_EDITOR="$config_editor" sh "$root/.agents/scripts/status.sh")
printf '%s\n' "$status_output" | grep -q '^mcp registrations:$'
printf '%s\n' "$status_output" | grep -q '^claude wrapper: registered (CLAUDE.md)$'
! printf '%s\n' "$status_output" | grep -q '^  Claude wrapper:'
printf '%s\n' "$status_output" | grep -q '^AGENTS.md: agent-parity markers are incomplete, duplicated, or out of order; repair them manually$'
printf '%s\n' "$status_output" | grep -q '^.gitignore: agent-parity markers are incomplete, duplicated, or out of order; repair them manually$'
rm -f "$root/network-called" "$root/mcp-binary-called"

(TARGET="$root"; . "$root/.agents/scripts/common.sh"; unreg_claude_wrapper)
[ ! -e "$root/CLAUDE.md" ]
printf '%s\n' 'user-owned Claude instructions' > "$root/CLAUDE.md"

PATH="$root/fake-bin:$PATH" AGENT_PARITY_CONFIG_EDITOR="$config_editor" sh "$root/.agents/scripts/uninstall.sh"

[ ! -e "$root/network-called" ]
[ ! -e "$root/mcp-binary-called" ]
[ ! -e "$root/.agents/mcp/memory" ]
grep -q '"keep": true' "$root/.mcp.json"
grep -q '"other"' "$root/.mcp.json"
! grep -q '"memory"' "$root/.mcp.json"
grep -q '\[mcp_servers.other\]' "$root/.codex/config.toml"
! grep -q 'mcp_servers.memory' "$root/.codex/config.toml"
grep -q '"model": "opus"' "$root/.agents/claude/settings.json"
grep -q 'echo user' "$root/.agents/claude/settings.json"
! grep -q 'agent-parity' "$root/.agents/claude/settings.json"
grep -q '"theme": "dark"' "$root/.cursor/cli.json"
grep -q 'Shell(git:\*)' "$root/.cursor/cli.json"
grep -q 'Shell(rm:\*)' "$root/.cursor/cli.json"
! grep -q 'Mcp(memory:\*)' "$root/.cursor/cli.json"
grep -q '^user-owned Claude instructions$' "$root/CLAUDE.md"
[ "$(cat "$root/AGENTS.md")" = "$agents_before" ]
[ "$(cat "$root/.gitignore")" = "$gitignore_before" ]

echo "offline Unix uninstall: OK"
