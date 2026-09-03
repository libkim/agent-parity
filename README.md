<p align="center">
  <img src="assets/app-icon.png" alt="agent-parity" width="360">
</p>

<h1 align="center">agent-parity</h1>

<p align="center"><a href="README.md">English</a> · <a href="README.ko.md">한국어</a></p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/demo-dark.gif">
    <img src="assets/demo-light.gif" alt="One environment, every agent: memory and skills added in one agent are committed to the repo and shared across Claude Code, Codex, Cursor, and Antigravity" width="820">
  </picture>
</p>

A coding agent's memory usually lives on your machine, in your home directory
rather than in the repo, so it never follows the project to another machine or a
teammate. Skills and instructions can be committed and travel, but each agent
keeps its own, so they drift as you switch agents.

agent-parity turns both into plain files in your repo. Once committed, they become **environment as code**, versioned alongside your source. The memory
store lives in the repo, so cloning it to a new machine or handing it to a
teammate carries the context along, and whoever receives it uses it from the
next session with no install command to run; a bundled merge driver even
reconciles edits made on two machines at once. Skills and instructions become
one shared definition that Claude Code, Codex, Cursor, and Antigravity all read,
so they stay consistent instead of diverging per agent.

## Features

- **Dependency-free**: no package manager to set up and no packages to install.
  The shared environment is plain files in your repo, and the helpers ship as
  small native binaries.
- **Non-invasive**: changes project settings only, never global agent settings,
  and merges just its own entries so your other settings stay intact. The files
  and settings agent-parity owns and regenerates on `update` are its managed files.
- **Zero-install**: commit the wiring once, and a fresh clone needs no install
  or update command. The setup activates on the next agent session.

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
| Linux | x86_64, arm64 |
| macOS | x86_64, arm64 |
| Windows | x86_64 |

## Usage

Run the install command below in your project's root, then restart your agent
session.

### Install

POSIX sh (Linux/macOS):

```sh
curl -fsSL https://github.com/libkim/agent-parity/releases/latest/download/install.sh | sh
```

PowerShell (Windows):

```powershell
irm https://github.com/libkim/agent-parity/releases/latest/download/install.ps1 | iex
```

An install or `update` takes effect from the next session. A running session
keeps using the previous setup and works normally until you restart it.

### Adopting an existing setup

Installing on a project that already runs a memory server, shared skills, or its
own instructions preserves existing content and makes no assumptions. Existing
per-agent skills may be relocated into the shared skill source as described
below.

- A config that already lists other MCP servers gets agent-parity's
  memory-server entry added and the rest preserved. If a `memory` entry already
  exists but points at a different server, it is reported with a replacement
  snippet instead of overwritten. That entry is yours to swap.
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

Claude Code's pre-approval needs the exact project folder trusted. If only a
parent directory is trusted, the trust dialog is skipped but the memory server
still prompts for approval once. This is a confirmed Claude Code bug
([claude-code#79612](https://github.com/anthropics/claude-code/issues/79612)), pending an upstream fix.

### Commands

agent-parity exposes these management commands as an `agent-parity` skill, so each agent can run
them through its own skill interface.

| Command | Description |
| --- | --- |
| `status` | Checks the project files and the locally available agent CLIs. |
| `version` | Reports the installed and latest version. |
| `update` | Exits without changes when the installed version is current; otherwise applies the latest release's runtime metadata, launchers, registrations, skills wiring, Claude settings, and marker blocks. |
| `uninstall` | Removes project wiring while leaving the shared executable cache and, by default, the memory store. Add `--purge` to delete the memory store as well. |

| Where | Automatic skill invocation | Manual skill invocation |
| --- | --- | --- |
| Claude Code | "update agent-parity" | `/agent-parity update` |
| Codex CLI | "update agent-parity" | `$agent-parity update` |
| Cursor Agent | "update agent-parity" | `/agent-parity` and pick it |
| Antigravity CLI | "update agent-parity" | — |
| POSIX sh (Linux/macOS) | — | `./.agent-parity/bin/agent-parity update` |
| PowerShell (Windows) | — | `.\.agent-parity\bin\agent-parity.cmd update` |

<details>
<summary><code>status</code> output</summary>

The CLI `status` command does not inspect an already-running agent session. When
an agent runs it in response to a conversational request, the managed agent
instructions additionally require checking whether that session exposes the
memory tools, then recommending a session restart or offering configuration-file
inspection according to the reported wiring state.

| Output | Value | Meaning |
| --- | --- | --- |
| `target` | `<path>` | Project directory being inspected. |
| `server` | `vX.Y.Z (shared cache, downloaded on demand)` | Pinned release version. The platform binary is not vendored in the repo; the launcher fetches it into the shared cache on first use. Comparable with the latest release. |
|  | `dev (shared cache, downloaded on demand)` | Dev metadata is pinned instead of a release. |
|  | `missing` | The pinned `VERSION` or `RELEASE` metadata is absent. |
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
| `claude wrapper` | `registered (CLAUDE.md)` / `missing` / `not registered` | Whether `CLAUDE.md` is the `@AGENTS.md` import wrapper; a pre-existing non-wrapper `CLAUDE.md` is preserved. |
| `agent-specific diagnostics` | CLI found / not found, registration result | Extra checks offered by the installed agent CLI. These are not a check of the current agent session's tool visibility. |
| `self-heal hooks` | `registered` / `missing` | Whether the managed hooks can retarget the memory launcher. Claude and Codex use `SessionStart`, Cursor uses `sessionStart`, and Antigravity uses `PreInvocation`. Codex requires the project hook to be reviewed and trusted. |
| `skills` | `<n> in .agents/skills; sync script present` | Count of your own skills, plus the shared source and Claude sync script. |
|  | `sync wiring missing` | The Claude skill-sync script is absent. |
|  | `shipped skill <name>: present` / `missing` | Whether each managed skill (`agent-parity`, `write-requirement`, `write-governance`) is installed. |
| `hook` | `registered` / `missing` | Whether Claude's session-start hook will sync skills into `.claude/skills`. |
| `cursor cli` | `memory allowlist present` / `allowlist missing` | Whether `.cursor/cli.json` grants Cursor auto-approval for the memory tools. |
| `AGENTS.md` | `agent-parity instruction block present` / `agent-parity instruction block missing` | Whether the managed product instruction block is present. |
| `memory store` | `<n> entries` / `missing` | Number of saved memory Markdown files, or that the store directory does not exist. |
| `git` | `all artifacts tracked` | Installed artifacts are eligible to sync through Git. |
|  | `IGNORED ...` | One or more installed artifacts are ignored and will not sync until `install` or a newer-version `update` repairs the managed `.gitignore` block. |
|  | `memory merge driver: registered` / `missing` | Whether the git merge driver for `.agent-parity/memory` files is registered in `.git/config`. |
|  | `pre-push guard: registered` / `a pre-push hook is in place ...` / `missing` | Whether the pre-push hook that blocks pushing uncommitted managed files is installed. When another pre-push hook already occupies the entry point, it reports how to wire the guard in instead. See [Git pre-push hooks](#git-pre-push-hooks). |
| `parity` | `<file> exists ...` | An agent-specific instruction file would make agent behavior diverge; merge its content into `AGENTS.md`. |

</details>

### Git pre-push hooks

agent-parity installs a `pre-push` hook that runs `.agent-parity/scripts/pre-push.sh`,
which blocks a push while any managed file is uncommitted, so cross-machine
sharing does not silently break. git runs only one hook per event, so the hook is
installed only when the pre-push entry point is empty or already ours. That entry
point is `.git/hooks/pre-push`, or, if a hook manager like husky set
`core.hooksPath`, the `pre-push` file in that directory.

To run your own checks alongside the guard, make your own hook call
`.agent-parity/scripts/pre-push.sh`:

- **If a pre-push hook is already there** (your own, or a hook manager's such as
  husky), agent-parity leaves it alone; add a line that runs
  `.agent-parity/scripts/pre-push.sh` to it.
- **If agent-parity installed the hook and you now want your own checks**, put
  your own pre-push hook at that entry point and add a line that runs
  `.agent-parity/scripts/pre-push.sh` to it. Do not edit the hook agent-parity
  installed, since install and update regenerate it and uninstall removes it.

### Caution

The memory store is plaintext in the repo, so a public repo exposes it.
agent-parity reminds agents to keep secrets out, but you're responsible for what
ends up stored.

## How it works

The portable wiring, release metadata, memory, and skills are committed to the
repo; MCP binaries are not. On first use, the `run.sh` / `run.cmd` launcher that
runs the memory server downloads only the current platform's binary from the
project's pinned release, verifies it
against `checksums.txt`, and stores it in a per-user cache shared by projects.
Install/update also places the current platform's small `agent-parity-config`
editor in that shared cache. On a fresh pull with an empty cache, self-heal
downloads and verifies the same pinned editor automatically. Configuration-related
management commands use the cached editor to parse and edit JSON/TOML without
starting or downloading the MCP server. `status` and `version` make only a
bounded network request for the latest-release field.
The default cache is `$XDG_CACHE_HOME/agent-parity` (or
`~/.cache/agent-parity`) on Unix and `%LOCALAPPDATA%\agent-parity\cache` on
Windows; `AGENT_PARITY_CACHE` overrides it. `uninstall` leaves this shared
cache alone. Claude artifacts are generated from the tracked source: `.claude/skills/`
is ignored, while the generated `.claude/settings.json` is committed so a
fresh pull already contains the hooks needed to regenerate it. If the project's
`.gitignore` would hide the tracked wiring, `install` maintains a marker block
and `uninstall` reverts it. Git is optional. It only matters for sharing across
machines or teammates.

agent-parity handles your content and its own wiring differently. In the agent
configs and Claude settings it merges only its own entries, so your other
settings there (and a `memory` entry you repoint at another server) are
preserved. The marker blocks in `AGENTS.md` and `.gitignore` and the generated
shims (launchers, command scripts, sync scripts, and the `agent-parity`
skill) are regenerated by `update` to stay current, so don't edit those copies;
`uninstall` removes what it added. Your memory store and your own skills in
`.agents/skills/` are never modified or deleted. `--purge` deletes the store on
request. Skills already sitting in a per-agent `.claude`, `.codex`, or `.cursor`
`skills/` folder are moved into the shared `.agents/skills/` at install so every
agent shares them; after `uninstall`, a `.claude/skills` copy is left so Claude,
which can't read the shared folder, keeps its skills without the sync.

### Configuration merge policy

Install and update apply the same ownership rules to every agent configuration:

- A dedicated agent-parity namespace is replaced completely with its canonical
  form; descendants are not validated individually.
- An object whose command is an exact current or legacy agent-parity command is
  owned and replaced completely with its canonical form.
- In a shared array, agent-parity validates the array itself but treats unrelated
  members as opaque; it replaces or removes only exactly identified managed
  members and appends a missing managed member.
- A same-named object whose ownership cannot be proved is preserved and named in
  a warning that asks the user to edit it manually.
- Uninstall applies the same identifiers in reverse and removes only managed
  namespaces, objects, fields, and array members.

The command completes the other files after a configuration warning and prints
a final warning count, so one agent's malformed or conflicting settings do not
prevent the others from converging.

### Cross-OS self-heal

Self-heal is a managed hook that runs at the start of a session and repairs the
config to match the current OS on its own. The committed MCP configs point to
either `run.sh` or `run.cmd`. The managed hooks inspect all four configs and
change only an agent-parity-owned
`memory` command to the launcher for the current OS. Claude and Codex run this
at `SessionStart`, Cursor at `sessionStart`, and Antigravity at
`PreInvocation`. A user-supplied `memory` server is never overwritten. When a
file changes, the hook asks you to restart the current agent session because
MCP tools may already have loaded before the repair; an unchanged run is
silent. With an empty cache, the hook downloads and verifies only the pinned
config editor; it never downloads or starts the MCP server binary. Codex
project hooks must be reviewed and trusted with `/hooks` (or the Hooks UI)
before they run.

### Memory

The memory server agent-parity installs stores memories as files and exposes the
tools an agent calls.

| Tool | What it does |
| --- | --- |
| `memory_add` | Save a memory |
| `memory_recent` | Return the newest context memories, latest first |
| `memory_search` | Search tags and body keywords, ranking a tag match above a body-text match |
| `memory_get` | Fetch one memory by id |
| `memory_update` | Retire a governance rule: set its status to deprecated or merged |
| `memory_governance` | List governance by status, retired ones included |

Each memory is a markdown file with `created` and `tags` frontmatter. Ranking is
static, so reading never rewrites a file.

agent-parity turns off the agent's built-in auto-memory, so an agent's memories
land in this one shared store rather than the agent's own machine-local one.

A memory has one of two types. **Context** (the default) is ordinary working
memory, returned by `memory_recent` and `memory_search`. **Governance**
(`memory_add` with `type: governance`) is a standing project rule: the server
folds every governance memory into its startup instructions, so each session
receives them automatically, and they are kept out of `memory_recent` and
`memory_search` so they never crowd the working results. Keep governance small
and curated, since it costs context in every session; a governance memory saved
mid-session applies to the next session onward, and to the current one it is
already in the conversation. A governance rule that no longer holds, or that was
folded into a broader one, is retired with `memory_update`: setting its status
to `deprecated` or `merged` drops it from the startup instructions while keeping
the file for history. The lifecycle covers governance only, since it
decides what gets injected and context memories never are. Retirement is
one-way: to make a retired rule apply again, write the current rule as a new
governance memory rather than reviving text whose reasons are no longer on
record.
`memory_governance` lists the rules by status, retired ones included, so what
was retired can be reviewed before writing a replacement; `memory_recent` and
`memory_search` never return governance. The injected rules
are each prefixed with their memory id so an agent can retire one in place.

A memory is normally created once under a unique id, so two machines rarely
touch the same file. When both sides explicitly edit the same file, a bundled
git merge driver unions the tags and keeps the body if only one side changed
it; a body edited differently on both sides conflicts, as it should.

Cross-machine sharing only works if these files are committed, so a bundled
pre-push hook refuses a push while any managed file is uncommitted (see
[Git pre-push hooks](#git-pre-push-hooks)).

### Skills

Drop standard Agent Skills (`<name>/SKILL.md`) into `.agents/skills/`. Codex,
Cursor, and Antigravity CLI load them from there directly. For Claude Code, the
installed SessionStart hook calls `.agent-parity/bin/agent-parity sync-claude`; the
project-local launcher selects `sync-claude.sh` on Unix or `sync-claude.ps1` on
Windows. That recreates `.claude/skills` and `.claude/settings.json`
from the tracked source at the start of every session. A separate Claude
SessionStart hook runs MCP self-heal independently. Edit only the source;
the generated copy is disposable.
`.claude/settings.local.json` is never touched, so machine-local settings stay
local.

Installation also writes its own skills into this source: `agent-parity` (the
management commands), plus the authoring skills `write-requirement` (turn a
request into a testable requirement) and `write-governance` (write a standing
project rule). Like the launchers, these are regenerated on `update`, so edit
your own skills, not these.

## Files the install creates

| Path | Contents |
| --- | --- |
| `.agent-parity/mcp/memory/` | memory server launchers plus pinned `VERSION` and `RELEASE` metadata; no binaries |
| `.agent-parity/memory/` | the memory store: one markdown file per memory |
| `.agents/skills/` | shared skills source (yours to fill) |
| `.agents/skills/agent-parity/` | managed skill for running the management commands from any agent |
| `.agents/skills/write-requirement/` | managed skill for turning a request into a testable requirement |
| `.agents/skills/write-governance/` | managed skill for writing a standing project rule |
| `.agent-parity/bin/` | project-local launchers (`agent-parity`, `agent-parity.cmd`) |
| `.agent-parity/scripts/common.{sh,ps1}` | shared functions used by the local management commands |
| `.agent-parity/scripts/{status,version,uninstall}.{sh,ps1}` | separate project-local management commands |
| `.agent-parity/scripts/sync-claude.{sh,ps1}` | sync script that mirrors skills into `.claude` |
| `.agent-parity/scripts/self-heal.{sh,ps1}` | retargets managed MCP registrations to the current OS launcher |
| `.agent-parity/scripts/merge-memory.sh` | git merge driver that resolves concurrent memory recalls |
| `.agent-parity/scripts/pre-push.sh` | pre-push guard that blocks a push while managed files are uncommitted |
| `.agent-parity/claude/settings.json` | Claude settings source with the platform-neutral sync hook |
| `.agents/mcp_config.json` | memory server registered for Antigravity CLI |
| `.agents/hooks.json` | Antigravity self-heal hook |
| `.claude/settings.json` | generated Claude settings bootstrap; committed and refreshed from `.agent-parity/claude/settings.json` |
| `.claude/skills/` | generated Claude skill mirror; ignored by Git and refreshed at session start |
| `.codex/config.toml` | memory server registered for Codex |
| `.codex/hooks.json` | Codex session-start self-heal hook (requires trust) |
| `.cursor/mcp.json` | memory server registered for Cursor |
| `.cursor/cli.json` | memory-tool auto-approval allowlist for Cursor |
| `.cursor/hooks.json` | Cursor session-start self-heal hook |
| `.mcp.json` | memory server registered for Claude Code |
| `AGENTS.md` | instruction block, delimited by markers |
| `CLAUDE.md` | `@AGENTS.md` import wrapper |
| `.gitattributes` | managed block routing memory files to the merge driver and pinning agent-parity's own shell scripts to LF |
| `.gitignore` | managed marker block when exclusions would hide installed wiring or generated Claude files |

`install.sh` / `install.ps1` are remote install-only entrypoints. For
`agent-parity update`, the project launcher downloads the latest release's
version-stamped `update.sh` / `update.ps1` asset. That embedded version selects
the matching Raw templates and config-editor asset; it also pins the MCP
launcher metadata to that release. No updater is kept in `.agent-parity/scripts`.

`uninstall` is fully offline and never starts the MCP launcher. Windows
and Unix both use the verified `agent-parity-config` editor installed in the
shared cache for structured JSON/TOML changes. Neither path needs Python or
another user-installed runtime.
