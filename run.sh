#!/usr/bin/env bash
# Download the pinned release binary for this platform into a shared cache,
# verify it against the release checksum, then run it for this project.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
version_file="$here/VERSION"
release_file="$here/RELEASE"

[[ -f "$version_file" ]] || { echo "memory-mcp: missing $version_file" >&2; exit 1; }
[[ -f "$release_file" ]] || { echo "memory-mcp: missing $release_file" >&2; exit 1; }
version="$(tr -d '\r\n' < "$version_file")"
release="$(tr -d '\r\n' < "$release_file")"
case "$version" in
  v[0-9A-Za-z._-]* | dev) ;;
  *) echo "memory-mcp: invalid pinned version: $version" >&2; exit 1 ;;
esac
case "$version" in
  *[!0-9A-Za-z._-]*) echo "memory-mcp: invalid pinned version: $version" >&2; exit 1 ;;
esac
[[ -n "$release" ]] || { echo "memory-mcp: empty release URL" >&2; exit 1; }

case "$(uname -s)" in
  Linux) goos=linux ;;
  Darwin) goos=darwin ;;
  *) echo "memory-mcp: unsupported OS $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) goarch=amd64 ;;
  aarch64 | arm64) goarch=arm64 ;;
  *) echo "memory-mcp: unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

asset="memory-mcp-${goos}-${goarch}"
cache_root="${AGENT_PARITY_CACHE:-${XDG_CACHE_HOME:-${HOME:?HOME is not set}/.cache}/agent-parity}"
cache_dir="$cache_root/memory-mcp/$version"
bin="$cache_dir/$asset"
sum="$bin.sha256"

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "memory-mcp: sha256sum or shasum is required" >&2
    return 1
  fi
}

cache_valid() {
  [[ -x "$bin" && -f "$sum" ]] || return 1
  expected="$(tr -d '\r\n' < "$sum")"
  [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || return 1
  actual="$(hash_file "$bin")" || return 1
  expected_lc="$(printf '%s' "$expected" | tr 'A-F' 'a-f')"
  actual_lc="$(printf '%s' "$actual" | tr 'A-F' 'a-f')"
  [[ "$actual_lc" == "$expected_lc" ]]
}

if ! cache_valid; then
  mkdir -p "$cache_dir"
  tmp_bin="$(mktemp "$cache_dir/.${asset}.XXXXXX")"
  tmp_sum="$(mktemp "$cache_dir/.checksums.XXXXXX")"
  cleanup() { rm -f "$tmp_bin" "$tmp_sum"; }
  trap cleanup EXIT HUP INT TERM

  curl -fsSL "${release%/}/checksums.txt" -o "$tmp_sum"
  expected="$(awk -v asset="$asset" '{ name=$2; sub(/^\*/, "", name); if (name == asset) { print $1; exit } }' "$tmp_sum")"
  [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "memory-mcp: checksum missing for $asset" >&2; exit 1; }
  curl -fsSL "${release%/}/$asset" -o "$tmp_bin"
  actual="$(hash_file "$tmp_bin")"
  expected_lc="$(printf '%s' "$expected" | tr 'A-F' 'a-f')"
  actual_lc="$(printf '%s' "$actual" | tr 'A-F' 'a-f')"
  [[ "$actual_lc" == "$expected_lc" ]] || { echo "memory-mcp: checksum mismatch for $asset" >&2; exit 1; }
  chmod +x "$tmp_bin"
  mv -f "$tmp_bin" "$bin"
  printf '%s\n' "$expected_lc" > "$tmp_sum"
  mv -f "$tmp_sum" "$sum"
  trap - EXIT HUP INT TERM
fi

# The store lives at <root>/.agents/memory ($MEMORY_DIR overrides). The
# launcher lives at <root>/.agents/mcp/memory, so the root is three levels up.
mem="${MEMORY_DIR:-"$(cd "$here/../../.." && pwd)/.agents/memory"}"
exec "$bin" -dir "$mem" "$@"
