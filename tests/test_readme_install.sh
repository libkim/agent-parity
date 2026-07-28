#!/usr/bin/env sh
set -eu

version=${1:?usage: test_readme_install.sh <version>}
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
tests_platform
root=$(mktemp -d "${TMPDIR:-/tmp}/agent-parity-readme-install.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM

(
  cd "$root"
  export AGENT_PARITY_RAW="file://$repo"
  export AGENT_PARITY_RELEASE="file://$repo/dist"
  export AGENT_PARITY_CACHE="$root/cache"
  curl -fsSL "file://$repo/dist/install.sh" | sh
)

[ "$(tr -d '\r\n' < "$root/.agents/mcp/memory/VERSION")" = "$version" ]
[ -x "$root/.agents/bin/agent-parity" ]
[ -x "$root/.agents/scripts/status.sh" ]
[ -f "$root/.mcp.json" ]
[ -f "$root/.cursor/cli.json" ]
# install must not pre-download the server binary; that happens at first
# MCP launch or the session-start pre-warm.
[ ! -e "$root/cache/memory-mcp/$version/$server_asset" ]

echo "README-style Unix install pipeline: OK"
