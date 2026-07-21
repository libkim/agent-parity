#!/bin/sh
# agent-parity pre-push guard. git runs pre-push hooks through sh on every OS, so
# this stays a single POSIX script like the memory merge driver.
#
# It refuses a push while any of agent-parity's managed artifacts are
# uncommitted, so a new memory or a wiring change is never left behind on the
# machines that pull this repo. git's own ignore rules decide what counts:
# generated copies (.claude/skills, the binary cache) are ignored, so only files
# meant to be committed ever surface here. Bypass once with `git push --no-verify`.
set -eu

top=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$top" || exit 0

# The roots agent-parity manages. Naming the directories is enough: ignored
# subpaths under them are dropped by git status, so this needs no change when the
# ignore set does.
roots=".agents .mcp.json .codex .cursor .claude/settings.json AGENTS.md CLAUDE.md .gitattributes .gitignore"
present=""
for r in $roots; do
  [ -e "$r" ] && present="$present $r"
done
[ -n "$present" ] || exit 0

# Fail open: a git error here must not block every push.
dirty=$(git status --porcelain -- $present 2>/dev/null) || exit 0
[ -n "$dirty" ] || exit 0

echo "agent-parity: refusing to push -- these managed files are uncommitted:" >&2
printf '%s\n' "$dirty" | sed 's/^/  /' >&2
echo >&2
echo "They carry the shared memory and cross-agent wiring, so other machines need" >&2
echo "them committed. Commit them and push again, or run 'git push --no-verify' to" >&2
echo "bypass this check once." >&2
exit 1
