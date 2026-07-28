#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILLS_SOURCE="$ROOT_DIR/.agents/skills"
SKILLS_TARGET="$ROOT_DIR/.claude/skills"
SETTINGS_SOURCE="$ROOT_DIR/.agents/claude/settings.json"
SETTINGS_TARGET="$ROOT_DIR/.claude/settings.json"

usage() {
  cat <<'USAGE'
Usage: .agents/scripts/sync-claude.sh <check|sync|clean>

Materialize Claude Code artifacts from the synced .agents source.
  check  Report whether .claude matches .agents (skills + settings).
  sync   Recreate .claude/skills and .claude/settings.json from .agents.
  clean  Remove generated .claude/skills and .claude/settings.json.

Note: .claude/settings.local.json (machine-local) is never touched.
USAGE
}

require_skills_source() {
  # Self-heal: an empty skills dir may not survive a git clone.
  mkdir -p "$SKILLS_SOURCE"
}

check() {
  require_skills_source
  local status=0

  # skills
  if [ -L "$SKILLS_TARGET" ]; then
    echo "skills:   unexpected symlink .claude/skills"; status=1
  elif [ ! -d "$SKILLS_TARGET" ]; then
    echo "skills:   missing .claude/skills"; status=1
  elif diff -qr "$SKILLS_SOURCE" "$SKILLS_TARGET" >/dev/null; then
    echo "skills:   ok"
  else
    echo "skills:   stale"; status=1
  fi

  # settings
  if [ ! -f "$SETTINGS_SOURCE" ]; then
    echo "settings: no source (.agents/claude/settings.json) — skipped"
  elif [ ! -f "$SETTINGS_TARGET" ]; then
    echo "settings: missing .claude/settings.json"; status=1
  elif diff -q "$SETTINGS_SOURCE" "$SETTINGS_TARGET" >/dev/null; then
    echo "settings: ok"
  else
    echo "settings: stale"; status=1
  fi

  exit $status
}

sync() {
  require_skills_source
  mkdir -p "$ROOT_DIR/.claude"
  rm -rf "$SKILLS_TARGET"
  cp -R "$SKILLS_SOURCE" "$SKILLS_TARGET"
  echo "synced:   .claude/skills recreated from .agents/skills"
  if [ -f "$SETTINGS_SOURCE" ]; then
    cp "$SETTINGS_SOURCE" "$SETTINGS_TARGET"
    echo "synced:   .claude/settings.json recreated from .agents/claude/settings.json"
  else
    echo "settings: no source — skipped"
  fi
}

clean() {
  rm -rf "$SKILLS_TARGET"
  rm -f "$SETTINGS_TARGET"
  echo "cleaned:  .claude/skills and .claude/settings.json removed"
}

case "${1:-}" in
  check) check ;;
  sync) sync ;;
  clean) clean ;;
  -h|--help|help|"") usage ;;
  *) usage >&2; exit 2 ;;
esac
