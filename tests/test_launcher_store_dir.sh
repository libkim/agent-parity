#!/usr/bin/env sh
# Both launchers must default the memory store to <root>/.agent-parity/memory.
# run.sh was updated during the .agents -> .agent-parity move but run.cmd was
# once left pointing at the retired .agents\memory, silently splitting the
# Windows store from the Unix one on a shared repo. Keep the two in step.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

grep -qF '.agent-parity/memory' "$repo/templates/run.sh" || {
	echo "run.sh: memory store default is not .agent-parity/memory" >&2; exit 1; }
grep -qF '.agent-parity\memory' "$repo/templates/run.cmd" || {
	echo "run.cmd: memory store default is not .agent-parity\\memory" >&2; exit 1; }

# Neither launcher may keep the retired .agents/... memory store path.
! grep -qF '.agents/memory' "$repo/templates/run.sh" || {
	echo "run.sh: stale .agents/memory store path" >&2; exit 1; }
! grep -qF '.agents\memory' "$repo/templates/run.cmd" || {
	echo "run.cmd: stale .agents\\memory store path" >&2; exit 1; }

echo "launchers default the store to .agent-parity/memory on both OSes: OK"
