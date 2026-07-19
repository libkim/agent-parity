#!/usr/bin/env sh
set -eu

[ "$#" -eq 0 ] || { echo "usage: self-heal.sh" >&2; exit 2; }
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
target=$(CDPATH= cd -- "$here/../.." && pwd)
desired=".agents/mcp/memory/run.sh"
changed=0
failed=0

SCRIPT_DIR=$here
TARGET=$target
. "$here/common.sh"
platform
editor=$(local_config_editor_path) || editor=""

[ -x "$editor" ] || {
  echo "agent-parity local config editor is missing: $editor" >&2
  exit 1
}

ensure_config() {
  rel=$1
  result=$("$editor" ensure "$target/$rel" "$desired" 2>/dev/null) || {
    failed=$((failed + 1))
    return
  }
  [ "$result" != changed ] || changed=$((changed + 1))
}

ensure_config ".mcp.json"
ensure_config ".cursor/mcp.json"
ensure_config ".codex/config.toml"
ensure_config ".agents/mcp_config.json"

[ "$changed" -gt 0 ] || [ "$failed" -gt 0 ] || exit 0
if [ "$failed" -gt 0 ]; then
  printf '%s\n' "agent-parity could not repair every MCP configuration. Run agent-parity status for details."
else
  printf '%s\n' "agent-parity updated $changed MCP configuration(s) for this OS. Restart this agent session to load the memory tools."
fi
