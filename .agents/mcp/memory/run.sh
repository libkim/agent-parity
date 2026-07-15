#!/usr/bin/env bash
# Launcher for Linux/macOS (incl. WSL): pick the binary matching this machine's
# OS/arch and exec it. The binary and the default memory dir are resolved
# relative to this script, so the same committed launcher works on any machine
# regardless of where the repo is checked out.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
  Linux) goos=linux ;;
  Darwin) goos=darwin ;;
  *) echo "memory-mcp: unsupported OS $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) goarch=amd64 ;;
  aarch64 | arm64) goarch=arm64 ;;
  *) echo "memory-mcp: unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

bin="$here/dist/memory-mcp-${goos}-${goarch}"
if [ ! -x "$bin" ]; then
  echo "memory-mcp: no binary for ${goos}/${goarch} at $bin (run build.sh)" >&2
  exit 1
fi

# The store lives at <root>/.agents/memory ($MEMORY_DIR overrides). The
# launcher lives at <root>/.agents/mcp/memory, so the root is three levels up.
mem="${MEMORY_DIR:-"$(cd "$here/../../.." && pwd)/.agents/memory"}"

exec "$bin" -dir "$mem" "$@"
