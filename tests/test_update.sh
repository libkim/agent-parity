#!/usr/bin/env sh
# update must (re)install every shipped skill, not just agent-parity, so an
# existing install that predates a new authoring skill gains it on update. It
# must also tell the user to restart, since a running session loads the server,
# skills, and registrations only at startup.
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

run update.sh > "$root/update.out" 2>&1 || { cat "$root/update.out" >&2; exit 1; }

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

echo "update reinstalls all shipped skills and prompts a restart: OK"
