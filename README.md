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
- **Non-invasive** — creates only project-scoped files (committed to the repo); never touches global settings.
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
curl -fsSL https://raw.githubusercontent.com/libkim/agent-parity/main/install.sh | sh -s -- install
```

Native Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/libkim/agent-parity/main/install.ps1 | iex
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

After the first install, use the project-local management script. Run each
command as `./.agents/bin/agent-parity <command>` on Linux/macOS/WSL or
`.\.agents\bin\agent-parity.cmd <command>` on Windows PowerShell. When you run
the bootstrap script directly, `[dir]` defaults to the current directory.

| Command | Description |
| --- | --- |
| `status` | Checks the project files and the locally available agent CLIs. |
| `version` | Reports the installed version (it stamps the whole environment and is carried by the memory server binary, which also answers `.agents/mcp/memory/dist/memory-mcp-<os>-<arch> -version`). |
| `update` | Re-applies everything at the latest release — binaries, launchers, registrations, skills wiring, Claude settings, and the marker blocks. |
| `uninstall` | Removes the installed artifacts. Add `--purge` to delete the memory store as well. |

<details>
<summary><code>status</code> output</summary>

`status` does not inspect an already-running agent session, so it cannot tell
whether that session currently exposes the memory tools.

| Output | Value | Meaning |
| --- | --- | --- |
| `target` | `<path>` | Project directory being inspected. |
| `server` | `dev` | A locally built current-source binary: it supports `-version`, but no release version was stamped into it. |
|  | `vX.Y.Z` | A release-stamped binary; its version can be compared with the latest release. |
|  | `unknown (pre-versioning build)` | The binary exists and runs, but does not support `-version`; it was built before version reporting was added. |
|  | `missing` | The binary for this OS and architecture is missing from the expected `dist/` path. |
| `launcher` | `ok` | The OS-appropriate launcher exists. |
|  | `missing` | The launcher is absent; agents cannot start the bundled binary. |
| `latest release` | `vX.Y.Z` | GitHub's latest release was found. |
|  | `unknown` | The latest release could not be checked, for example because the network is unavailable. |
| `update available` | `<installed> -> <latest>` | Printed only when both versions are valid semantic versions and the latest release is newer. |
| `mcp registrations` | `registered` | The agent config points to this install's launcher. |
|  | `registered for Windows` / `registered for Unix` | The config points to the launcher for the other OS; run `install` or `update` on this OS to retarget it. |
|  | `points elsewhere` | A `memory` MCP entry exists, but it points to another launcher; it is deliberately not overwritten. |
|  | `config missing` | The agent config file is absent. |
|  | `not registered` | The config file exists but has no usable entry for this install. |
| `agent-specific diagnostics` | CLI found / not found, registration result | Extra checks offered by the installed agent CLI. These are not a check of the current agent session's tool visibility. |
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

Everything installed is committed to the repo. The first machine runs `install`
once; that vendors the binaries and wiring into the repo, so every machine that
later pulls it needs no reinstall. `.claude/` is generated per session from
`.agents/` and stays out of git. If the project's `.gitignore` would hide these
files, `install` maintains a marker block of rules to keep them tracked and
`uninstall` reverts it. Git is optional — it only matters for sharing across
machines or teammates.

agent-parity handles your content and its own wiring differently. In the agent
configs and Claude settings it merges only its own entries, so your other
settings there — and a `memory` entry you repoint at another server — are
preserved. The marker blocks in `AGENTS.md` and `.gitignore` and the generated
shims (launchers, sync scripts, the management command) are regenerated by
`update` to stay current, so don't edit those copies; `uninstall` removes what
it added. Your memory store and the skills in `.agents/skills/` are never
modified or deleted (`--purge` deletes the store on request). Skills already
sitting in a per-agent folder (`.claude`, `.codex`, or `.cursor` `skills/`) are
moved into the shared `.agents/skills/` at install so every agent shares them;
after `uninstall`, a `.claude/skills` copy is left so Claude — which can't read
the shared folder — keeps its skills without the sync.

### Memory

Each memory is a markdown file with `created`, `tags`, `strength`, and
`lastAccessed` frontmatter. `memory_search` scores entries by
`match × exp(-ageDays / strength)` and bumps `strength` on recall, so
often-recalled memories keep ranking high while long-unused ones fall in the
results.

### Skills

Drop standard Agent Skills (`<name>/SKILL.md`) into `.agents/skills/`. Codex,
Cursor, and Antigravity CLI load them from there directly. For Claude Code, the
installed SessionStart hook runs the platform sync script (`sync-claude.sh` on
Unix, `sync-claude.ps1` on native Windows), which recreates `.claude/skills`
and `.claude/settings.json` from the `.agents/` source at the start of every
session. Edit only the source; the generated copy is disposable.
`.claude/settings.local.json` is never touched, so machine-local settings stay
local.

## Files the install creates

| Path | Contents |
| --- | --- |
| `.agents/mcp/memory/` | memory server: launchers (`run.sh`, `run.cmd`) + `dist/<binary>` |
| `.agents/bin/` | project-local management command (`agent-parity`, `.cmd`, `.ps1`) |
| `.agents/memory/` | the memory store — one markdown file per memory |
| `.agents/skills/` | shared skills source (yours to fill) |
| `.agents/scripts/sync-claude.{sh,ps1}` | sync script that mirrors skills into `.claude`. Only the one for the installing OS is created (`.sh` on Unix, `.ps1` on Windows). |
| `.agents/claude/settings.json` | Claude settings source with the sync hook (OS-specific contents) |
| `.agents/mcp_config.json` | memory server registered for Antigravity CLI |
| `.mcp.json` | memory server registered for Claude Code |
| `.cursor/mcp.json` | memory server registered for Cursor |
| `.cursor/cli.json` | memory-tool auto-approval allowlist for Cursor |
| `.codex/config.toml` | memory server registered for Codex |
| `AGENTS.md` | instruction block, delimited by markers |
| `CLAUDE.md` | `@AGENTS.md` import wrapper (created if absent) |

## License

MIT
