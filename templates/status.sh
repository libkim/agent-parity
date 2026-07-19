#!/usr/bin/env sh
set -eu
[ "$#" -eq 0 ] || { echo "usage: agent-parity status" >&2; exit 2; }
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TARGET=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
. "$SCRIPT_DIR/common.sh"
platform

echo "target: $TARGET"
installed=$(installed_version)
if [ "$installed" != missing ] && [ -f "$TARGET/$SERVER_DIR/RELEASE" ]; then
  echo "server: $installed (shared cache, downloaded on demand)"
else
  installed="missing"
  echo "server: missing (expected $SERVER_DIR/VERSION and RELEASE)"
fi
if [ -x "$TARGET/$SERVER_DIR/run.sh" ]; then echo "launcher: ok"; else echo "launcher: missing"; fi
latest=$(latest_version)
echo "latest release: $latest"
show_update_notice "$installed" "$latest"
status_mcp_registrations
status_agent_hooks
status_agent_diagnostics
status_skills
cli="$TARGET/$CURSOR_CLI"
CONFIG_EDITOR=$(local_config_editor_path) || CONFIG_EDITOR=""
if [ ! -e "$cli" ]; then
  echo "cursor cli: allowlist missing ($CURSOR_CLI)"
elif [ ! -x "$CONFIG_EDITOR" ]; then
  echo "cursor cli: unknown (local config editor missing)"
elif "$CONFIG_EDITOR" has-cursor-cli "$cli" 2>/dev/null; then
  echo "cursor cli: memory allowlist present ($CURSOR_CLI)"
else
  echo "cursor cli: $CURSOR_CLI exists but is not ours (memory allowlist not confirmed)"
fi
ag="$TARGET/AGENTS.md"
if [ -e "$ag" ] && grep -qF "$MARK_BEGIN" "$ag" 2>/dev/null && grep -qF "$MARK_END" "$ag" 2>/dev/null; then
  echo "AGENTS.md: memory block present"
else
  echo "AGENTS.md: memory block missing"
fi
if [ -d "$TARGET/$STORE_DIR" ]; then
  n=$(find "$TARGET/$STORE_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  echo "memory store: $n entries ($TARGET/$STORE_DIR)"
else
  echo "memory store: missing ($TARGET/$STORE_DIR)"
fi
if in_git_repo; then
  ign=$(ignored_artifacts | tr '\n' ' ')
  if [ -n "$ign" ]; then echo "git: IGNORED and will not sync via git: $ign(run install or update to fix)"; else echo "git: all artifacts tracked"; fi
fi
warn_parity
