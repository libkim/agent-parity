#!/usr/bin/env sh
set -eu

version=${1:?usage: test_readme_install.sh <version>}
repo=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
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
[ ! -e "$root/cache/memory/$version/memory-mcp-linux-amd64" ]

echo "README-style Unix install pipeline: OK"
