#!/usr/bin/env sh
set -eu

REPO="libkim/agent-parity"

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
target=$(CDPATH= cd -- "$here/../.." && pwd)

if [ "$#" -eq 0 ]; then
  set -- --help
fi

case "${OS:-}:$(uname -s 2>/dev/null || true)" in
  Windows_NT:* | *:MINGW* | *:MSYS* | *:CYGWIN*) exec "$here/agent-parity.cmd" "$@" ;;
esac

case "$1" in
  sync-claude)
    exec "$target/.agents/scripts/sync-claude.sh" sync >/dev/null
    ;;
  self-heal)
    shift
    [ "$#" -eq 0 ] || { echo "usage: agent-parity self-heal" >&2; exit 2; }
    exec "$target/.agents/scripts/self-heal.sh"
    ;;
  update)
    shift
    [ "$#" -eq 0 ] || { echo "usage: agent-parity update" >&2; exit 2; }
    if [ -n "${AGENT_PARITY_RAW:-}" ]; then
      update_raw=${AGENT_PARITY_RAW%/}
      update_release=${AGENT_PARITY_RELEASE:-}
      update_version=${AGENT_PARITY_VERSION:-}
    else
      latest_url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest")
      case "$latest_url" in
        */tag/v*) tag=${latest_url##*/} ;;
        *) echo "could not resolve latest agent-parity release" >&2; exit 1 ;;
      esac
      update_raw="https://raw.githubusercontent.com/$REPO/$tag"
      update_release=${AGENT_PARITY_RELEASE:-"https://github.com/$REPO/releases/download/$tag"}
      update_version=$tag
    fi
    update_url="$update_raw/update.sh"
    tmp=$(mktemp "${TMPDIR:-/tmp}/agent-parity-update.XXXXXX")
    trap 'rm -f "$tmp"' EXIT HUP INT TERM
    curl -fsSL "$update_url" -o "$tmp"
    if AGENT_PARITY_RAW="$update_raw" AGENT_PARITY_RELEASE="$update_release" AGENT_PARITY_VERSION="$update_version" sh "$tmp" update "$target"; then code=0; else code=$?; fi
    rm -f "$tmp"
    trap - EXIT HUP INT TERM
    exit "$code"
    ;;
  uninstall | status | version)
    cmd=$1
    shift
    exec "$target/.agents/scripts/$cmd.sh" "$@"
    ;;
  *)
    echo "usage: agent-parity <sync-claude|self-heal|update|uninstall|status|version>" >&2
    exit 2
    ;;
esac
