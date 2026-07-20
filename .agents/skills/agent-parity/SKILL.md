---
name: agent-parity
description: Run agent-parity project management commands (status, version, update, uninstall) for this project's shared cross-agent memory and skills environment. Use when the user asks to check, update, or remove the agent-parity setup.
---

# agent-parity management

Run the project-local management command from the repository root, picking the
invocation for the current operating system:

- Linux, macOS, or WSL: `./.agents/bin/agent-parity <command>`
- Windows PowerShell: `.\.agents\bin\agent-parity.cmd <command>`

Commands:

- `status` — check the installed files and the locally available agent CLIs.
- `version` — report the installed and latest version.
- `update` — fetch the latest release updater and re-apply binaries, launchers, registrations, skills wiring, Claude settings, and marker blocks.
- `uninstall` — remove the installed artifacts. Add `--purge` to also delete the memory store.

Run the chosen command with the shell tool and show the user its output. Always
invoke the vendored command above; never reimplement what it does.
