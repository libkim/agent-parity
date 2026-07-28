#!/usr/bin/env sh
# The pre-push guard is installed as a .git/hooks/pre-push dispatcher: it blocks
# while managed files are uncommitted, passes once they are committed, preserves
# and chains a user's own hook as pre-push.user, restores it on uninstall, and
# defers entirely when a hook manager owns the dir via core.hooksPath.
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
tests_platform
[ -x "$repo/dist/$editor_asset" ] || { echo "build release assets first: dist/$editor_asset" >&2; exit 1; }

install_into() {
  AGENT_PARITY_RAW="file://$repo" AGENT_PARITY_RELEASE="file://$repo/dist" \
  AGENT_PARITY_VERSION=v9.8.7 AGENT_PARITY_CACHE="$1/cache" \
    sh "$repo/dist/install.sh" "$1"
}
hook_runs() { ( cd "$1" && ./.git/hooks/pre-push origin file:///dev/null </dev/null 2>/dev/null ); }

root=$(mktemp -d "${TMPDIR:-/tmp}/agent-parity-prepush.XXXXXX")
root2=$(mktemp -d "${TMPDIR:-/tmp}/agent-parity-prepush2.XXXXXX")
trap 'rm -rf "$root" "$root2"' EXIT HUP INT TERM

git -C "$root" init -q
install_into "$root" > "$root/out" 2>&1 || { cat "$root/out" >&2; exit 1; }

hook="$root/.git/hooks/pre-push"
[ -x "$hook" ] || { echo "hook not installed" >&2; exit 1; }
grep -qF "agent-parity managed pre-push hook" "$hook" || { echo "hook missing marker" >&2; exit 1; }
grep -q "pre-push guard registered" "$root/out" || { echo "install did not report the hook" >&2; exit 1; }

# Fresh install leaves the managed files uncommitted, so the guard blocks and
# instructs the caller to commit every managed file without advertising a bypass.
if guard_output=$(cd "$root" && ./.git/hooks/pre-push origin file:///dev/null </dev/null 2>&1); then
  echo "hook allowed push with uncommitted managed files" >&2
  exit 1
fi
printf '%s\n' "$guard_output" | grep -qF "Commit every listed managed file, then push again." || {
  echo "hook did not instruct the caller to commit every managed file" >&2
  printf '%s\n' "$guard_output" >&2
  exit 1
}
if printf '%s\n' "$guard_output" | grep -q -- '--no-verify'; then
  echo "hook advertised a pre-push bypass" >&2
  exit 1
fi

# Commit them and the guard passes.
git -C "$root" add -A
git -C "$root" -c user.email=t@e -c user.name=t commit -qm install
hook_runs "$root" || { echo "hook blocked a clean tree" >&2; exit 1; }

# A new uncommitted memory blocks again.
echo body > "$root/.agents/memory/9999.md"
if hook_runs "$root"; then echo "hook allowed an uncommitted memory" >&2; exit 1; fi
rm -f "$root/.agents/memory/9999.md"

# uninstall removes our hook.
AGENT_PARITY_CONFIG_EDITOR="$repo/dist/$editor_asset" sh "$root/.agents/scripts/uninstall.sh" >/dev/null 2>&1
[ ! -e "$hook" ] || { echo "uninstall left the hook behind" >&2; exit 1; }

# A user's own pre-push hook is preserved as pre-push.user and chained from the
# dispatcher, so both the user's checks and our guard run.
git -C "$root2" init -q
mkdir -p "$root2/.git/hooks"
printf '#!/bin/sh\ncat >/dev/null\necho MINE-RAN\n' > "$root2/.git/hooks/pre-push"
chmod +x "$root2/.git/hooks/pre-push"
install_into "$root2" > "$root2/out" 2>&1 || { cat "$root2/out" >&2; exit 1; }
hook2="$root2/.git/hooks/pre-push"
grep -qF "agent-parity managed pre-push hook" "$hook2" || { echo "install did not install the dispatcher" >&2; exit 1; }
[ -x "$hook2.user" ] || { echo "install did not preserve the user hook as pre-push.user" >&2; exit 1; }
grep -q MINE-RAN "$hook2.user" || { echo "pre-push.user is not the original user hook" >&2; exit 1; }
grep -q "preserved your pre-push hook as pre-push.user" "$root2/out" || { echo "install did not report preserving the user hook" >&2; exit 1; }
# Commit managed files so our guard passes, then the dispatcher must still run
# the chained user hook.
git -C "$root2" add -A
git -C "$root2" -c user.email=t@e -c user.name=t commit -qm install
chain_output=$(cd "$root2" && ./.git/hooks/pre-push origin file:///dev/null </dev/null 2>&1) || {
  echo "dispatcher failed on a clean tree" >&2; printf '%s\n' "$chain_output" >&2; exit 1; }
printf '%s\n' "$chain_output" | grep -q MINE-RAN || { echo "dispatcher did not run the chained user hook" >&2; exit 1; }
# uninstall restores the user's original hook to the entry point.
AGENT_PARITY_CONFIG_EDITOR="$repo/dist/$editor_asset" sh "$root2/.agents/scripts/uninstall.sh" >/dev/null 2>&1
grep -q MINE-RAN "$hook2" || { echo "uninstall did not restore the user's original pre-push hook" >&2; exit 1; }
[ ! -e "$hook2.user" ] || { echo "uninstall left pre-push.user behind" >&2; exit 1; }

# When core.hooksPath is set (a hook manager owns the dir), install does not
# touch it and reports how to wire the guard in.
root3=$(mktemp -d "${TMPDIR:-/tmp}/agent-parity-prepush3.XXXXXX")
git -C "$root3" init -q
mkdir -p "$root3/.husky"
git -C "$root3" config core.hooksPath .husky
install_into "$root3" > "$root3/out" 2>&1 || { cat "$root3/out" >&2; exit 1; }
[ ! -e "$root3/.git/hooks/pre-push" ] || { echo "install wrote into .git/hooks despite core.hooksPath" >&2; exit 1; }
[ -z "$(ls -A "$root3/.husky" 2>/dev/null)" ] || { echo "install wrote into the hook manager's dir" >&2; exit 1; }
grep -q "core.hooksPath is set" "$root3/out" || { echo "install did not report the core.hooksPath case" >&2; exit 1; }
rm -rf "$root3"

echo "pre-push guard installs, blocks, chains a user hook, restores on uninstall, and defers to core.hooksPath: OK"
