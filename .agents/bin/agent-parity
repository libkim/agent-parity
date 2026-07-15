#!/usr/bin/env sh
set -eu

REPO="libkim/agent-parity"
RAW="${AGENT_PARITY_RAW:-https://raw.githubusercontent.com/$REPO/main}"

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
target=$(CDPATH= cd -- "$here/../.." && pwd)

if [ "$#" -eq 0 ]; then
  set -- --help
fi

tmp="${TMPDIR:-/tmp}/agent-parity.$$"
trap 'rm -f "$tmp"' EXIT HUP INT TERM
curl -fsSL "$RAW/install.sh" -o "$tmp"
case "$1" in
  install | update | uninstall | status | version)
    cmd=$1
    shift
    exec sh "$tmp" "$cmd" "$target" "$@"
    ;;
  *)
    exec sh "$tmp" "$@" "$target"
    ;;
esac
