#!/usr/bin/env sh
# Shared shell functions for project-local agent-parity commands.
set -eu

REPO="libkim/agent-parity"
SERVER_DIR=".agents/mcp/memory"
STORE_DIR=".agents/memory"
PROJECT_CLI_DIR=".agents/bin"
SYNC_SCRIPT=".agents/scripts/sync-claude.sh"
CLAUDE_SRC=".agents/claude/settings.json"
CLAUDE_TGT=".claude/settings.json"
# SessionStart runs through the project-local launcher. Claude chooses the host
# shell; the launcher absorbs the Unix/Windows difference.
CLAUDE_HOOK='.agents/bin/agent-parity sync-claude'
MARK_BEGIN="<!-- agent-parity:begin -->"
MARK_END="<!-- agent-parity:end -->"
GI_BEGIN="# agent-parity:begin"
GI_END="# agent-parity:end"
# Everything install may create at the target's top level. gitignore syncing
# and the status report both derive from this one list.
ARTIFACTS=".mcp.json .cursor .codex .agents AGENTS.md CLAUDE.md"
# Cursor CLI reads .cursor/cli.json for tool permissions. We ship it verbatim
# (not a memory-server merge), so it is wired on its own, outside for_each_config.
CURSOR_CLI=".cursor/cli.json"
# Instruction files only one of the four agents reads. They split behavior, so
# install and status call them out; they belong to the user, so never touched.
PARITY_BREAKERS=".cursorrules:Cursor"

LOCAL_TEMP_FILE=""

cleanup_local_temp() {
  [ -z "$LOCAL_TEMP_FILE" ] || rm -f "$LOCAL_TEMP_FILE"
  LOCAL_TEMP_FILE=""
}

trap cleanup_local_temp EXIT
trap 'cleanup_local_temp; exit 1' HUP INT TERM

make_local_temp_for() {
  local_target=$1
  local_dir=$(dirname "$local_target")
  local_base=$(basename "$local_target")
  LOCAL_TEMP_FILE=$(mktemp "$local_dir/.${local_base}.agent-parity.XXXXXX")
  if [ -e "$local_target" ]; then
    local_mode=$(stat -c '%a' "$local_target" 2>/dev/null || stat -f '%Lp' "$local_target" 2>/dev/null || true)
    [ -z "$local_mode" ] || chmod "$local_mode" "$LOCAL_TEMP_FILE"
  fi
}

commit_local_temp() {
  local_target=$1
  mv "$LOCAL_TEMP_FILE" "$local_target"
  LOCAL_TEMP_FILE=""
}

is_claude_wrapper() {
  wrapper=$(cat "$1")
  cr=$(printf '\r')
  [ "${wrapper%$cr}" = "@AGENTS.md" ]
}


platform() {
  case "$(uname -s)" in
    Linux) goos=linux ;;
    Darwin) goos=darwin ;;
    *) echo "unsupported OS: $(uname -s) (on native Windows, use install.ps1)" >&2; exit 1 ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) goarch=amd64 ;;
    aarch64 | arm64) goarch=arm64 ;;
    *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
  esac
  BIN="memory-mcp-${goos}-${goarch}"
}

local_config_editor_path() {
  if [ -n "${AGENT_PARITY_CONFIG_EDITOR:-}" ]; then
    printf '%s\n' "$AGENT_PARITY_CONFIG_EDITOR"
    return
  fi
  version_file="$TARGET/$SERVER_DIR/VERSION"
  [ -f "$version_file" ] || return 1
  editor_version=$(tr -d '\r\n' < "$version_file")
  cache_root=${AGENT_PARITY_CACHE:-${XDG_CACHE_HOME:-${HOME:?HOME is not set}/.cache}/agent-parity}
  printf '%s\n' "$cache_root/config/$editor_version/agent-parity-config-${goos}-${goarch}"
}

# Calls "$1 <path relative to target> <template in repo> <registered-marker>"
# once per wiring file. install/uninstall/status all derive from this single
# list. CLAUDE.md is wiring too: Claude Code reads CLAUDE.md, not AGENTS.md,
# so the instruction block only reaches it through this import wrapper.
for_each_config() {
  "$1" ".mcp.json"               templates/claude.mcp.json              ".agents/mcp/memory/run.sh"
  "$1" ".cursor/mcp.json"        templates/cursor.mcp.json              ".agents/mcp/memory/run.sh"
  "$1" ".codex/config.toml"      templates/codex.config.toml            ".agents/mcp/memory/run.sh"
  "$1" ".agents/mcp_config.json" templates/antigravity.mcp_config.json  ".agents/mcp/memory/run.sh"
  "$1" "CLAUDE.md"               templates/CLAUDE.md                    "@AGENTS.md"
}

installed_version() {
  version_file="$TARGET/$SERVER_DIR/VERSION"
  [ -f "$version_file" ] || { echo "missing"; return; }
  tr -d '\r\n' < "$version_file"
}

latest_version() {
  # The /releases/latest redirect lands on .../releases/tag/<version>.
  u=$(curl --connect-timeout 3 --max-time 5 -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null) || { echo "unknown (network unavailable)"; return; }
  case "$u" in
    */tag/*) echo "${u##*/}" ;;
    *) echo "unknown (network unavailable)" ;;
  esac
}

newer_version_available() {
  installed=${1#v}
  latest=${2#v}
  awk -v installed="$installed" -v latest="$latest" '
    BEGIN {
      ni = split(installed, i, ".")
      nl = split(latest, l, ".")
      if (ni != 3 || nl != 3) exit 1
      for (n = 1; n <= 3; n++) {
        if (i[n] !~ /^[0-9]+$/ || l[n] !~ /^[0-9]+$/) exit 1
        if ((l[n] + 0) > (i[n] + 0)) exit 0
        if ((l[n] + 0) < (i[n] + 0)) exit 1
      }
      exit 1
    }
  '
}

show_update_notice() {
  installed=$1
  latest=$2
  newer_version_available "$installed" "$latest" || return 0
  echo
  echo "update available: $installed -> $latest"
  echo "run from the project root: ./.agents/bin/agent-parity update"
}

require_local_config_editor() {
	CONFIG_EDITOR=$(local_config_editor_path) || { echo "cannot resolve local config editor path" >&2; exit 1; }
	[ -x "$CONFIG_EDITOR" ] || { echo "missing local config editor: $CONFIG_EDITOR" >&2; exit 1; }
}


unreg_cursor_cli() {
  t="$TARGET/$CURSOR_CLI"
  [ -e "$t" ] || return 0
  result=$("$CONFIG_EDITOR" unmerge-cursor-cli "$t")
  if [ "$result" = changed ]; then
    rmdir "$(dirname "$t")" 2>/dev/null || true
    echo "  unmerged:      $CURSOR_CLI (removed memory allowlist entry, kept the rest)"
  else
    echo "  unchanged:     $CURSOR_CLI (memory allowlist entry not present)"
  fi
}

unreg_agent_hooks() {
  "$CONFIG_EDITOR" unmerge-hook "$TARGET/$CLAUDE_SRC" claude >/dev/null
  "$CONFIG_EDITOR" unmerge-hook "$TARGET/$CLAUDE_TGT" claude >/dev/null
  "$CONFIG_EDITOR" unmerge-hook "$TARGET/.codex/hooks.json" codex >/dev/null
  "$CONFIG_EDITOR" unmerge-hook "$TARGET/.cursor/hooks.json" cursor >/dev/null
  "$CONFIG_EDITOR" unmerge-hook "$TARGET/.agents/hooks.json" antigravity >/dev/null
  echo "  hooks:      removed agent-parity self-heal handlers"
}

in_git_repo() {
  command -v git >/dev/null 2>&1 && git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

ignored_artifacts() {
  for p in $ARTIFACTS; do
    [ -e "$TARGET/$p" ] || continue
    git -C "$TARGET" check-ignore -q -- "$p" 2>/dev/null && echo "$p"
  done
}

strip_gitignore_block() {
  gi="$TARGET/.gitignore"
  [ -e "$gi" ] || return 0
  grep -qF "$GI_BEGIN" "$gi" 2>/dev/null && grep -qF "$GI_END" "$gi" 2>/dev/null || return 0
  make_local_temp_for "$gi"
  awk -v b="$GI_BEGIN" -v e="$GI_END" '
    { line = $0; sub(/\r$/, "", line) }
    line == b { inblock = 1; next }
    line == e { inblock = 0; next }
    !inblock { print }
  ' "$gi" > "$LOCAL_TEMP_FILE"
  commit_local_temp "$gi"
}

# The vendored files must stay git-tracked to reach other machines through
# git. Where the project's .gitignore hides any of them, keep a marked block
# of un-ignore rules; recompute it from scratch each run so it stays minimal.

uninstall_skills() {
  s="$TARGET/$SYNC_SCRIPT"
  # Strip our settings keys even when a partial installation has already lost
  # its sync script.
  for f in "$CLAUDE_TGT" "$CLAUDE_SRC"; do
    [ -e "$TARGET/$f" ] || continue
    "$CONFIG_EDITOR" unmerge-claude-settings "$TARGET/$f" >/dev/null
  done
  # The agent-parity skill is our wiring, not a user skill, so remove both the
  # source and Claude's synced copy before deciding whether a static copy of
  # real user skills is worth keeping below.
  rm -rf "$TARGET/.agents/skills/agent-parity" "$TARGET/.claude/skills/agent-parity"
  if [ -n "$(ls -A "$TARGET/.claude/skills" 2>/dev/null | grep -v '^\.gitkeep$')" ]; then
    # Claude Code reads only this copy, so removing it with the wiring would
    # take Claude's skills away while every other agent keeps the source.
    echo "skills: left .claude/skills as a static copy for Claude Code (no longer auto-synced)"
  else
    rm -rf "$TARGET/.claude/skills"
  fi
  rm -f "$s"
  rmdir "$TARGET/.agents/claude" "$TARGET/.agents/scripts" "$TARGET/.claude" 2>/dev/null || true
  echo "skills: removed sync wiring"
  if [ -z "$(ls -A "$TARGET/.agents/skills" 2>/dev/null | grep -v '^\.gitkeep$')" ]; then
    rm -rf "$TARGET/.agents/skills"
    echo "skills: removed empty .agents/skills"
  else
    echo "skills: kept .agents/skills (your skills live there)"
  fi
  rmdir "$TARGET/.agents" 2>/dev/null || true
}

warn_parity() {
  for pair in $PARITY_BREAKERS; do
    f="${pair%%:*}"
    who=$(echo "${pair##*:}" | tr '_' ' ')
    if [ -e "$TARGET/$f" ]; then
      echo "parity: $f exists -- only $who reads it, so agents diverge; fold it into AGENTS.md"
    fi
  done
}

status_skills() {
  if [ ! -e "$TARGET/$SYNC_SCRIPT" ]; then
    echo "skills: sync wiring missing"
    return 0
  fi
  n=$(ls "$TARGET/.agents/skills" 2>/dev/null | grep -cvE '^(\.gitkeep|agent-parity)$' || true)
  echo "skills: $n in .agents/skills; sync script present"
  if [ -e "$TARGET/.agents/skills/agent-parity/SKILL.md" ]; then
    echo "  management skill: present"
  else
    echo "  management skill: missing"
  fi
  CONFIG_EDITOR=$(local_config_editor_path) || CONFIG_EDITOR=""
  if [ -x "$CONFIG_EDITOR" ] && "$CONFIG_EDITOR" has-sync-hook "$TARGET/$CLAUDE_SRC" "$CLAUDE_HOOK" 2>/dev/null; then
    echo "  hook: registered ($CLAUDE_SRC)"
  elif [ -x "$CONFIG_EDITOR" ] && "$CONFIG_EDITOR" has-sync-hook "$TARGET/$CLAUDE_TGT" "$CLAUDE_HOOK" 2>/dev/null; then
    echo "  hook: registered ($CLAUDE_TGT)"
  elif [ ! -x "$CONFIG_EDITOR" ]; then
    echo "  hook: unknown (local config editor missing)"
  else
    echo "  hook: missing -- Claude Code will not auto-sync skills"
  fi
}

status_codex_mcp() {
  command -v codex >/dev/null 2>&1 || {
    echo "codex mcp: codex CLI not found"
    return 0
  }
  out=$(cd "$TARGET" && codex mcp get memory 2>&1) || {
    echo "codex mcp: memory not registered/enabled for this project"
    printf '%s\n' "$out" | sed 's/^/  /'
    return 0
  }
  if printf '%s\n' "$out" | grep -q 'enabled: true'; then
    echo "codex mcp: memory registered/enabled"
  else
    echo "codex mcp: memory found but not enabled"
  fi
  if printf '%s\n' "$out" | grep -qF "$SERVER_DIR/run.sh"; then
    echo "  command: $SERVER_DIR/run.sh"
  else
    echo "  command: check with 'codex mcp get memory'"
  fi
  echo "  note: Codex loads MCP tools when a session starts; restart the agent session if memory_recent/memory_add are not visible."
}

# Append the marked instruction block, or rewrite exactly the marked region
# when it is already there, leaving the rest of the file untouched.

unreg_config() {
  t="$TARGET/$1"
  [ -e "$t" ] || return 0
  if [ "$1" = "CLAUDE.md" ]; then
    if is_claude_wrapper "$t"; then
      rm "$t"
      echo "  removed:       $1"
    fi
    # The @AGENTS.md import may carry the user's own AGENTS.md content too,
    # so a CLAUDE.md we did not write verbatim is left alone.
    return 0
  elif [ "$3" = ".agents/mcp/memory/run.sh" ]; then
    result=$("$CONFIG_EDITOR" unmerge "$t" 2>/dev/null) || result=invalid
    if [ "$result" = changed ]; then
      echo "  unmerged:      $1 (removed memory server entry, kept the rest)"
    elif [ "$result" = invalid ]; then
      echo "  edit manually: $1 -- invalid JSON/TOML"
    fi
  fi
}



status_agent_config() {
  label=$1
  rel=$2
  marker=$3
  t="$TARGET/$rel"
  if [ ! -e "$t" ]; then
    echo "  $label: config missing ($rel)"
  elif [ "$marker" = ".agents/mcp/memory/run.sh" ]; then
    CONFIG_EDITOR=$(local_config_editor_path) || CONFIG_EDITOR=""
    if [ ! -x "$CONFIG_EDITOR" ]; then
      echo "  $label: unknown (local config editor missing)"
      return
    fi
    command=$("$CONFIG_EDITOR" command "$t" 2>/dev/null) || code=$?
    code=${code:-0}
    if [ "$code" -eq 0 ] && [ "$command" = "$marker" ]; then
      echo "  $label: registered ($rel)"
    elif [ "$code" -eq 0 ] && [ "$command" = ".agents/mcp/memory/run.cmd" ]; then
      echo "  $label: registered for Windows ($rel; self-heal will retarget it when the next session starts)"
    elif [ "$code" -eq 0 ]; then
      echo "  $label: points elsewhere ($rel has a memory entry not using $SERVER_DIR)"
    elif [ "$code" -eq 1 ]; then
      echo "  $label: not registered ($rel)"
    else
      echo "  $label: invalid JSON/TOML ($rel)"
    fi
    unset code command
  elif [ "$rel" = "CLAUDE.md" ]; then
    if is_claude_wrapper "$t"; then
      echo "  $label: registered ($rel)"
    else
      echo "  $label: not registered ($rel)"
    fi
  else
    echo "  $label: not registered ($rel)"
  fi
}

status_mcp_registrations() {
  echo "mcp registrations:"
  status_agent_config "Claude Code"      ".mcp.json"               ".agents/mcp/memory/run.sh"
  status_agent_config "Cursor"           ".cursor/mcp.json"        ".agents/mcp/memory/run.sh"
  status_agent_config "Codex"            ".codex/config.toml"      ".agents/mcp/memory/run.sh"
  status_agent_config "Antigravity CLI"  ".agents/mcp_config.json" ".agents/mcp/memory/run.sh"
  status_agent_config "Claude wrapper"   "CLAUDE.md"               "@AGENTS.md"
}

status_agent_hooks() {
  echo "self-heal hooks:"
  CONFIG_EDITOR=$(local_config_editor_path) || CONFIG_EDITOR=""
  for spec in "$CLAUDE_SRC:claude" ".codex/hooks.json:codex" ".cursor/hooks.json:cursor" ".agents/hooks.json:antigravity"; do
    rel=${spec%%:*}
    kind=${spec##*:}
    if [ ! -x "$CONFIG_EDITOR" ]; then
      echo "  $kind: unknown (local config editor missing)"
    elif "$CONFIG_EDITOR" has-agent-hook "$TARGET/$rel" "$kind" 2>/dev/null; then
      echo "  $kind: registered ($rel)"
    else
      echo "  $kind: missing ($rel)"
    fi
  done
  echo "  note: Codex project hooks must be reviewed and trusted before they run"
}

status_agent_diagnostics() {
  echo "agent-specific diagnostics:"
  if command -v claude >/dev/null 2>&1; then
    echo "  Claude Code: CLI found; no noninteractive MCP tool-visibility check implemented"
    echo "    check inside Claude Code with /mcp if memory tools are not visible."
  else
    echo "  Claude Code: CLI not found"
  fi
  if command -v cursor >/dev/null 2>&1; then
    echo "  Cursor: CLI found; no noninteractive MCP tool-visibility check implemented"
  else
    echo "  Cursor: CLI not found"
  fi
  first=yes
  status_codex_mcp | while IFS= read -r line; do
    if [ "$first" = yes ]; then
      echo "  Codex: $line"
      first=no
    else
      echo "         $line"
    fi
  done
  if command -v antigravity >/dev/null 2>&1; then
    echo "  Antigravity CLI: CLI found; no noninteractive MCP tool-visibility check implemented"
  else
    echo "  Antigravity CLI: CLI not found"
  fi
}
