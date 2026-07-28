#!/usr/bin/env sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
root=$(mktemp -d "${TMPDIR:-/tmp}/agent-parity-markers.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM
TARGET=$root
. "$repo/templates/common.sh"

check_state() {
  name=$1 expected=$2 content=$3
  path="$root/$name"
  if [ "$content" = __missing__ ]; then
    rm -f "$path"
  else
    printf '%s' "$content" > "$path"
  fi
  actual=$(managed_block_state "$path" '<!-- agent-parity:begin -->' '<!-- agent-parity:end -->')
  [ "$actual" = "$expected" ] || { echo "$name: expected $expected, got $actual" >&2; exit 1; }
}

check_state missing absent __missing__
check_state clean absent 'user content
'
check_state valid valid '<!-- agent-parity:begin -->
managed
<!-- agent-parity:end -->
'
check_state begin-only invalid '<!-- agent-parity:begin -->
managed
'
check_state end-only invalid '<!-- agent-parity:end -->
'
check_state reversed invalid '<!-- agent-parity:end -->
managed
<!-- agent-parity:begin -->
'
check_state duplicate invalid '<!-- agent-parity:begin -->
managed
<!-- agent-parity:end -->
<!-- agent-parity:begin -->
'
check_state embedded invalid 'note: <!-- agent-parity:begin -->
<!-- agent-parity:end -->
'

echo "Unix managed marker states: OK"
