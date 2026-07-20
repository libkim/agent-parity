#!/usr/bin/env sh
set -eu

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) ;;
  *) echo "test_git_bash.sh must run in Git Bash on Windows" >&2; exit 2 ;;
esac

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
root=$(mktemp -d "${TMPDIR:-/tmp}/agent-parity-git-bash.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM
mkdir -p "$root/.agents/bin"
cp "$repo/templates/project-agent-parity.sh" "$root/.agents/bin/agent-parity"
cat > "$root/.agents/bin/agent-parity.cmd" <<'EOF'
@echo off
> "%~dp0dispatch.txt" echo %*
exit /b 0
EOF

for command in sync-claude self-heal update uninstall status version; do
  rm -f "$root/.agents/bin/dispatch.txt"
  env -u OS sh "$root/.agents/bin/agent-parity" "$command"
  actual=$(tr -d '\r\n' < "$root/.agents/bin/dispatch.txt")
  [ "$actual" = "$command" ] || { echo "$command dispatched as: $actual" >&2; exit 1; }
done

echo "Windows Git Bash dispatches every management command through agent-parity.cmd: OK"
