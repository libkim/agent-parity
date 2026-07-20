#!/usr/bin/env sh
# git merge driver for .agents/memory/*.md: resolves the platform config
# editor from the shared cache and delegates the 3-way merge to it. git runs
# merge drivers through sh on every platform (Git for Windows bundles one),
# so this single script serves all OSes. It stays offline: the session-start
# hook provisions the editor, so a missing editor here just means falling
# back to a normal conflict.
set -eu

[ "$#" -eq 3 ] || { echo "usage: merge-memory.sh <base> <ours> <theirs>" >&2; exit 2; }
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
target=$(CDPATH= cd -- "$here/../.." && pwd)

version_file="$target/.agents/mcp/memory/VERSION"
[ -f "$version_file" ] || { echo "merge-memory: missing $version_file" >&2; exit 1; }
version=$(tr -d '\r\n' < "$version_file")

ext=""
case "$(uname -s)" in
  Linux) goos=linux ;;
  Darwin) goos=darwin ;;
  MINGW* | MSYS* | CYGWIN*) goos=windows; ext=".exe" ;;
  *) echo "merge-memory: unsupported OS $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) goarch=amd64 ;;
  aarch64 | arm64) goarch=arm64 ;;
  *) echo "merge-memory: unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

if [ "$goos" = windows ]; then
  # Match the cache root the Windows installer and run.cmd use; LOCALAPPDATA
  # holds a Windows-style path, so convert it for this sh context.
  if [ -n "${AGENT_PARITY_CACHE:-}" ]; then
    win_root=$AGENT_PARITY_CACHE
  elif [ -n "${LOCALAPPDATA:-}" ]; then
    win_root="$LOCALAPPDATA\\agent-parity\\cache"
  else
    win_root="${USERPROFILE:?USERPROFILE is not set}\\.cache\\agent-parity"
  fi
  cache_root=$(cygpath -u "$win_root")
else
  cache_root=${AGENT_PARITY_CACHE:-${XDG_CACHE_HOME:-${HOME:?HOME is not set}/.cache}/agent-parity}
fi

editor="$cache_root/config/$version/agent-parity-config-${goos}-${goarch}${ext}"
if [ ! -x "$editor" ]; then
  echo "merge-memory: config editor not provisioned at $editor -- start an agent session (or run agent-parity status) and retry the merge" >&2
  exit 1
fi

exec "$editor" merge-memory "$1" "$2" "$3"
