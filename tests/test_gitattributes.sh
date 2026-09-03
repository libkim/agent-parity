#!/usr/bin/env sh
# The managed .gitattributes block carries two rules: the memory merge driver
# and an LF pin for our own shell scripts. git runs the merge driver and the
# pre-push guard through sh on every OS, and the pre-push hook execs the script,
# so a Windows checkout under the default core.autocrlf=true must not hand sh a
# CRLF file. This repo pins *.sh for itself, but an installed project only gets
# what the managed block writes.
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
tests_platform
[ -x "$repo/dist/$editor_asset" ] || { echo "build release assets first" >&2; exit 1; }
root=$(mktemp -d "${TMPDIR:-/tmp}/agent-parity-gitattributes.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM

git -C "$root" init -q
# A user rule that install must carry through untouched.
printf '*.png binary\n' > "$root/.gitattributes"

install_target() {
  AGENT_PARITY_RAW="file://$repo" \
  AGENT_PARITY_RELEASE="file://$repo/dist" \
  AGENT_PARITY_VERSION=v9.8.7 \
  AGENT_PARITY_CACHE="$root/cache" \
    sh "$repo/dist/$1" "$root" > "$root/$1.out" 2>&1 ||
      { cat "$root/$1.out" >&2; exit 1; }
}

install_target install.sh

grep -q '^\.agent-parity/memory/\*\.md merge=agent-parity-memory$' "$root/.gitattributes" ||
  { echo "merge driver rule missing" >&2; cat "$root/.gitattributes" >&2; exit 1; }
grep -q '^\.agent-parity/\*\*/\*\.sh text eol=lf$' "$root/.gitattributes" ||
  { echo "script LF pin missing" >&2; cat "$root/.gitattributes" >&2; exit 1; }
grep -q '^\.agent-parity/bin/agent-parity text eol=lf$' "$root/.gitattributes" ||
  { echo "launcher LF pin missing" >&2; cat "$root/.gitattributes" >&2; exit 1; }
grep -q '^\*\.png binary$' "$root/.gitattributes" ||
  { echo "user rule was dropped" >&2; exit 1; }

# The pin has to reach the scripts git actually executes, and stop there: the
# target repo's own shell scripts stay the user's call.
mkdir -p "$root/scripts"
printf '#!/bin/sh\n' > "$root/scripts/user.sh"
for f in .agent-parity/scripts/pre-push.sh .agent-parity/scripts/merge-memory.sh \
         .agent-parity/mcp/memory/run.sh .agent-parity/bin/agent-parity; do
  attr=$(git -C "$root" check-attr eol -- "$f")
  case "$attr" in
    *": eol: lf") ;;
    *) echo "not pinned to LF: $attr" >&2; exit 1 ;;
  esac
done
attr=$(git -C "$root" check-attr eol -- scripts/user.sh)
case "$attr" in
  *": eol: unspecified") ;;
  *) echo "user script must stay unpinned: $attr" >&2; exit 1 ;;
esac

# Converging again must rewrite the block in place, not stack a second copy.
printf '%s\n' v9.8.6 > "$root/.agent-parity/mcp/memory/VERSION"
install_target update.sh
[ "$(grep -c 'text eol=lf' "$root/.gitattributes")" = 2 ] ||
  { echo "block was duplicated" >&2; cat "$root/.gitattributes" >&2; exit 1; }

# Uninstall strips by marker, so it removes both rules and keeps the user's.
PATH="$root/fake-bin:$PATH" \
AGENT_PARITY_CONFIG_EDITOR="$root/cache/config/v9.8.7/$editor_asset" \
  sh "$root/.agent-parity/scripts/uninstall.sh" > "$root/uninstall.out" 2>&1 ||
    { cat "$root/uninstall.out" >&2; exit 1; }
if grep -q 'agent-parity' "$root/.gitattributes" 2>/dev/null; then
  echo "uninstall left managed content behind" >&2
  cat "$root/.gitattributes" >&2
  exit 1
fi
grep -q '^\*\.png binary$' "$root/.gitattributes" ||
  { echo "uninstall dropped the user rule" >&2; exit 1; }

# A project installed before the LF rules existed carries a one-line block.
# Converging it must replace the block in place, not append a second one or
# strand the old single rule outside the markers.
legacy=$(mktemp -d "${TMPDIR:-/tmp}/agent-parity-gitattributes-legacy.XXXXXX")
trap 'rm -rf "$root" "$legacy"' EXIT HUP INT TERM
git -C "$legacy" init -q
cat > "$legacy/.gitattributes" <<'LEGACY'
*.png binary
# agent-parity:begin
.agent-parity/memory/*.md merge=agent-parity-memory
# agent-parity:end
LEGACY

AGENT_PARITY_RAW="file://$repo" AGENT_PARITY_RELEASE="file://$repo/dist" AGENT_PARITY_VERSION=v9.8.7 AGENT_PARITY_CACHE="$legacy/cache"   sh "$repo/dist/install.sh" "$legacy" > "$legacy/install.out" 2>&1 ||
    { cat "$legacy/install.out" >&2; exit 1; }

[ "$(grep -c 'agent-parity:begin' "$legacy/.gitattributes")" = 1 ] ||
  { echo "legacy converge duplicated the block" >&2; cat "$legacy/.gitattributes" >&2; exit 1; }
[ "$(grep -c 'text eol=lf' "$legacy/.gitattributes")" = 2 ] ||
  { echo "legacy converge did not add both LF rules" >&2; cat "$legacy/.gitattributes" >&2; exit 1; }
[ "$(grep -c 'merge=agent-parity-memory' "$legacy/.gitattributes")" = 1 ] ||
  { echo "legacy merge rule was duplicated or lost" >&2; cat "$legacy/.gitattributes" >&2; exit 1; }
grep -q '^\*\.png binary$' "$legacy/.gitattributes" ||
  { echo "legacy converge dropped the user rule" >&2; exit 1; }

echo "gitattributes managed block: OK"
