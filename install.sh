#!/usr/bin/env sh
# agent-parity: Unix installer.
set -eu

REPO="libkim/agent-parity"
# Overridable for forks and local testing (file:// URLs work).
RAW="${AGENT_PARITY_RAW:-}"
RELEASE="${AGENT_PARITY_RELEASE:-}"
VERSION="${AGENT_PARITY_VERSION:-}"
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


fetch() { curl -fsSL "$RAW/$1"; }

TEMP_FILE=""
TEMP_DIR=""

cleanup_temp() {
  [ -z "$TEMP_FILE" ] || rm -f "$TEMP_FILE"
  [ -z "$TEMP_DIR" ] || rm -rf "$TEMP_DIR"
  TEMP_FILE=""
  TEMP_DIR=""
}

trap cleanup_temp EXIT
trap 'cleanup_temp; exit 1' HUP INT TERM

make_temp_for() {
  temp_target=$1
  temp_dir=$(dirname "$temp_target")
  temp_base=$(basename "$temp_target")
  mktemp "$temp_dir/.${temp_base}.agent-parity.XXXXXX"
}

commit_temp() {
  temp_target=$1
  mv "$TEMP_FILE" "$temp_target"
  TEMP_FILE=""
}

fetch_to() {
  fetch_rel=$1
  fetch_target=$2
  fetch_mode=${3:-}
  TEMP_FILE=$(make_temp_for "$fetch_target")
  fetch "$fetch_rel" > "$TEMP_FILE"
  [ "$fetch_mode" != executable ] || chmod +x "$TEMP_FILE"
  commit_temp "$fetch_target"
}

download_to() {
  download_url=$1
  download_target=$2
  download_mode=${3:-}
  TEMP_FILE=$(make_temp_for "$download_target")
  curl -fsSL "$download_url" -o "$TEMP_FILE"
  [ "$download_mode" != executable ] || chmod +x "$TEMP_FILE"
  commit_temp "$download_target"
}

write_value_to() {
  value_target=$1
  value=$2
  TEMP_FILE=$(make_temp_for "$value_target")
  printf '%s\n' "$value" > "$TEMP_FILE"
  commit_temp "$value_target"
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
  u=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null) || { echo "unknown"; return; }
  case "$u" in
    */tag/*) echo "${u##*/}" ;;
    *) echo "unknown" ;;
  esac
}

# Pin scripts, templates, and binaries to one release tag. The supported
# bootstrap passes both URLs explicitly; direct invocation resolves them here.
# There is deliberately no main fallback: an unresolved release must fail
# instead of mixing rolling installer logic with released artifacts.
if [ -z "$RAW" ] || [ -z "$RELEASE" ]; then
  PINNED_TAG=$(latest_version)
  case "$PINNED_TAG" in
    v*)
      [ -n "$RAW" ]     || RAW="https://raw.githubusercontent.com/$REPO/$PINNED_TAG"
      [ -n "$RELEASE" ] || RELEASE="https://github.com/$REPO/releases/download/$PINNED_TAG"
      ;;
    *) echo "could not resolve latest agent-parity release" >&2; exit 1 ;;
  esac
fi

if [ -z "$VERSION" ]; then
  case "${RAW%/}" in
    */v*) VERSION=${RAW%/}; VERSION=${VERSION##*/} ;;
    *) VERSION=dev ;;
  esac
fi
case "$VERSION" in
  v[0-9A-Za-z._-]* | dev) ;;
  *) echo "invalid agent-parity release version: $VERSION" >&2; exit 1 ;;
esac
case "$VERSION" in
  *[!0-9A-Za-z._-]*) echo "invalid agent-parity release version: $VERSION" >&2; exit 1 ;;
esac


install_project_cli() {
  d="$TARGET/$PROJECT_CLI_DIR"
  s="$TARGET/.agents/scripts"
  mkdir -p "$d" "$s"
  fetch_to templates/project-agent-parity.sh "$d/agent-parity" executable
  fetch_to templates/project-agent-parity.cmd "$d/agent-parity.cmd" executable
  for name in common.sh status.sh version.sh uninstall.sh sync-claude.sh self-heal.sh; do
    fetch_to "templates/$name" "$s/$name" executable
  done
  for name in common.ps1 status.ps1 version.ps1 uninstall.ps1 sync-claude.ps1 self-heal.ps1; do
    fetch_to "templates/$name" "$s/$name"
  done
  rm -f "$d/agent-parity.ps1"
  echo "cli: wrote project launchers and local command scripts"
}

install_config_editor() {
  asset="agent-parity-config-${goos}-${goarch}"
  cache_root=${AGENT_PARITY_CACHE:-${XDG_CACHE_HOME:-${HOME:?HOME is not set}/.cache}/agent-parity}
  d="$cache_root/config/$VERSION"
  mkdir -p "$d"
  TEMP_DIR=$(mktemp -d "$d/.agent-parity-config.XXXXXX")
  download_to "${RELEASE%/}/checksums.txt" "$TEMP_DIR/checksums.txt"
  download_to "${RELEASE%/}/$asset" "$TEMP_DIR/$asset" executable
  expected=$(awk -v asset="$asset" '{ name=$2; sub(/^\*/, "", name); if (name == asset) { print $1; exit } }' "$TEMP_DIR/checksums.txt")
  [ -n "$expected" ] || { echo "checksum missing for $asset" >&2; exit 1; }
  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$TEMP_DIR/$asset" | awk '{print $1}')
  else
    actual=$(shasum -a 256 "$TEMP_DIR/$asset" | awk '{print $1}')
  fi
  [ "$actual" = "$expected" ] || { echo "checksum mismatch for $asset" >&2; exit 1; }
  mv -f "$TEMP_DIR/$asset" "$d/$asset"
  rm -f "$TEMP_DIR/checksums.txt"
  rmdir "$TEMP_DIR"
  TEMP_DIR=""
  echo "cli: installed local JSON/TOML config editor"
}

install_server() {
  dest="$TARGET/$SERVER_DIR"
  mkdir -p "$dest"
  TEMP_DIR=$(mktemp -d "$dest/.agent-parity-runtime.XXXXXX")
  fetch_to run.sh "$TEMP_DIR/run.sh" executable
  TEMP_FILE=$(make_temp_for "$TEMP_DIR/run.cmd")
  if fetch run.cmd > "$TEMP_FILE" 2>/dev/null; then
    commit_temp "$TEMP_DIR/run.cmd"
  else
    cleanup_temp
    echo "could not fetch run.cmd" >&2
    exit 1
  fi
  write_value_to "$TEMP_DIR/VERSION" "$VERSION"
  write_value_to "$TEMP_DIR/RELEASE" "${RELEASE%/}"
  "$TEMP_DIR/run.sh" -version >/dev/null
  for name in run.sh run.cmd VERSION RELEASE; do
    mv -f "$TEMP_DIR/$name" "$dest/$name"
  done
  rmdir "$TEMP_DIR"
  TEMP_DIR=""
  # Remove a legacy vendored copy only after the verified cache and launchers
  # are ready.
  rm -rf "$dest/dist"
  echo "server: pinned $VERSION (current platform binary verified in the shared cache)"
}

reg_config() {
  t="$TARGET/$1"
  c=$(fetch "$2")
  if [ ! -e "$t" ]; then
    mkdir -p "$(dirname "$t")"
    printf '%s\n' "$c" > "$t"
    echo "  wrote:      $1"
  elif [ "$3" = ".agents/mcp/memory/run.sh" ]; then
    cache_root=${AGENT_PARITY_CACHE:-${XDG_CACHE_HOME:-${HOME:?HOME is not set}/.cache}/agent-parity}
    editor="$cache_root/config/$VERSION/agent-parity-config-${goos}-${goarch}"
    current=$("$editor" command "$t" 2>/dev/null) || code=$?
    code=${code:-0}
    if [ "$code" -eq 0 ] && [ "$current" = "$3" ]; then
      echo "  registered: $1 (already)"
    elif [ "$code" -eq 0 ] && { [ "$current" = ".agents/mcp/memory/run.sh" ] || [ "$current" = ".agents/mcp/memory/run.cmd" ]; }; then
      result=$("$editor" ensure "$t" "$3")
      if [ "$result" = changed ]; then echo "  retargeted: $1 (launcher -> Unix launcher)"; else echo "  registered: $1 (already)"; fi
    elif [ "$code" -eq 0 ]; then
      echo "  exists:     $1 -- its memory entry points at a different server; replace it with:"
      printf '%s\n' "$c" | sed 's/^/    | /'
    elif [ "$code" -eq 1 ] && "$editor" ensure "$t" "$3" >/dev/null; then
      echo "  merged:     $1 (added memory server entry)"
    else
      echo "  exists:     $1 -- invalid JSON/TOML; merge this in:"
      printf '%s\n' "$c" | sed 's/^/    | /'
    fi
    unset code current
  elif [ "$(cat "$t")" = "$c" ]; then
    echo "  registered: $1 (already)"
  else
    echo "  exists:     $1 -- merge this in:"
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
    echo "  exists:     $CURSOR_CLI -- merge this in:"
    printf '%s\n' "$c" | sed 's/^/    | /'
  fi
}

reg_agent_hooks() {
  bin="$TARGET/$SERVER_DIR/run.sh"
  "$bin" -merge-agent-hook "$TARGET/$CLAUDE_SRC" -hook-kind claude
  "$bin" -merge-agent-hook "$TARGET/$CLAUDE_TGT" -hook-kind claude
  "$bin" -merge-agent-hook "$TARGET/.codex/hooks.json" -hook-kind codex
  "$bin" -merge-agent-hook "$TARGET/.cursor/hooks.json" -hook-kind cursor
  "$bin" -merge-agent-hook "$TARGET/.agents/hooks.json" -hook-kind antigravity
  echo "  hooks:      Claude, Codex, Cursor, Antigravity self-heal registered"
  echo "  note:       Codex requires review/trust for the project hook before it runs"
}

# Remove the Cursor CLI allowlist only when it is byte-identical to ours; a
# file the user changed is left in place.

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
  TEMP_FILE=$(make_temp_for "$gi")
  awk -v b="$GI_BEGIN" -v e="$GI_END" '
    { line = $0; sub(/\r$/, "", line) }
    line == b { inblock = 1; next }
    line == e { inblock = 0; next }
    !inblock { print }
  ' "$gi" > "$TEMP_FILE"
  commit_temp "$gi"
}

# The vendored files must stay git-tracked to reach other machines through
# git. Where the project's .gitignore hides any of them, keep a marked block
# of un-ignore rules; recompute it from scratch each run so it stays minimal.
sync_gitignore() {
  in_git_repo || return 0
  strip_gitignore_block
  # Legacy installs may still have a vendored dist directory. Keep it out of
  # Git even if an interrupted migration leaves files behind.
  rules="/.agents/mcp/memory/dist/
"
  for p in $(ignored_artifacts); do
    if [ -d "$TARGET/$p" ]; then rules="$rules!/$p/
"; else rules="$rules!/$p
"; fi
  done
  # .claude is regenerated from .agents each session. Keep settings.json tracked
  # so a fresh pull already carries the SessionStart hook and self-syncs with no
  # manual first-run bootstrap; ignore the rest (skills copy, machine-local
  # settings, runtime files). Git can't re-include a file under a fully ignored
  # directory, so ignore .claude/* and un-ignore settings.json.
  if [ -e "$TARGET/$SYNC_SCRIPT" ] && ! git -C "$TARGET" check-ignore -q -- .claude/skills 2>/dev/null; then
    rules="$rules/.claude/*
!/.claude/settings.json
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
# hook mirrors it into .claude/skills each session -- an internal shim that
# keeps surface behavior identical across agents.
# Pre-existing per-agent skills (.claude, .codex, .cursor) are moved into the
# shared source: Claude's must move or the sync would destroy them, and Codex's
# and Cursor's would otherwise stay invisible to the other agents. Skills are
# self-contained folders, so the move is mechanical and safe -- unlike
# instruction prose, which is only ever reported.
adopt_agent_skills() {
  for pair in .claude/skills:claude .codex/skills:codex .cursor/skills:cursor; do
    dir=${pair%%:*}; label=${pair##*:}
    [ -d "$TARGET/$dir" ] || continue
    for d in "$TARGET/$dir"/*/; do
      [ -d "$d" ] || continue
      name=$(basename "$d")
      [ "$name" = "agent-parity" ] && continue
      if [ ! -e "$TARGET/.agents/skills/$name" ]; then
        mv "$d" "$TARGET/.agents/skills/$name"
        echo "  adopted:    $dir/$name -> .agents/skills/$name (now shared by all agents)"
      elif ! diff -qr "$TARGET/.agents/skills/$name" "$d" >/dev/null 2>&1; then
        mv "$d" "$TARGET/.agents/skills/$name.from-$label"
        echo "  conflict:   $dir/$name differs from the shared one -- saved as .agents/skills/$name.from-$label, merge manually"
      fi
    done
  done
}

install_skills() {
  echo "skills:"
  mkdir -p "$TARGET/.agents/skills"
  adopt_agent_skills
  # The agent-parity skill lets any agent run the management commands without the
  # user typing OS-specific paths. It is a generated shim we own outright (like
  # run.sh), so overwrite it every run to keep it current.
  msk="$TARGET/.agents/skills/agent-parity"
  mkdir -p "$msk"
  fetch_to templates/agent-parity.skill.md "$msk/SKILL.md"
  echo "  wrote:      .agents/skills/agent-parity/SKILL.md"
  [ -n "$(ls -A "$TARGET/.agents/skills" 2>/dev/null)" ] || : > "$TARGET/.agents/skills/.gitkeep"
  # sync-claude.sh is a generated shim we own outright (like run.sh), so
  # overwrite it every run to keep it current -- user skills live in
  # .agents/skills, never here.
  s="$TARGET/$SYNC_SCRIPT"
  mkdir -p "$(dirname "$s")"
  fetch_to templates/sync-claude.sh "$s" executable
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
  if "$TARGET/$SERVER_DIR/run.sh" -merge-claude-settings "$src" -hook-command "$CLAUDE_HOOK"; then
    echo "  merged:     $CLAUDE_SRC (memory keys + sync hook)"
  else
    echo "  warn:       could not merge $CLAUDE_SRC" >&2
  fi
  bash "$TARGET/$SYNC_SCRIPT" sync 2>&1 | sed 's/^/  /'
}


sync_agents_block() {
  ag="$TARGET/AGENTS.md"
  snip=$(fetch templates/AGENTS.snippet.md)
  if [ -e "$ag" ] && grep -qF "$MARK_BEGIN" "$ag" 2>/dev/null && grep -qF "$MARK_END" "$ag" 2>/dev/null; then
    cur=$(awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
      { line = $0; sub(/\r$/, "", line) }
      line == b { inblock = 1 } inblock { print } line == e { exit }
    ' "$ag")
    if [ "$cur" = "$snip" ]; then
      echo "AGENTS.md: memory block up to date"
      return
    fi
    TEMP_FILE=$(make_temp_for "$ag")
    printf '%s\n' "$snip" | awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
      NR == FNR { new[FNR] = $0; n = FNR; next }
      { line = $0; sub(/\r$/, "", line) }
      line == b { for (i = 1; i <= n; i++) print new[i]; inblock = 1; next }
      line == e { inblock = 0; next }
      !inblock { print }
    ' - "$ag" > "$TEMP_FILE"
    commit_temp "$ag"
    echo "AGENTS.md: refreshed memory instruction block"
  else
    if [ -e "$ag" ] && grep -qE "memory_(recent|add|search|get)" "$ag" 2>/dev/null; then
      echo "AGENTS.md: note -- existing text already mentions the memory tools; check it against the appended block for duplication"
    fi
    { printf '\n%s\n' "$snip"; } >> "$ag"
    echo "AGENTS.md: appended memory instruction block"
  fi
}


usage() {
  echo "usage: install.sh [install] [dir]" >&2
  exit 2
}

TARGET=""
if [ "${1:-}" = "install" ]; then shift; fi
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h | --help | help) usage ;;
    -*) usage ;;
    *) [ -z "$TARGET" ] || usage; TARGET=$1 ;;
  esac
  shift
done
TARGET=${TARGET:-.}
[ -d "$TARGET" ] || { echo "no such directory: $TARGET" >&2; exit 1; }
platform

warn_parity() {
  for pair in $PARITY_BREAKERS; do
    f="${pair%%:*}"
    who=$(echo "${pair##*:}" | tr '_' ' ')
    if [ -e "$TARGET/$f" ]; then
      echo "parity: $f exists -- only $who reads it, so agents diverge; fold it into AGENTS.md"
    fi
  done
}


cmd_install() {
  mkdir -p "$TARGET/$SERVER_DIR" "$TARGET/$STORE_DIR"
  install_server
  install_project_cli
  install_config_editor
  echo "configs:"
  for_each_config reg_config
  reg_cursor_cli
  install_skills
  reg_agent_hooks
  sync_agents_block
  sync_gitignore
  warn_parity
  echo
  echo "installed $(installed_version) -> $TARGET/$SERVER_DIR"
  echo "memory store: $TARGET/$STORE_DIR"
  echo "start a new agent session (or restart) to load the memory server."
}


cmd_install
