#!/usr/bin/env sh
set -eu

[ "$#" -le 1 ] || { echo "usage: self-heal.sh [claude|cursor|codex|antigravity]" >&2; exit 2; }
agent=${1:-}
case "$agent" in
  ""|claude|cursor|codex|antigravity) ;;
  *) echo "self-heal: unknown agent '$agent'" >&2; exit 2 ;;
esac
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
target=$(CDPATH= cd -- "$here/../.." && pwd)
desired=".agent-parity/mcp/memory/run.sh"
changed=0
failed=0
failure_details=""

SCRIPT_DIR=$here
TARGET=$target
. "$here/common.sh"
platform

ensure_config() {
  rel=$1
  result=$("$editor" ensure "$target/$rel" "$desired" 2>&1) || {
    failed=$((failed + 1))
    failure_details="${failure_details}\n  - $rel: $result"
    return
  }
  [ "$result" != changed ] || changed=$((changed + 1))
}

# Every failure below becomes a notice instead of a nonzero exit: this runs as
# a session-start hook and Antigravity can crash the turn on nonzero, and a
# hook that dies mid-script reports nothing -- exactly the silent outage this
# script exists to prevent.
if ensure_local_config_editor 2>/dev/null; then
  editor=$CONFIG_EDITOR
  # Repair only the config this agent reads; leave the others so a different-OS
  # agent sharing this working tree keeps its own launcher. No agent argument
  # (a manual run) heals every config for the current OS.
  case "$agent" in
    claude)      ensure_config ".mcp.json" ;;
    cursor)      ensure_config ".cursor/mcp.json" ;;
    codex)       ensure_config ".codex/config.toml" ;;
    antigravity) ensure_config ".agents/mcp_config.json" ;;
    *)
      ensure_config ".mcp.json"
      ensure_config ".cursor/mcp.json"
      ensure_config ".codex/config.toml"
      ensure_config ".agents/mcp_config.json"
      ;;
  esac
else
  failed=$((failed + 1))
  failure_details="${failure_details}\n  - config editor: could not download or verify the pinned editor"
fi

# The merge driver definition lives in .git/config, which git never carries,
# and machines that only pull never run install -- re-register it here.
# Registration is not a user-facing change, so stay silent either way.
if in_git_repo && ! merge_driver_registered; then
  git -C "$target" config merge.agent-parity-memory.name "agent-parity memory merge" 2>/dev/null || true
  git -C "$target" config merge.agent-parity-memory.driver "$MERGE_DRIVER_CMD" 2>/dev/null || true
fi

# The pre-push guard shim lives in .git/hooks, which git never carries either;
# re-establish it on a fresh clone. Silent, and never over a user's own hook.
if in_git_repo && ! pre_push_hook_registered; then
  reg_pre_push_hook 2>/dev/null || true
fi

# Fill the binary cache ahead of the real MCP launch so a pruned or fresh
# cache never turns into a silent memory outage.
warm=ok
"$target/.agent-parity/mcp/memory/run.sh" prewarm >/dev/null 2>&1 || warm=failed

[ "$changed" -gt 0 ] || [ "$failed" -gt 0 ] || [ "$warm" = failed ] || exit 0
if [ "$failed" -gt 0 ]; then
  printf '%s\n' "agent-parity skipped $failed MCP configuration(s); edit the listed files manually:"
  printf '%b\n' "$failure_details"
elif [ "$changed" -gt 0 ]; then
  printf '%s\n' "agent-parity updated $changed MCP configuration(s) for this OS. Restart this agent session to load the memory tools."
fi
if [ "$warm" = failed ]; then
  printf '%s\n' "agent-parity could not prepare the memory server binary, so the memory tools may be offline this session. Check the network and restart this agent session."
fi
exit 0
