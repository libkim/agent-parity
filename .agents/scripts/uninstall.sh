#!/usr/bin/env sh
set -eu
PURGE=no
while [ "$#" -gt 0 ]; do
  case "$1" in
    --purge) PURGE=yes ;;
    *) echo "usage: agent-parity uninstall [--purge]" >&2; exit 2 ;;
  esac
  shift
done
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TARGET=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
. "$SCRIPT_DIR/common.sh"
platform
require_local_config_editor

echo "configs:"
for_each_mcp_config unreg_mcp_config
unreg_cursor_cli
unreg_claude_wrapper
unreg_agent_hooks
rm -f "$TARGET/$PROJECT_CLI_DIR/agent-parity" "$TARGET/$PROJECT_CLI_DIR/agent-parity.cmd" "$TARGET/$PROJECT_CLI_DIR/agent-parity.ps1"
rmdir "$TARGET/$PROJECT_CLI_DIR" 2>/dev/null || true
uninstall_skills
rm -rf "$TARGET/$SERVER_DIR"
rmdir "$TARGET/.agents/mcp" 2>/dev/null || true
echo "removed: $SERVER_DIR"
ag="$TARGET/AGENTS.md"
ag_state=$(managed_block_state "$ag" "$MARK_BEGIN" "$MARK_END")
if [ "$ag_state" = valid ]; then
  make_local_temp_for "$ag"
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    { line = $0; sub(/\r$/, "", line) }
    line == b { inblock = 1; next }
    line == e { inblock = 0; next }
    !inblock { print }
  ' "$ag" > "$LOCAL_TEMP_FILE"
  commit_local_temp "$ag"
  echo "AGENTS.md: removed memory instruction block"
elif [ "$ag_state" = invalid ]; then
  echo "AGENTS.md: agent-parity markers are incomplete, duplicated, or out of order; file left unchanged -- repair the markers manually"
elif [ -e "$ag" ] && grep -q "memory MCP server" "$ag" 2>/dev/null; then
  echo "AGENTS.md: has a memory block without markers -- remove it manually"
fi
ga="$TARGET/.gitattributes"
ga_state=$(managed_block_state "$ga" "$GI_BEGIN" "$GI_END")
if [ "$ga_state" = valid ]; then
  strip_gitattributes_block
  [ -s "$TARGET/.gitattributes" ] || rm -f "$TARGET/.gitattributes"
  echo ".gitattributes: removed agent-parity block"
elif [ "$ga_state" = invalid ]; then
  echo ".gitattributes: agent-parity markers are incomplete, duplicated, or out of order; file left unchanged -- repair the markers manually"
fi
if in_git_repo; then
  git -C "$TARGET" config --remove-section merge.agent-parity-memory 2>/dev/null || true
fi
gi="$TARGET/.gitignore"
gi_state=$(managed_block_state "$gi" "$GI_BEGIN" "$GI_END")
if [ "$gi_state" = valid ]; then
  strip_gitignore_block
  echo ".gitignore: removed agent-parity block"
elif [ "$gi_state" = invalid ]; then
  echo ".gitignore: agent-parity markers are incomplete, duplicated, or out of order; file left unchanged -- repair the markers manually"
fi
if [ "$PURGE" = "yes" ]; then
  rm -rf "$TARGET/$STORE_DIR"
  echo "memory store: deleted ($TARGET/$STORE_DIR)"
else
  echo "memory store: kept at $TARGET/$STORE_DIR (pass --purge to delete it)"
fi
rm -f "$SCRIPT_DIR/common.sh" "$SCRIPT_DIR/status.sh" "$SCRIPT_DIR/version.sh" "$SCRIPT_DIR/uninstall.sh" "$SCRIPT_DIR/sync-claude.sh" "$SCRIPT_DIR/self-heal.sh" "$SCRIPT_DIR/merge-memory.sh"
rm -f "$SCRIPT_DIR/common.ps1" "$SCRIPT_DIR/status.ps1" "$SCRIPT_DIR/version.ps1" "$SCRIPT_DIR/uninstall.ps1" "$SCRIPT_DIR/sync-claude.ps1" "$SCRIPT_DIR/self-heal.ps1"
rmdir "$SCRIPT_DIR" 2>/dev/null || true
