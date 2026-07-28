#!/usr/bin/env sh
set -eu
[ "$#" -eq 0 ] || { echo "usage: agent-parity version" >&2; exit 2; }
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TARGET=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
. "$SCRIPT_DIR/common.sh"
platform

installed=$(installed_version)
latest=$(latest_version)
echo "installed: $installed"
echo "latest:    $latest"
show_update_notice "$installed" "$latest"
