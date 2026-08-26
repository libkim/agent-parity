#!/usr/bin/env sh
# agent-parity: Unix updater.
set -eu

REPO="libkim/agent-parity"
PACKAGED_VERSION="dev"
# Overridable for forks and local testing (file:// URLs work).
RAW="${AGENT_PARITY_RAW:-}"
RELEASE="${AGENT_PARITY_RELEASE:-}"
VERSION="${AGENT_PARITY_VERSION:-}"
SERVER_DIR=".agent-parity/mcp/memory"
STORE_DIR=".agent-parity/memory"
PROJECT_CLI_DIR=".agent-parity/bin"
SYNC_SCRIPT=".agent-parity/scripts/sync-claude.sh"
CLAUDE_SRC=".agent-parity/claude/settings.json"
CLAUDE_TGT=".claude/settings.json"
# SessionStart runs through the project-local launcher. Claude chooses the host
# shell; the launcher absorbs the Unix/Windows difference.
CLAUDE_HOOK='.agent-parity/bin/agent-parity sync-claude'
MARK_BEGIN="<!-- agent-parity:begin -->"
MARK_END="<!-- agent-parity:end -->"
GI_BEGIN="# agent-parity:begin"
GI_END="# agent-parity:end"
# Memory files rarely change after creation, but an explicit edit on both
# sides can conflict; a bundled git merge driver unions tags and resolves a
# one-sided body edit instead of leaving conflict markers to the user.
MERGE_DRIVER_CMD='.agent-parity/scripts/merge-memory.sh %O %A %B'
GA_LINE=".agent-parity/memory/*.md merge=agent-parity-memory"
# Marks the pre-push hook we own, so we update ours but never clobber a
# hook the user wrote.
PRE_PUSH_MARKER='# agent-parity managed pre-push hook'
# Everything install may create at the target's top level. gitignore syncing
# and the status report both derive from this one list.
ARTIFACTS=".mcp.json .cursor .codex .agents .agent-parity AGENTS.md CLAUDE.md"
# Manifest diff: everything older supported releases created that the current
# release no longer manages -- the union of their manifests minus the current
# one. install/update remove these after converging; drop an entry only when
# the support floor rises past the release that retired it.
#   retired in v0.9.0: the .agents/ tooling dirs, moved under .agent-parity/
TOMBSTONES=".agents/mcp .agents/bin .agents/scripts .agents/claude"
# Cursor CLI reads .cursor/cli.json for tool permissions. It is wired on its
# own, outside the MCP config list.
CURSOR_CLI=".cursor/cli.json"
# Instruction files only one of the four agents reads. They split behavior, so
# install and status call them out; they belong to the user, so never touched.
PARITY_BREAKERS=".cursorrules:Cursor"
CONFIG_ISSUES=0

config_issue() {
  issue_file=$1
  issue_detail=$2
  CONFIG_ISSUES=$((CONFIG_ISSUES + 1))
  echo "  warn:       $issue_file -- $issue_detail; edit this file manually" >&2
}


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
}

# Calls "$1 <path relative to target> <template in repo> <registered-marker>"
# once per MCP config file.
for_each_mcp_config() {
  "$1" ".mcp.json"               templates/claude.mcp.json              ".agent-parity/mcp/memory/run.sh"
  "$1" ".cursor/mcp.json"        templates/cursor.mcp.json              ".agent-parity/mcp/memory/run.sh"
  "$1" ".codex/config.toml"      templates/codex.config.toml            ".agent-parity/mcp/memory/run.sh"
  "$1" ".agents/mcp_config.json" templates/antigravity.mcp_config.json  ".agent-parity/mcp/memory/run.sh"
}

installed_version() {
  version_file="$TARGET/$SERVER_DIR/VERSION"
  [ -f "$version_file" ] || { echo "missing"; return; }
  tr -d '\r\n' < "$version_file"
}

# Files agent-parity installed under each pre-v0.9.0 directory, relative to it.
# Cleanup removes only these, then drops the directory if nothing else remains,
# so a user file that shares the directory is preserved rather than deleted.
tombstone_own_files() {
  case "$1" in
    .agents/mcp)
      echo memory/run.sh memory/run.cmd memory/VERSION memory/RELEASE
      echo memory/dist/memory-mcp-linux-amd64 memory/dist/memory-mcp-linux-arm64
      echo memory/dist/memory-mcp-darwin-amd64 memory/dist/memory-mcp-darwin-arm64
      echo memory/dist/memory-mcp-windows-amd64.exe ;;
    .agents/bin)
      echo agent-parity agent-parity.cmd agent-parity.ps1 ;;
    .agents/scripts)
      echo common.sh common.ps1 status.sh status.ps1 version.sh version.ps1
      echo uninstall.sh uninstall.ps1 sync-claude.sh sync-claude.ps1
      echo self-heal.sh self-heal.ps1 merge-memory.sh pre-push.sh ;;
    .agents/claude)
      echo settings.json ;;
  esac
}

remove_tombstones() {
  for tombstone in $TOMBSTONES; do
    dir="$TARGET/$tombstone"
    [ -d "$dir" ] || continue
    for rel in $(tombstone_own_files "$tombstone"); do
      rm -f "$dir/$rel"
    done
    # Drop directories left empty, deepest first. rmdir refuses a non-empty
    # directory, so any surviving user file keeps its tree intact.
    find "$dir" -depth -type d -exec rmdir {} \; 2>/dev/null || true
    if [ -d "$dir" ]; then
      echo "legacy: kept $tombstone -- it has files agent-parity did not install"
    else
      echo "legacy: removed $tombstone"
    fi
  done
}

# The memory store holds user data, so a pre-v0.9.0 store (.agents/memory) is
# moved into the new location, never deleted and recreated. Files are moved one
# by one without clobbering, then the emptied old dir is removed.
migrate_store() {
  old="$TARGET/.agents/memory"
  new="$TARGET/$STORE_DIR"
  [ -d "$old" ] || return 0
  [ "$old" = "$new" ] && return 0
  mkdir -p "$new"
  moved=0
  for f in "$old"/*.md; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    [ -e "$new/$base" ] || { mv "$f" "$new/$base"; moved=$((moved + 1)); }
  done
  rmdir "$old" 2>/dev/null || true
  [ "$moved" -eq 0 ] || echo "memory store: migrated $moved file(s) to $STORE_DIR"
}

# Other versions' caches are re-downloadable derivatives, so pruning cannot
# lose data; a dir that resists deletion (still running) just waits for the
# next run.
gc_version_cache() {
  gc_root=${AGENT_PARITY_CACHE:-${XDG_CACHE_HOME:-${HOME:?HOME is not set}/.cache}/agent-parity}
  pruned=0
  for gc_family in memory-mcp config; do
    for gc_dir in "$gc_root/$gc_family"/*/; do
      [ -d "$gc_dir" ] || continue
      [ "$(basename "$gc_dir")" != "$VERSION" ] || continue
      rm -rf "$gc_dir" 2>/dev/null || true
      [ -d "$gc_dir" ] || pruned=$((pruned + 1))
    done
  done
  [ "$pruned" -eq 0 ] || echo "cache: pruned $pruned old version(s)"
}

# Release assets have PACKAGED_VERSION replaced with their tag by build.sh.
# The latest asset URL is resolved before this script starts, so this script
# never performs a second latest-release lookup.
if [ -z "$VERSION" ]; then
  [ "$PACKAGED_VERSION" != dev ] || { echo "unpackaged update.sh requires AGENT_PARITY_VERSION" >&2; exit 1; }
  VERSION=$PACKAGED_VERSION
fi
case "$VERSION" in
  v[0-9A-Za-z._-]* | dev) ;;
  *) echo "invalid agent-parity release version: $VERSION" >&2; exit 1 ;;
esac
case "$VERSION" in
  *[!0-9A-Za-z._-]*) echo "invalid agent-parity release version: $VERSION" >&2; exit 1 ;;
esac
[ -n "$RAW" ]     || RAW="https://raw.githubusercontent.com/$REPO/$VERSION"
[ -n "$RELEASE" ] || RELEASE="https://github.com/$REPO/releases/download/$VERSION"


install_project_cli() {
  d="$TARGET/$PROJECT_CLI_DIR"
  s="$TARGET/.agent-parity/scripts"
  mkdir -p "$d" "$s"
  fetch_to templates/project-agent-parity.sh "$d/agent-parity" executable
  fetch_to templates/project-agent-parity.cmd "$d/agent-parity.cmd" executable
  for name in common.sh status.sh version.sh uninstall.sh sync-claude.sh self-heal.sh merge-memory.sh pre-push.sh; do
    fetch_to "templates/$name" "$s/$name" executable
  done
  for name in common.ps1 status.ps1 version.ps1 uninstall.ps1 sync-claude.ps1 self-heal.ps1; do
    fetch_to "templates/$name" "$s/$name"
  done
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
  CONFIG_EDITOR="$d/$asset"
  rm -f "$TEMP_DIR/checksums.txt"
  rmdir "$TEMP_DIR"
  TEMP_DIR=""
  echo "cli: installed local JSON/TOML config editor"
}

install_server() {
  dest="$TARGET/$SERVER_DIR"
  mkdir -p "$dest"
  TEMP_DIR=$(mktemp -d "$dest/.agent-parity-runtime.XXXXXX")
  fetch_to templates/run.sh "$TEMP_DIR/run.sh" executable
  TEMP_FILE=$(make_temp_for "$TEMP_DIR/run.cmd")
  if fetch templates/run.cmd > "$TEMP_FILE" 2>/dev/null; then
    commit_temp "$TEMP_DIR/run.cmd"
  else
    cleanup_temp
    echo "could not fetch templates/run.cmd" >&2
    exit 1
  fi
  write_value_to "$TEMP_DIR/VERSION" "$VERSION"
  write_value_to "$TEMP_DIR/RELEASE" "${RELEASE%/}"
  for name in run.sh run.cmd VERSION RELEASE; do
    mv -f "$TEMP_DIR/$name" "$dest/$name"
  done
  rmdir "$TEMP_DIR"
  TEMP_DIR=""
  echo "server: pinned $VERSION (current platform binary downloads on first MCP launch)"
}

reg_mcp_config() {
  t="$TARGET/$1"
  c=$(fetch "$2")
  if [ ! -e "$t" ]; then
    mkdir -p "$(dirname "$t")"
    printf '%s\n' "$c" > "$t"
    echo "  wrote:      $1"
  elif [ "$3" = ".agent-parity/mcp/memory/run.sh" ]; then
    current=$("$CONFIG_EDITOR" command "$t" 2>&1) || code=$?
    code=${code:-0}
    if [ "$code" -eq 0 ] && { [ "$current" = ".agent-parity/mcp/memory/run.sh" ] || [ "$current" = ".agent-parity/mcp/memory/run.cmd" ] || [ "$current" = ".agents/mcp/memory/run.sh" ] || [ "$current" = ".agents/mcp/memory/run.cmd" ]; }; then
      if result=$("$CONFIG_EDITOR" ensure "$t" "$3" 2>&1); then
        if [ "$result" = changed ]; then echo "  updated:    $1 (managed registration and approvals)"; else echo "  registered: $1 (already)"; fi
      else
        config_issue "$1" "$result"
      fi
    elif [ "$code" -eq 0 ]; then
      config_issue "$1" "memory entry points at a different server"
      printf '%s\n' "$c" | sed 's/^/    | /'
    elif [ "$code" -eq 1 ]; then
      if result=$("$CONFIG_EDITOR" ensure "$t" "$3" 2>&1); then
        echo "  merged:     $1 (added memory server entry)"
      else
        config_issue "$1" "$result"
        printf '%s\n' "$c" | sed 's/^/    | /'
      fi
    else
      config_issue "$1" "$current"
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

reg_claude_wrapper() {
  t="$TARGET/CLAUDE.md"
  if [ ! -e "$t" ]; then
    printf '%s\n' '@AGENTS.md' > "$t"
    echo "claude wrapper: wrote CLAUDE.md"
  elif awk 'BEGIN { ok=1; n=0 } { sub(/\r$/, ""); n++; if (n != 1 || $0 != "@AGENTS.md") ok=0 } END { exit !(ok && n == 1) }' "$t"; then
    echo "claude wrapper: registered (CLAUDE.md)"
  else
    echo "claude wrapper: existing CLAUDE.md preserved; expected exact content: @AGENTS.md"
  fi
}

reg_cursor_cli() {
  t="$TARGET/$CURSOR_CLI"
  result=$("$CONFIG_EDITOR" merge-cursor-cli "$t" 2>&1) || {
    config_issue "$CURSOR_CLI" "$result"
    return 0
  }
  case "$result" in
    changed) echo "  merged:     $CURSOR_CLI (added memory allowlist entry)" ;;
    unchanged) echo "  registered: $CURSOR_CLI (already)" ;;
    *) echo "unexpected config editor result for $CURSOR_CLI: $result" >&2; exit 1 ;;
  esac
}

reg_agent_hooks() {
  hook_issues_before=$CONFIG_ISSUES
  for spec in "$CLAUDE_SRC:claude" "$CLAUDE_TGT:claude" ".codex/hooks.json:codex" ".cursor/hooks.json:cursor" ".agents/hooks.json:antigravity"; do
    rel=${spec%:*}
    kind=${spec##*:}
    if ! detail=$("$CONFIG_EDITOR" merge-hook "$TARGET/$rel" "$kind" 2>&1); then
      config_issue "$rel" "$detail"
    fi
  done
  if [ "$hook_issues_before" -eq "$CONFIG_ISSUES" ]; then
    echo "  hooks:      Claude, Codex, Cursor, Antigravity self-heal registered"
  else
    echo "  hooks:      completed with configuration warnings"
  fi
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

managed_block_state() {
  file=$1 begin=$2 end=$3
  [ -e "$file" ] || { echo absent; return; }
  awk -v b="$begin" -v e="$end" '
    {
      line = $0; sub(/\r$/, "", line)
      if (index(line, b)) begin_hits++
      if (index(line, e)) end_hits++
      if (line == b) begin_line = NR
      if (line == e) end_line = NR
    }
    END {
      if (begin_hits == 0 && end_hits == 0) print "absent"
      else if (begin_hits == 1 && end_hits == 1 && begin_line > 0 && begin_line < end_line) print "valid"
      else print "invalid"
    }
  ' "$file"
}

strip_gitignore_block() {
  gi="$TARGET/.gitignore"
  TEMP_FILE=$(make_temp_for "$gi")
  awk -v b="$GI_BEGIN" -v e="$GI_END" '
    { line = $0; sub(/\r$/, "", line) }
    line == b { inblock = 1; next }
    line == e { inblock = 0; next }
    !inblock { print }
  ' "$gi" > "$TEMP_FILE"
  commit_temp "$gi"
}

strip_gitattributes_block() {
  ga="$TARGET/.gitattributes"
  TEMP_FILE=$(make_temp_for "$ga")
  awk -v b="$GI_BEGIN" -v e="$GI_END" '
    { line = $0; sub(/\r$/, "", line) }
    line == b { inblock = 1; next }
    line == e { inblock = 0; next }
    !inblock { print }
  ' "$ga" > "$TEMP_FILE"
  commit_temp "$ga"
}

sync_gitattributes() {
  in_git_repo || return 0
  ga="$TARGET/.gitattributes"
  state=$(managed_block_state "$ga" "$GI_BEGIN" "$GI_END")
  case "$state" in
    valid) strip_gitattributes_block ;;
    invalid)
      echo ".gitattributes: agent-parity markers are incomplete, duplicated, or out of order; file left unchanged -- repair the markers manually" >&2
      return 0
      ;;
  esac
  [ -s "$ga" ] && [ -n "$(tail -c1 "$ga")" ] && echo >> "$ga"
  {
    echo "$GI_BEGIN"
    echo "$GA_LINE"
    echo "$GI_END"
  } >> "$ga"
  echo ".gitattributes: memory files use the agent-parity merge driver"
}

# The driver definition lives in .git/config, which git never carries; the
# committed session hooks re-register it on machines that only pull.
reg_merge_driver() {
  in_git_repo || return 0
  git -C "$TARGET" config merge.agent-parity-memory.name "agent-parity memory merge"
  git -C "$TARGET" config merge.agent-parity-memory.driver "$MERGE_DRIVER_CMD"
  echo "git: memory merge driver registered (.git/config)"
}

# The pre-push entry point is a file named exactly "pre-push" in git's active
# hooks dir. rev-parse --git-path hooks already resolves core.hooksPath, so this
# points at .husky/pre-push under husky and .git/hooks/pre-push otherwise. We own
# that entry point only when it is empty or already ours; the installed hook just
# runs the tracked guard in .agents. If any other hook already sits there, a
# user's own hook or a hook manager's, we leave it alone and tell the user to
# call the guard from it. We do not detect or wrap a hook manager: whether a hook
# is there is all that matters, and a static user hook cannot be told apart from
# a regenerated one anyway.
pre_push_hook_path() {
  hp=$(git -C "$TARGET" rev-parse --git-path hooks 2>/dev/null) || return 1
  case "$hp" in /*) echo "$hp/pre-push" ;; *) echo "$TARGET/$hp/pre-push" ;; esac
}

reg_pre_push_hook() {
  in_git_repo || return 0
  hook=$(pre_push_hook_path) || return 0
  if [ -e "$hook" ] && ! grep -qF "$PRE_PUSH_MARKER" "$hook" 2>/dev/null; then
    echo "git: a pre-push hook is already in place -- call .agent-parity/scripts/pre-push.sh from it to guard managed files"
    return 0
  fi
  mkdir -p "$(dirname "$hook")"
  cat > "$hook" <<EOF
#!/bin/sh
$PRE_PUSH_MARKER
# Managed file, regenerated by install/update. To add your own checks, put your
# own pre-push hook here and run .agent-parity/scripts/pre-push.sh from it.
exec "\$(git rev-parse --show-toplevel)/.agent-parity/scripts/pre-push.sh"
EOF
  chmod +x "$hook"
  echo "git: pre-push guard registered (.git/hooks/pre-push)"
}

# The vendored files must stay git-tracked to reach other machines through
# git. Where the project's .gitignore hides any of them, keep a marked block
# of un-ignore rules; recompute it from scratch each run so it stays minimal.
sync_gitignore() {
  in_git_repo || return 0
  gi="$TARGET/.gitignore"
  state=$(managed_block_state "$gi" "$GI_BEGIN" "$GI_END")
  case "$state" in
    valid) strip_gitignore_block ;;
    invalid)
      echo ".gitignore: agent-parity markers are incomplete, duplicated, or out of order; file left unchanged -- repair the markers manually" >&2
      return 0
      ;;
  esac
  # This block carries un-ignore rules only. A consumer project never builds the
  # memory server, so dist/ never legitimately appears here; a legacy committed
  # dist/ is removed by the tombstone sweep, not hidden by a positive ignore.
  rules=""
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
  # These are the skills we ship: agent-parity runs the management commands
  # without the user typing OS-specific paths, and write-requirement/
  # write-governance are the default authoring skills. They are generated files
  # we own outright (like run.sh), so overwrite them every run to keep current.
  for sk in agent-parity write-requirement write-governance; do
    d="$TARGET/.agents/skills/$sk"
    mkdir -p "$d"
    fetch_to "templates/$sk.skill.md" "$d/SKILL.md"
    echo "  wrote:      .agents/skills/$sk/SKILL.md"
  done
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
  if detail=$("$CONFIG_EDITOR" merge-claude-settings "$src" "$CLAUDE_HOOK" 2>&1); then
    echo "  merged:     $CLAUDE_SRC (memory keys + sync hook)"
    if sync_output=$(bash "$TARGET/$SYNC_SCRIPT" sync 2>&1); then
      printf '%s\n' "$sync_output" | sed 's/^/  /'
    else
      config_issue "$CLAUDE_TGT" "$sync_output"
    fi
  else
    config_issue "$CLAUDE_SRC" "$detail"
  fi
}


sync_agents_block() {
  ag="$TARGET/AGENTS.md"
  snip=$(fetch templates/AGENTS.snippet.md)
  state=$(managed_block_state "$ag" "$MARK_BEGIN" "$MARK_END")
  if [ "$state" = valid ]; then
    cur=$(awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
      { line = $0; sub(/\r$/, "", line) }
      line == b { inblock = 1 } inblock { print } line == e { exit }
    ' "$ag")
    if [ "$cur" = "$snip" ]; then
      echo "AGENTS.md: agent-parity instruction block up to date"
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
    echo "AGENTS.md: refreshed agent-parity instruction block"
  elif [ "$state" = absent ]; then
    if [ -e "$ag" ] && grep -qE "memory_(recent|add|search|get)" "$ag" 2>/dev/null; then
      echo "AGENTS.md: note -- existing text already mentions the memory tools; check it against the appended block for duplication"
    fi
    { printf '\n%s\n' "$snip"; } >> "$ag"
    echo "AGENTS.md: appended agent-parity instruction block"
  else
    echo "AGENTS.md: agent-parity markers are incomplete, duplicated, or out of order; file left unchanged -- repair the markers manually" >&2
  fi
}


usage() {
  echo "usage: update.sh [update] [dir]" >&2
  exit 2
}

TARGET=""
if [ "${1:-}" = "update" ]; then shift; fi
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

cmd_update() {
  # Accept the pre-v0.9.0 layout too (server under .agents/): an update from it
  # installs into the new location and tombstones the old tooling dirs.
  if [ ! -d "$TARGET/$SERVER_DIR" ] && [ ! -d "$TARGET/.agents/mcp/memory" ]; then
    echo "nothing to update: $TARGET/$SERVER_DIR not found -- run install first" >&2
    exit 1
  fi
  old=$(installed_version)
  if [ "$old" = "$VERSION" ]; then
    echo "already up to date: $old"
    return
  fi
  migrate_store
  install_server
  install_project_cli
  install_config_editor
  echo "configs:"
  for_each_mcp_config reg_mcp_config
  reg_cursor_cli
  reg_claude_wrapper
  install_skills
  reg_agent_hooks
  sync_agents_block
  sync_gitignore
  sync_gitattributes
  reg_merge_driver
  reg_pre_push_hook
  # Tombstones go last so the converged layout is complete before anything
  # legacy disappears.
  remove_tombstones
  gc_version_cache
  warn_parity
  if [ "$CONFIG_ISSUES" -gt 0 ]; then
    echo "configuration: completed with $CONFIG_ISSUES warning(s); listed files require manual review"
  else
    echo "configuration: all managed agent settings converged"
  fi
  new=$(installed_version)
  echo "updated: $old -> $new"
  # A running session loads the updated server, skills, and registrations only
  # at startup, so a completed version change needs a restart.
  echo "start a new agent session (or restart) to load the updated setup."
}


cmd_update
