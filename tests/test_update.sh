#!/usr/bin/env sh
# update must exit without changing anything when the installed version already
# matches the target. When the target is newer, it installs every shipped skill
# and tells the user to restart.
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
tests_platform
[ -x "$repo/dist/$editor_asset" ] || { echo "build release assets first: dist/$editor_asset" >&2; exit 1; }

root=$(mktemp -d "${TMPDIR:-/tmp}/agent-parity-update.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM
git -C "$root" init -q

run() {
  AGENT_PARITY_RAW="file://$repo" \
  AGENT_PARITY_RELEASE="file://$repo/dist" \
  AGENT_PARITY_VERSION=v9.8.7 \
  AGENT_PARITY_CACHE="$root/cache" \
    sh "$repo/dist/$1" "$root"
}

run install.sh > "$root/install.out" 2>&1 || { cat "$root/install.out" >&2; exit 1; }
for sk in agent-parity write-requirement write-governance; do
  [ -f "$root/.agents/skills/$sk/SKILL.md" ] || { echo "install did not write $sk" >&2; exit 1; }
done

# Simulate an install made before the authoring skills existed: drop them from
# both the shared source and Claude's mirror so only a template write restores
# them.
rm -rf "$root/.agents/skills/write-requirement" "$root/.agents/skills/write-governance" \
       "$root/.claude/skills/write-requirement" "$root/.claude/skills/write-governance"

run update.sh > "$root/update-same.out" 2>&1 || { cat "$root/update-same.out" >&2; exit 1; }
[ "$(cat "$root/update-same.out")" = 'already up to date: v9.8.7' ]
[ ! -e "$root/.agents/skills/write-requirement" ]
[ ! -e "$root/.agents/skills/write-governance" ]

printf '%s\n' v9.8.6 > "$root/.agents/mcp/memory/VERSION"
: > "$root/.cursorrules"
run update.sh > "$root/update.out" 2>&1 || { cat "$root/update.out" >&2; exit 1; }
grep -qF 'parity: .cursorrules exists -- only Cursor reads it, so agents diverge; fold it into AGENTS.md' "$root/update.out"

# Every shipped skill is present again and was written from the template.
for sk in agent-parity write-requirement write-governance; do
  [ -f "$root/.agents/skills/$sk/SKILL.md" ] || { echo "update did not restore $sk" >&2; exit 1; }
  grep -q "wrote: .*\.agents/skills/$sk/SKILL.md" "$root/update.out" || {
    echo "update did not report writing $sk" >&2; cat "$root/update.out" >&2; exit 1; }
done

# update points the user at a restart, since the running session loads the new
# setup only at startup.
grep -q 'start a new agent session (or restart)' "$root/update.out" || {
  echo "update did not print the restart notice" >&2; cat "$root/update.out" >&2; exit 1; }

# The owned Codex namespace converges while a wrong Cursor structural type is
# left untouched and named in a warning without preventing later files from
# converging.
cat > "$root/.codex/config.toml" <<'EOF'
[mcp_servers.memory]
command = ".agents/mcp/memory/run.sh"
default_tools_approval_mode = "prompt"
EOF
printf '%s\n' '{"permissions":"user-value"}' > "$root/.cursor/cli.json"
rm -f "$root/.agents/hooks.json"
printf '%s\n' v9.8.6 > "$root/.agents/mcp/memory/VERSION"
run update.sh > "$root/update-warnings.out" 2>&1 || { cat "$root/update-warnings.out" >&2; exit 1; }
grep -qF '.cursor/cli.json' "$root/update-warnings.out"
! grep -qF '.codex/config.toml' "$root/update-warnings.out"
grep -q 'configuration: completed with 1 warning(s)' "$root/update-warnings.out"
grep -q 'default_tools_approval_mode = "approve"' "$root/.codex/config.toml"
grep -q '"permissions":"user-value"' "$root/.cursor/cli.json"
[ -f "$root/.agents/hooks.json" ]

echo "update skips equal versions and applies newer versions: OK"
