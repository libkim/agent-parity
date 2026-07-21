#!/usr/bin/env sh
# The pre-push guard is installed as a .git/hooks/pre-push shim, blocks while
# managed files are uncommitted, passes once they are committed, is removed by
# uninstall, and never replaces a user's own pre-push hook.
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

# Fresh install leaves the managed files uncommitted, so the guard blocks.
if hook_runs "$root"; then echo "hook allowed push with uncommitted managed files" >&2; exit 1; fi

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

# A user's own pre-push hook is never replaced.
git -C "$root2" init -q
mkdir -p "$root2/.git/hooks"
printf '#!/bin/sh\necho MINE\n' > "$root2/.git/hooks/pre-push"
chmod +x "$root2/.git/hooks/pre-push"
install_into "$root2" > "$root2/out" 2>&1 || { cat "$root2/out" >&2; exit 1; }
grep -q MINE "$root2/.git/hooks/pre-push" || { echo "install clobbered a user's pre-push hook" >&2; exit 1; }
grep -qF "agent-parity managed pre-push hook" "$root2/.git/hooks/pre-push" && { echo "install overwrote the user hook with ours" >&2; exit 1; }
grep -q "left your existing pre-push hook" "$root2/out" || { echo "install did not warn about the existing hook" >&2; exit 1; }

echo "pre-push guard installs, blocks, uninstalls, and spares a user hook: OK"
