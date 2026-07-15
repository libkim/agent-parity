#!/usr/bin/env sh
# agent-parity: set up a cross-agent environment inside a target project —
# a shared memory MCP server plus cross-agent skills, wired so Claude Code,
# Codex, Cursor, and Antigravity CLI behave identically.
#
#   curl -fsSL https://raw.githubusercontent.com/libkim/agent-parity/main/install.sh | sh -s -- install [dir]
#
# Commands: install, update, uninstall [--purge], status, version.
# [dir] is the target project and defaults to the current directory.
set -eu

REPO="libkim/agent-parity"
# Overridable for forks and local testing (file:// URLs work).
RAW="${AGENT_PARITY_RAW:-https://raw.githubusercontent.com/$REPO/main}"
RELEASE="${AGENT_PARITY_RELEASE:-https://github.com/$REPO/releases/latest/download}"
SERVER_DIR=".agents/mcp/memory"
STORE_DIR=".agents/memory"
PROJECT_CLI_DIR=".agents/bin"
SYNC_SCRIPT=".agents/scripts/sync-claude.sh"
CLAUDE_SRC=".agents/claude/settings.json"
CLAUDE_TGT=".claude/settings.json"
# SessionStart command merged into the settings; $CLAUDE_PROJECT_DIR stays
# literal for Claude to expand, so single-quote it.
CLAUDE_HOOK='bash "$CLAUDE_PROJECT_DIR/.agents/scripts/sync-claude.sh" sync'
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

usage() {
  cat >&2 <<'EOF'
usage: agent-parity <command> [dir] [--purge]

  install   [dir]  install the memory server, register agent configs, wire
                   cross-agent skills, create the store
  uninstall [dir]  remove the server, registrations, and skill wiring; keeps
                   the memory store and your skills unless --purge is given
  update    [dir]  refresh the launcher, binary, and managed blocks
  status    [dir]  show what is installed, registered, and stored
  version   [dir]  print installed and latest release versions

[dir] is the target project and defaults to the current directory.

Bootstrap once with:
  curl -fsSL https://raw.githubusercontent.com/libkim/agent-parity/main/install.sh | sh -s -- install

After that, use:
  ./.agents/bin/agent-parity status
  ./.agents/bin/agent-parity update
EOF
  exit 2
}

fetch() { curl -fsSL "$RAW/$1"; }

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
  b="$TARGET/$SERVER_DIR/dist/$BIN"
  [ -x "$b" ] || { echo "missing"; return; }
  "$b" -version 2>/dev/null || echo "unknown (pre-versioning build)"
}

latest_version() {
  # The /releases/latest redirect lands on .../releases/tag/<version>.
  u=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null) || { echo "unknown"; return; }
  case "$u" in
    */tag/*) echo "${u##*/}" ;;
    *) echo "unknown" ;;
  esac
}

# Pin scripts, templates, and binaries to the latest release tag so the whole
# environment installs and updates as one version, not a mix of rolling main
# and a released binary. Falls back to main when no release is found or when
# AGENT_PARITY_RAW / AGENT_PARITY_RELEASE are set for development.
if [ -z "${AGENT_PARITY_RAW:-}" ] || [ -z "${AGENT_PARITY_RELEASE:-}" ]; then
  PINNED_TAG=$(latest_version)
  case "$PINNED_TAG" in
    v*)
      [ -n "${AGENT_PARITY_RAW:-}" ]     || RAW="https://raw.githubusercontent.com/$REPO/$PINNED_TAG"
      [ -n "${AGENT_PARITY_RELEASE:-}" ] || RELEASE="https://github.com/$REPO/releases/download/$PINNED_TAG"
      ;;
  esac
fi

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

install_project_cli() {
  d="$TARGET/$PROJECT_CLI_DIR"
  mkdir -p "$d"
  fetch templates/project-agent-parity.sh > "$d/agent-parity"
  chmod +x "$d/agent-parity"
  fetch templates/project-agent-parity.cmd > "$d/agent-parity.cmd" 2>/dev/null || true
  fetch templates/project-agent-parity.ps1 > "$d/agent-parity.ps1" 2>/dev/null || true
  echo "cli: wrote $PROJECT_CLI_DIR/agent-parity"
}

# All release binaries are fetched, not just this machine's: the vendored
# model promises that a git pull alone makes any machine work, so every
# platform a teammate or device might run must already be in the repo.
ALL_BINS="memory-mcp-linux-amd64 memory-mcp-linux-arm64 memory-mcp-darwin-amd64 memory-mcp-darwin-arm64 memory-mcp-windows-amd64.exe"

download_server() {
  dest="$TARGET/$SERVER_DIR"
  mkdir -p "$dest/dist"
  fetch run.sh > "$dest/run.sh"; chmod +x "$dest/run.sh"
  fetch run.cmd > "$dest/run.cmd" 2>/dev/null || true
  echo "downloading server binaries (all platforms) ..."
  for b in $ALL_BINS; do
    curl -fsSL "$RELEASE/$b" -o "$dest/dist/$b"
    chmod +x "$dest/dist/$b"
  done
}

reg_config() {
  t="$TARGET/$1"
  c=$(fetch "$2")
  if [ ! -e "$t" ]; then
    mkdir -p "$(dirname "$t")"
    printf '%s\n' "$c" > "$t"
    echo "  wrote:      $1"
  elif grep -qF "$3" "$t" 2>/dev/null; then
    echo "  registered: $1 (already)"
  elif [ "$3" = ".agents/mcp/memory/run.sh" ] && grep -qF ".agents/mcp/memory/run.cmd" "$t" 2>/dev/null; then
    tmp="$t.agent-parity.tmp"
    sed 's|.agents/mcp/memory/run.cmd|.agents/mcp/memory/run.sh|g' "$t" > "$tmp" && mv "$tmp" "$t"
    echo "  retargeted: $1 (Windows launcher -> Unix launcher)"
  elif [ "$3" = ".agents/mcp/memory/run.sh" ] && "$TARGET/$SERVER_DIR/dist/$BIN" -has-memory-config "$t" 2>/dev/null; then
    echo "  exists:     $1 — its memory entry points at a different server; replace it with:"
    printf '%s\n' "$c" | sed 's/^/    | /'
  elif [ "$3" = ".agents/mcp/memory/run.sh" ] && "$TARGET/$SERVER_DIR/dist/$BIN" -merge-config "$t" -command "$3" 2>/dev/null; then
    echo "  merged:     $1 (added memory server entry)"
  else
    echo "  exists:     $1 — merge this in:"
    printf '%s\n' "$c" | sed 's/^/    | /'
  fi
}

# Cursor CLI permission allowlist: a verbatim file we own outright. Write it
# when absent; if a different cli.json already exists it is the user's, so leave
# it and print the snippet to merge. update re-runs this and is idempotent.
reg_cursor_cli() {
  t="$TARGET/$CURSOR_CLI"
  c=$(fetch templates/cursor.cli.json)
  if [ ! -e "$t" ]; then
    mkdir -p "$(dirname "$t")"
    printf '%s\n' "$c" > "$t"
    echo "  wrote:      $CURSOR_CLI"
  elif [ "$(cat "$t")" = "$c" ]; then
    echo "  registered: $CURSOR_CLI (already)"
  else
    echo "  exists:     $CURSOR_CLI — merge this in:"
    printf '%s\n' "$c" | sed 's/^/    | /'
  fi
}

# Remove the Cursor CLI allowlist only when it is byte-identical to ours; a
# file the user changed is left in place.
unreg_cursor_cli() {
  t="$TARGET/$CURSOR_CLI"
  [ -e "$t" ] || return 0
  c=$(fetch templates/cursor.cli.json)
  if [ "$(cat "$t")" = "$c" ]; then
    rm "$t"
    rmdir "$(dirname "$t")" 2>/dev/null || true
    echo "  removed:       $CURSOR_CLI"
  else
    echo "  edit manually: $CURSOR_CLI — remove our memory allowlist entry"
  fi
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
  tmp="$gi.agent-parity.tmp"
  awk -v b="$GI_BEGIN" -v e="$GI_END" '
    $0 == b { inblock = 1; next }
    $0 == e { inblock = 0; next }
    !inblock { print }
  ' "$gi" > "$tmp" && mv "$tmp" "$gi"
}

# The vendored files must stay git-tracked to reach other machines through
# git. Where the project's .gitignore hides any of them, keep a marked block
# of un-ignore rules; recompute it from scratch each run so it stays minimal.
sync_gitignore() {
  in_git_repo || return 0
  strip_gitignore_block
  rules=""
  for p in $(ignored_artifacts); do
    if [ -d "$TARGET/$p" ]; then rules="$rules!/$p/
"; else rules="$rules!/$p
"; fi
  done
  # .claude is regenerated from .agents each session; keep it out of git so
  # the generated copy never competes with its source.
  if [ -e "$TARGET/$SYNC_SCRIPT" ] && ! git -C "$TARGET" check-ignore -q -- .claude 2>/dev/null; then
    rules="$rules/.claude/
"
  fi
  [ -n "$rules" ] || return 0
  gi="$TARGET/.gitignore"
  [ -s "$gi" ] && [ -n "$(tail -c1 "$gi")" ] && echo >> "$gi"
  {
    echo "$GI_BEGIN"
    printf '%s' "$rules"
    echo "$GI_END"
  } >> "$gi"
  echo ".gitignore: updated managed block:"
  printf '%s' "$rules" | sed 's/^/  /'
}

# Cross-agent skills: .agents/skills/ is the shared source that Codex, Cursor,
# and Antigravity CLI read natively. Claude Code does not, so a SessionStart
# hook mirrors it into .claude/skills each session — an internal shim that
# keeps surface behavior identical across agents.
# Pre-existing per-agent skills (.claude, .codex, .cursor) are moved into the
# shared source: Claude's must move or the sync would destroy them, and Codex's
# and Cursor's would otherwise stay invisible to the other agents. Skills are
# self-contained folders, so the move is mechanical and safe — unlike
# instruction prose, which is only ever reported.
adopt_agent_skills() {
  for pair in .claude/skills:claude .codex/skills:codex .cursor/skills:cursor; do
    dir=${pair%%:*}; label=${pair##*:}
    [ -d "$TARGET/$dir" ] || continue
    for d in "$TARGET/$dir"/*/; do
      [ -d "$d" ] || continue
      name=$(basename "$d")
      if [ ! -e "$TARGET/.agents/skills/$name" ]; then
        mv "$d" "$TARGET/.agents/skills/$name"
        echo "  adopted:    $dir/$name -> .agents/skills/$name (now shared by all agents)"
      elif ! diff -qr "$TARGET/.agents/skills/$name" "$d" >/dev/null 2>&1; then
        mv "$d" "$TARGET/.agents/skills/$name.from-$label"
        echo "  conflict:   $dir/$name differs from the shared one — saved as .agents/skills/$name.from-$label, merge manually"
      fi
    done
  done
}

install_skills() {
  echo "skills:"
  mkdir -p "$TARGET/.agents/skills"
  adopt_agent_skills
  [ -n "$(ls -A "$TARGET/.agents/skills" 2>/dev/null)" ] || : > "$TARGET/.agents/skills/.gitkeep"
  # sync-claude.sh is a generated shim we own outright (like run.sh), so
  # overwrite it every run to keep it current — user skills live in
  # .agents/skills, never here.
  s="$TARGET/$SYNC_SCRIPT"
  mkdir -p "$(dirname "$s")"
  fetch templates/sync-claude.sh > "$s"
  chmod +x "$s"
  echo "  wrote:      $SYNC_SCRIPT"
  # Merge our keys into the settings source, preserving any the user set. If only
  # the generated .claude copy exists, seed the source from it first so nothing
  # there is lost when sync regenerates the copy.
  src="$TARGET/$CLAUDE_SRC"
  mkdir -p "$(dirname "$src")"
  if [ ! -e "$src" ] && [ -e "$TARGET/$CLAUDE_TGT" ]; then
    cp "$TARGET/$CLAUDE_TGT" "$src"
    echo "  migrated:   $CLAUDE_TGT -> $CLAUDE_SRC"
  fi
  if "$TARGET/$SERVER_DIR/dist/$BIN" -merge-claude-settings "$src" -hook-command "$CLAUDE_HOOK"; then
    echo "  merged:     $CLAUDE_SRC (memory keys + sync hook)"
  else
    echo "  warn:       could not merge $CLAUDE_SRC" >&2
  fi
  bash "$TARGET/$SYNC_SCRIPT" sync 2>&1 | sed 's/^/  /'
}

uninstall_skills() {
  s="$TARGET/$SYNC_SCRIPT"
  [ -e "$s" ] || return 0
  tpl=$(fetch templates/sync-claude.sh)
  if [ "$(cat "$s")" != "$tpl" ]; then
    echo "skills: $SYNC_SCRIPT differs from the packaged one — wiring left alone"
    return 0
  fi
  if [ -n "$(ls -A "$TARGET/.claude/skills" 2>/dev/null | grep -v '^\.gitkeep$')" ]; then
    # Claude Code reads only this copy, so removing it with the wiring would
    # take Claude's skills away while every other agent keeps the source.
    echo "skills: left .claude/skills as a static copy for Claude Code (no longer auto-synced)"
  else
    rm -rf "$TARGET/.claude/skills"
  fi
  # Strip our keys from the settings; the file is deleted if nothing else remains.
  for f in "$CLAUDE_TGT" "$CLAUDE_SRC"; do
    [ -e "$TARGET/$f" ] || continue
    "$TARGET/$SERVER_DIR/dist/$BIN" -unmerge-claude-settings "$TARGET/$f" 2>/dev/null || true
  done
  rm "$s"
  rmdir "$TARGET/.agents/claude" "$TARGET/.agents/scripts" "$TARGET/.claude" 2>/dev/null || true
  echo "skills: removed sync wiring"
  if [ "$(ls -A "$TARGET/.agents/skills" 2>/dev/null)" = ".gitkeep" ]; then
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
      echo "parity: $f exists — only $who reads it, so agents diverge; fold it into AGENTS.md"
    fi
  done
}

status_skills() {
  if [ ! -e "$TARGET/$SYNC_SCRIPT" ]; then
    echo "skills: sync wiring missing"
    return 0
  fi
  n=$(ls "$TARGET/.agents/skills" 2>/dev/null | grep -cv '^\.gitkeep$' || true)
  echo "skills: $n in .agents/skills; sync script present"
  if grep -q "sync-claude.sh" "$TARGET/$CLAUDE_SRC" 2>/dev/null; then
    echo "  hook: registered ($CLAUDE_SRC)"
  elif grep -q "sync-claude.sh" "$TARGET/$CLAUDE_TGT" 2>/dev/null; then
    echo "  hook: registered ($CLAUDE_TGT)"
  else
    echo "  hook: missing — Claude Code will not auto-sync skills"
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
sync_agents_block() {
  ag="$TARGET/AGENTS.md"
  snip=$(fetch templates/AGENTS.snippet.md)
  if [ -e "$ag" ] && grep -qF "$MARK_BEGIN" "$ag" 2>/dev/null && grep -qF "$MARK_END" "$ag" 2>/dev/null; then
    cur=$(awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
      $0 == b { inblock = 1 } inblock { print } $0 == e { exit }
    ' "$ag")
    if [ "$cur" = "$snip" ]; then
      echo "AGENTS.md: memory block up to date"
      return
    fi
    tmp="$ag.agent-parity.tmp"
    printf '%s\n' "$snip" | awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
      NR == FNR { new[FNR] = $0; n = FNR; next }
      $0 == b { for (i = 1; i <= n; i++) print new[i]; inblock = 1; next }
      $0 == e { inblock = 0; next }
      !inblock { print }
    ' - "$ag" > "$tmp" && mv "$tmp" "$ag"
    echo "AGENTS.md: refreshed memory instruction block"
  else
    if [ -e "$ag" ] && grep -qE "memory_(recent|add|search|get)" "$ag" 2>/dev/null; then
      echo "AGENTS.md: note — existing text already mentions the memory tools; check it against the appended block for duplication"
    fi
    { printf '\n%s\n' "$snip"; } >> "$ag"
    echo "AGENTS.md: appended memory instruction block"
  fi
}

cmd_install() {
  mkdir -p "$TARGET/$SERVER_DIR" "$TARGET/$STORE_DIR"
  download_server
  install_project_cli
  echo "configs:"
  for_each_config reg_config
  reg_cursor_cli
  install_skills
  sync_agents_block
  sync_gitignore
  warn_parity
  echo
  echo "installed $(installed_version) -> $TARGET/$SERVER_DIR"
  echo "memory store: $TARGET/$STORE_DIR"
  echo "start a new agent session (or restart) to load the memory server."
}

cmd_update() {
  if [ ! -d "$TARGET/$SERVER_DIR" ]; then
    echo "nothing to update: $TARGET/$SERVER_DIR not found — run install first" >&2
    exit 1
  fi
  old=$(installed_version)
  download_server
  install_project_cli
  echo "configs:"
  for_each_config reg_config
  reg_cursor_cli
  install_skills
  sync_agents_block
  sync_gitignore
  new=$(installed_version)
  if [ "$old" = "$new" ]; then
    echo "already up to date: $new"
  else
    echo "updated: $old -> $new"
  fi
}

unreg_config() {
  t="$TARGET/$1"
  [ -e "$t" ] || return 0
  c=$(fetch "$2")
  if [ "$(cat "$t")" = "$c" ]; then
    rm "$t"
    rmdir "$(dirname "$t")" 2>/dev/null || true
    echo "  removed:       $1"
  elif [ "$1" = "CLAUDE.md" ]; then
    # The @AGENTS.md import may carry the user's own AGENTS.md content too,
    # so a CLAUDE.md we did not write verbatim is left alone.
    :
  elif [ "$3" = ".agents/mcp/memory/run.sh" ] && grep -qF "$3" "$t" 2>/dev/null \
       && "$TARGET/$SERVER_DIR/dist/$BIN" -unmerge-config "$t" 2>/dev/null; then
    echo "  unmerged:      $1 (removed memory server entry, kept the rest)"
  elif grep -qF "$3" "$t" 2>/dev/null; then
    echo "  edit manually: $1 — remove its memory-mcp entry ($3)"
  fi
}

cmd_uninstall() {
  # Unregister configs first, while the binary is still present to unmerge.
  echo "configs:"
  for_each_config unreg_config
  unreg_cursor_cli
  rm -f "$TARGET/$PROJECT_CLI_DIR/agent-parity" "$TARGET/$PROJECT_CLI_DIR/agent-parity.cmd" "$TARGET/$PROJECT_CLI_DIR/agent-parity.ps1"
  rmdir "$TARGET/$PROJECT_CLI_DIR" 2>/dev/null || true
  # Remove skills wiring while the binary is still present so the settings
  # unmerge can run, then drop the server itself.
  uninstall_skills
  rm -rf "$TARGET/$SERVER_DIR"
  rmdir "$TARGET/.agents/mcp" 2>/dev/null || true
  echo "removed: $SERVER_DIR"
  ag="$TARGET/AGENTS.md"
  if [ -e "$ag" ] && grep -qF "$MARK_BEGIN" "$ag" 2>/dev/null && grep -qF "$MARK_END" "$ag" 2>/dev/null; then
    tmp="$ag.agent-parity.tmp"
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
      $0 == b { inblock = 1; next }
      $0 == e { inblock = 0; next }
      !inblock { print }
    ' "$ag" > "$tmp" && mv "$tmp" "$ag"
    echo "AGENTS.md: removed memory instruction block"
  elif [ -e "$ag" ] && grep -q "memory MCP server" "$ag" 2>/dev/null; then
    echo "AGENTS.md: has a memory block without markers — remove it manually"
  fi
  if [ -e "$TARGET/.gitignore" ] && grep -qF "$GI_BEGIN" "$TARGET/.gitignore" 2>/dev/null; then
    strip_gitignore_block
    echo ".gitignore: removed agent-parity block"
  fi
  if [ "$PURGE" = "yes" ]; then
    rm -rf "$TARGET/$STORE_DIR"
    echo "memory store: deleted ($TARGET/$STORE_DIR)"
  else
    echo "memory store: kept at $TARGET/$STORE_DIR (pass --purge to delete it)"
  fi
}

status_config() {
  t="$TARGET/$1"
  if [ ! -e "$t" ]; then
    echo "  missing:        $1"
  elif grep -qF "$3" "$t" 2>/dev/null; then
    echo "  registered:     $1"
  elif [ "$3" = ".agents/mcp/memory/run.sh" ] && grep -qF ".agents/mcp/memory/run.cmd" "$t" 2>/dev/null; then
    echo "  registered for Windows: $1 (run install/update here to retarget to run.sh)"
  elif [ "$3" = ".agents/mcp/memory/run.sh" ] && "$TARGET/$SERVER_DIR/dist/$BIN" -has-memory-config "$t" 2>/dev/null; then
    echo "  points elsewhere: $1 (memory entry not using $SERVER_DIR)"
  else
    echo "  not registered: $1"
  fi
}

status_agent_config() {
  label=$1
  rel=$2
  marker=$3
  t="$TARGET/$rel"
  if [ ! -e "$t" ]; then
    echo "  $label: config missing ($rel)"
  elif grep -qF "$marker" "$t" 2>/dev/null; then
    echo "  $label: registered ($rel)"
  elif [ "$marker" = ".agents/mcp/memory/run.sh" ] && grep -qF ".agents/mcp/memory/run.cmd" "$t" 2>/dev/null; then
    echo "  $label: registered for Windows ($rel; run install/update here to retarget to run.sh)"
  elif [ "$marker" = ".agents/mcp/memory/run.sh" ] && "$TARGET/$SERVER_DIR/dist/$BIN" -has-memory-config "$t" 2>/dev/null; then
    echo "  $label: points elsewhere ($rel has a memory entry not using $SERVER_DIR)"
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

cmd_status() {
  echo "target: $TARGET"
  if [ -x "$TARGET/$SERVER_DIR/dist/$BIN" ]; then
    installed=$(installed_version)
    echo "server: $installed ($SERVER_DIR/dist/$BIN)"
  else
    installed="missing"
    echo "server: missing (expected $SERVER_DIR/dist/$BIN)"
  fi
  if [ -x "$TARGET/$SERVER_DIR/run.sh" ]; then
    echo "launcher: ok"
  else
    echo "launcher: missing"
  fi
  latest=$(latest_version)
  echo "latest release: $latest"
  show_update_notice "$installed" "$latest"
  status_mcp_registrations
  status_agent_diagnostics
  status_skills
  cli="$TARGET/$CURSOR_CLI"
  if [ ! -e "$cli" ]; then
    echo "cursor cli: allowlist missing ($CURSOR_CLI)"
  elif [ "$(cat "$cli")" = "$(fetch templates/cursor.cli.json)" ]; then
    echo "cursor cli: memory allowlist present ($CURSOR_CLI)"
  else
    echo "cursor cli: $CURSOR_CLI exists but is not ours (memory allowlist not confirmed)"
  fi
  ag="$TARGET/AGENTS.md"
  if [ -e "$ag" ] && { grep -qF "$MARK_BEGIN" "$ag" || grep -q "memory MCP server" "$ag"; } 2>/dev/null; then
    echo "AGENTS.md: memory block present"
  else
    echo "AGENTS.md: memory block missing"
  fi
  if [ -d "$TARGET/$STORE_DIR" ]; then
    n=$(ls "$TARGET/$STORE_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
    echo "memory store: $n entries ($TARGET/$STORE_DIR)"
  else
    echo "memory store: missing ($TARGET/$STORE_DIR)"
  fi
  if in_git_repo; then
    ign=$(ignored_artifacts | tr '\n' ' ')
    if [ -n "$ign" ]; then
      echo "git: IGNORED and will not sync via git: $ign(run install or update to fix)"
    else
      echo "git: all artifacts tracked"
    fi
  fi
  warn_parity
}

cmd_version() {
  installed=$(installed_version)
  latest=$(latest_version)
  echo "installed: $installed"
  echo "latest:    $latest"
  show_update_notice "$installed" "$latest"
}

CMD=""
TARGET=""
PURGE=no
while [ $# -gt 0 ]; do
  case "$1" in
    install | update | uninstall | status | version) [ -z "$CMD" ] || usage; CMD="$1" ;;
    --purge) PURGE=yes ;;
    -h | --help) usage ;;
    -*) usage ;;
    *) [ -z "$TARGET" ] || usage; TARGET="$1" ;;
  esac
  shift
done
if [ -z "$CMD" ]; then
  # Backward compatible: a bare directory argument means install.
  [ -n "$TARGET" ] || usage
  CMD=install
fi
TARGET="${TARGET:-.}"
[ -d "$TARGET" ] || { echo "no such directory: $TARGET" >&2; exit 1; }

platform
"cmd_$CMD"
