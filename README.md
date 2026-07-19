# agent-parity

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.png">
    <img src="assets/logo.png" alt="agent-parity" width="360">
  </picture>
</p>

<p align="center"><a href="README.md">English</a> · <a href="README.ko.md">한국어</a></p>

Every coding agent keeps its own memory, skills, and instruction files, so
switching agents — or sharing a repo with teammates — means each one behaves
differently and has to be set up again. agent-parity fixes that by making the shared environment (memory, skills,
instructions) **environment as code** committed to the repo: install once
and Claude Code, Codex, Cursor, and Antigravity share the same memory and read
the same skills and instructions (`AGENTS.md`).

## Features

- **Dependency-free** — runs as a single static binary; no Go, Node, or other runtime to install.
- **Non-invasive** — creates only project-scoped files; never touches global settings.
- **Zero-install** — commit it once and any machine that pulls the repo uses it right away, no reinstall.

## Supported agents (tested 2026-07-10)

| Agent | Baseline version |
| --- | --- |
| Claude Code | 2.1.197 |
| Codex CLI | 0.144.1 |
| Cursor Agent | 2026.06.24-00-45-58-9f61de7 |
| Antigravity CLI | 1.1.1 |

## Supported platforms

| OS | Architectures |
| --- | --- |
| Linux | x86_64, arm64 (incl. Termux/Android) |
| macOS | x86_64, arm64 |
| Windows | x86_64 |

## Usage

Run the install command below in your project's root, then restart your agent
session.

### Install

Linux/macOS/WSL:

```sh
(
  repo=libkim/agent-parity
  latest=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")
  tag=${latest##*/}
  case "$tag" in v*) ;; *) echo "could not resolve latest agent-parity release" >&2; exit 1 ;; esac
  export AGENT_PARITY_RAW="https://raw.githubusercontent.com/$repo/$tag"
  export AGENT_PARITY_RELEASE="https://github.com/$repo/releases/download/$tag"
  export AGENT_PARITY_VERSION="$tag"
  installer=$(mktemp "${TMPDIR:-/tmp}/agent-parity-install.XXXXXX")
  trap 'rm -f "$installer"' EXIT HUP INT TERM
  curl -fsSL "$AGENT_PARITY_RAW/install.sh" -o "$installer"
  sh "$installer" install
)
```

Native Windows PowerShell:

```powershell
$repo = "libkim/agent-parity"
$tag = (irm "https://api.github.com/repos/$repo/releases/latest").tag_name
if ($tag -notmatch '^v') { throw "could not resolve latest agent-parity release" }
$oldRaw, $oldRelease, $oldVersion = $env:AGENT_PARITY_RAW, $env:AGENT_PARITY_RELEASE, $env:AGENT_PARITY_VERSION
try {
  $env:AGENT_PARITY_RAW = "https://raw.githubusercontent.com/$repo/$tag"
  $env:AGENT_PARITY_RELEASE = "https://github.com/$repo/releases/download/$tag"
  $env:AGENT_PARITY_VERSION = $tag
  irm "$env:AGENT_PARITY_RAW/install.ps1" | iex
} finally {
  $env:AGENT_PARITY_RAW, $env:AGENT_PARITY_RELEASE, $env:AGENT_PARITY_VERSION = $oldRaw, $oldRelease, $oldVersion
}
```

### Adopting an existing setup

Installing on a project that already runs a memory server, shared skills, or its
own instructions leaves your existing files in place and makes no assumptions:

- A config that already lists other MCP servers gets agent-parity's
  memory-server entry added and the rest preserved. If a `memory` entry already
  exists but points at a different server, it is reported with a replacement
  snippet instead of overwritten — that entry is yours to swap.
- Any agent skills already in the project (`.claude`, `.codex`, or `.cursor`
  `skills/`) are moved into the shared `.agents/skills/` automatically, so you
  don't have to do anything.
- An `AGENTS.md` that already covers the memory tools gets a duplication note
  when the block is appended, so you can fold the overlap yourself.

### Approval

The `memory` MCP lets multiple agents use one memory the same way. Items marked 'Required' work only after you approve them yourself in the agent session, by choosing the allow option in its approval prompt.

| Agent | MCP server approval | Tool-call approval |
| --- | --- | --- |
| Claude Code | Not required | Not required |
| Codex CLI | Not required | Not required |
| Cursor Agent | Required | Not required |
| Antigravity CLI | Not required | Required |

### Commands

Install adds an `agent-parity` skill, so you can run these from inside any
agent — ask it to run the command (in Claude Code, `/agent-parity`) and it picks
the right invocation for your OS.

| Command | Description |
| --- | --- |
| `status` | Checks the project files and the locally available agent CLIs. |
| `version` | Reports the installed and latest version. |
| `update` | Re-applies everything at the latest release — pinned runtime metadata, launchers, registrations, skills wiring, Claude settings, and marker blocks. |
| `uninstall` | Removes the installed artifacts. Add `--purge` to delete the memory store as well. |

You can also run them directly from the project root:
`./.agents/bin/agent-parity <command>` on Linux/macOS/WSL, or
`.\.agents\bin\agent-parity.cmd <command>` on Windows PowerShell.

<details>
<summary><code>status</code> output</summary>

`status` does not inspect an already-running agent session, so it cannot tell
whether that session currently exposes the memory tools.

| Output | Value | Meaning |
| --- | --- | --- |
| `target` | `<path>` | Project directory being inspected. |
| `server` | `dev` | Development runtime metadata is installed. |
|  | `vX.Y.Z` | The project is pinned to this release; its version can be compared with the latest release. |
|  | `missing` | The pinned `VERSION` or `RELEASE` metadata is missing. |
| `launcher` | `ok` | The OS-appropriate launcher exists. |
|  | `missing` | The launcher is absent; agents cannot resolve the cached runtime. |
| `latest release` | `vX.Y.Z` | GitHub's latest release was found. |
|  | `unknown (network unavailable)` | The latest release could not be checked because the network request failed or returned an invalid release. |
| `update available` | `<installed> -> <latest>` | Printed only when both versions are valid semantic versions and the latest release is newer. |
| `mcp registrations` | `registered` | The agent config points to this install's launcher. |
|  | `registered for Windows` / `registered for Unix` | The config points to the launcher for the other OS. A trusted self-heal hook retargets it when the next agent session starts. |
|  | `points elsewhere` | A `memory` MCP entry exists, but it points to another launcher; it is deliberately not overwritten. |
|  | `config missing` | The agent config file is absent. |
|  | `not registered` | The config file exists but has no usable entry for this install. |
| `agent-specific diagnostics` | CLI found / not found, registration result | Extra checks offered by the installed agent CLI. These are not a check of the current agent session's tool visibility. |
| `self-heal hooks` | `registered` / `missing` | Whether Claude, Codex, Cursor, and Antigravity can retarget the memory launcher at session start. Codex requires the project hook to be reviewed and trusted. |
| `skills` | `<n> in .agents/skills; sync script present` | Shared skill source and Claude sync script are installed. |
|  | `sync wiring missing` | The Claude skill-sync script is absent. |
| `hook` | `registered` / `missing` | Whether Claude's session-start hook will sync skills into `.claude/skills`. |
| `AGENTS.md` | `memory block present` / `missing` | Whether the managed memory instruction block is present. |
| `memory store` | `<n> entries` / `missing` | Number of saved memory Markdown files, or that the store directory does not exist. |
| `git` | `all artifacts tracked` | Installed artifacts are eligible to sync through Git. |
|  | `IGNORED ...` | One or more installed artifacts are ignored and will not sync until `install` or `update` repairs the managed `.gitignore` block. |
| `parity` | `<file> exists ...` | An agent-specific instruction file would make agent behavior diverge; merge its content into `AGENTS.md`. |

</details>

### Caution

The memory store is plaintext in the repo, so a public repo exposes it.
agent-parity reminds agents to keep secrets out, but you're responsible for what
ends up stored.

## How it works

The portable wiring, release metadata, memory, and skills are committed to the
repo; MCP binaries are not. On first use, `run.sh` / `run.cmd` downloads only
the current platform's binary from the project's pinned release, verifies it
against `checksums.txt`, and stores it in a per-user cache shared by projects.
Install/update also places the current platform's small `agent-parity-config`
editor in that shared cache. Local management commands use it to parse and
edit JSON/TOML without starting the MCP server or downloading anything during
the command.
The default cache is `$XDG_CACHE_HOME/agent-parity` (or
`~/.cache/agent-parity`) on Unix and `%LOCALAPPDATA%\agent-parity\cache` on
Windows; `AGENT_PARITY_CACHE` overrides it. `uninstall` leaves this shared
cache alone. `.claude/` is generated per session from `.agents/` and stays out
of git. If the project's `.gitignore` would hide the tracked wiring, `install`
maintains a marker block and `uninstall` reverts it. Git is optional — it only
matters for sharing across machines or teammates.

agent-parity handles your content and its own wiring differently. In the agent
configs and Claude settings it merges only its own entries, so your other
settings there — and a `memory` entry you repoint at another server — are
preserved. The marker blocks in `AGENTS.md` and `.gitignore` and the generated
shims (launchers, command scripts, sync scripts, and the `agent-parity`
skill) are regenerated by `update` to stay current, so don't edit those copies;
`uninstall` removes what it added. Your memory store and your own skills in
`.agents/skills/` are never modified or deleted (`--purge` deletes the store on
request). Skills already
sitting in a per-agent folder (`.claude`, `.codex`, or `.cursor` `skills/`) are
moved into the shared `.agents/skills/` at install so every agent shares them;
after `uninstall`, a `.claude/skills` copy is left so Claude — which can't read
the shared folder — keeps its skills without the sync.

### Cross-OS self-heal

The committed MCP configs point to either `run.sh` or `run.cmd`. At session
start, the managed hooks inspect all four configs and change only an
agent-parity-owned `memory` command to the launcher for the current OS. A
user-supplied `memory` server is never overwritten. When a file changes, the
hook asks you to restart the current agent session because MCP tools were
loaded before the repair; an unchanged run is silent. The repair uses only the
installed local script; it never downloads or starts
the MCP server binary. Codex project hooks must be reviewed and trusted with
`/hooks` (or the Hooks UI) before they run.

### Memory

Each memory is a markdown file with `created`, `tags`, `strength`, and
`lastAccessed` frontmatter. `memory_search` scores entries by
`match × exp(-ageDays / strength)` and bumps `strength` on recall, so
often-recalled memories keep ranking high while long-unused ones fall in the
results.

### Skills

Drop standard Agent Skills (`<name>/SKILL.md`) into `.agents/skills/`. Codex,
Cursor, and Antigravity CLI load them from there directly. For Claude Code, the
installed SessionStart hook calls `.agents/bin/agent-parity sync-claude`; the
project-local launcher selects `sync-claude.sh` on Unix or `sync-claude.ps1` on
native Windows. That recreates `.claude/skills` and `.claude/settings.json`
from the `.agents/` source at the start of every session. A separate Claude
SessionStart hook runs MCP self-heal independently. Edit only the source;
the generated copy is disposable.
`.claude/settings.local.json` is never touched, so machine-local settings stay
local.

## Files the install creates

| Path | Contents |
| --- | --- |
| `.agents/mcp/memory/` | memory server launchers plus pinned `VERSION` and `RELEASE` metadata; no binaries |
| `.agents/bin/` | project-local launchers (`agent-parity`, `agent-parity.cmd`) |
| `.agents/memory/` | the memory store — one markdown file per memory |
| `.agents/skills/` | shared skills source (yours to fill) |
| `.agents/skills/agent-parity/` | managed skill for running the management commands from any agent |
| `.agents/scripts/common.{sh,ps1}` | shared functions used by the local management commands |
| `.agents/scripts/{status,version,uninstall}.{sh,ps1}` | separate project-local management commands |
| `.agents/scripts/sync-claude.{sh,ps1}` | sync script that mirrors skills into `.claude` |
| `.agents/scripts/self-heal.{sh,ps1}` | retargets managed MCP registrations to the current OS launcher |
| `.agents/claude/settings.json` | Claude settings source with the platform-neutral sync hook |
| `.agents/mcp_config.json` | memory server registered for Antigravity CLI |
| `.agents/hooks.json` | Antigravity self-heal hook |
| `.mcp.json` | memory server registered for Claude Code |
| `.cursor/mcp.json` | memory server registered for Cursor |
| `.cursor/cli.json` | memory-tool auto-approval allowlist for Cursor |
| `.cursor/hooks.json` | Cursor session-start self-heal hook |
| `.codex/config.toml` | memory server registered for Codex |
| `.codex/hooks.json` | Codex session-start self-heal hook (requires trust) |
| `AGENTS.md` | instruction block, delimited by markers |
| `CLAUDE.md` | `@AGENTS.md` import wrapper |

`install.sh` / `install.ps1` are remote install-only entrypoints. For
`agent-parity update`, the project launcher resolves the latest release and
runs that release's remote `update.sh` / `update.ps1`; no updater is kept in
`.agents/scripts`.

`uninstall` is fully offline and never starts the MCP launcher. Native Windows
uses PowerShell's JSON support; the Unix command uses the verified
`agent-parity-config` editor installed in the shared cache. Neither path needs
Python or another user-installed runtime.

## License

MIT
