# agent-parity

<p align="center">
  <img src="assets/logo.png" alt="agent-parity" width="360">
</p>

[English](README.md) · [한국어](README.ko.md)

Every coding agent keeps its own memory, skills, and instruction files, so
switching agents — or sharing a repo with teammates — means each one behaves
differently and has to be set up again. agent-parity fixes that: install once
and Claude Code, Codex, Cursor, and Antigravity share the same memory and read
the same skills and instructions (`AGENTS.md`), all traveling with the repo
through git.

## Supported agents

Tested on 2026-07-10. The columns show what you still hit after installing
agent-parity, whose project config auto-approves every gate a project file
can. Project trust is always a manual one-time prompt; the remaining
`Required` cells are gates no project file can automate for that agent.

| Agent | Baseline version | Project trust | MCP server approval | Tool-call approval |
| --- | --- | --- | --- | --- |
| Claude Code | 2.1.197 | Required | Not required | Not required |
| Codex CLI | 0.144.1 | Required | Not required | Not required |
| Cursor Agent | 2026.06.24-00-45-58-9f61de7 | Required | Required | Not required |
| Antigravity CLI | 1.0.12 | Required | Not required | Required |

## Usage

Run the install command below in your project's root, then run your agent as
usual; that's it. After install a
new session brings up the `memory` server with its four tools (`memory_recent`,
`memory_add`, `memory_search`, `memory_get`), so there is nothing else to do.

### Install

Linux/macOS/WSL:

```sh
curl -fsSL https://raw.githubusercontent.com/libkim/agent-parity/main/install.sh | sh -s -- install
```

Native Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/libkim/agent-parity/main/install.ps1 | iex
```

The install command:

- Downloads the prebuilt binaries for every supported platform (no Go needed).
  Commit them and any machine that pulls the repo runs with no setup.
- Installs the project-local management script (`.agents/bin/agent-parity`).
- Registers the `memory` server in each agent's config. An existing config gets
  the entry merged in and other MCP servers preserved (JSON is reparsed, TOML
  gets the table appended); a `memory` entry that already points elsewhere is
  left untouched, with a replacement snippet printed.
- Wires the skills sync, appends an instruction block to `AGENTS.md`, and
  creates the store at `.agents/memory`.

## Commands

After the first install, use the project-local management script. Run each
command as `./.agents/bin/agent-parity <command>` on Linux/macOS/WSL or
`.\.agents\bin\agent-parity.cmd <command>` on Windows PowerShell. When you run
the bootstrap script directly, `[dir]` defaults to the current directory.

- `status` — checks the project files and the locally available agent CLIs.
- `version` — reports the installed server binary's version. The binary itself
  also answers `.agents/mcp/memory/dist/memory-mcp-<os>-<arch> -version`.
- `update` — replaces the binaries and wiring files with the latest release.
- `uninstall` — removes the installed artifacts. Add `--purge` to delete the
  memory store as well.

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

## Files the install creates

| Path | Contents |
| --- | --- |
| `.agents/mcp/memory/` | memory server: launchers (`run.sh`, `run.cmd`) + `dist/<binary>` |
| `.agents/bin/` | project-local management command (`agent-parity`, `.cmd`, `.ps1`) |
| `.agents/memory/` | the memory store — one markdown file per memory |
| `.agents/skills/` | shared skills source (yours to fill) |
| `.agents/scripts/sync-claude.{sh,ps1}` | sync script that mirrors skills into `.claude`. Only the one for the installing OS is created (`.sh` on Unix, `.ps1` on Windows). |
| `.agents/claude/settings.json` | Claude settings source with the sync hook (OS-specific contents) |
| `.agents/mcp_config.json` | Antigravity CLI registration |
| `.mcp.json` | Claude Code registration |
| `.cursor/mcp.json` | Cursor registration |
| `.cursor/cli.json` | Cursor tool auto-approval allowlist |
| `.codex/config.toml` | Codex registration |
| `AGENTS.md` | instruction block, delimited by markers |
| `CLAUDE.md` | `@AGENTS.md` import wrapper (created if absent) |

The management script is project-local under `.agents/bin/`; the installer does
not modify shell profiles, user PATH, or system application registries. If you
want a shorter command, add `.agents/bin` to your PATH yourself.

Commit all of it. The first machine runs `install` once; because that vendors
the binaries and wiring into the repo, every machine that later pulls the repo
is **zero-install** — it just pulls and runs, with no per-environment install
the way `npx`/`uvx`-based tools need. The store and skills are your project's
context; `.claude/` is generated per session from `.agents/` and stays out of
git.

Git is optional. Sharing through GitHub only matters when you work across
machines or teammates; a single-machine project installs and runs without git.

If the project's `.gitignore` would hide any of these files (say, an
ignore-everything whitelist policy), `install` and `update` maintain a marked
block of rules in it so the sources stay tracked and the generated `.claude/`
does not. `uninstall` removes the block, and `status` warns when artifacts are
still ignored. Projects whose `.gitignore` does not interfere are left
untouched.

## Governance

Everything the tool touches falls into four classes, each with one rule:

1. **Managed regions** — the marker-delimited blocks in `AGENTS.md` and
   `.gitignore`, plus wiring files written verbatim: agent configs, the
   `CLAUDE.md` wrapper, the sync script, the hook settings. Created by
   `install`, rewritten by `update`, removed by `uninstall`. Ownership is
   detected by marker or byte-identity, so once you edit one it stops being
   the tool's and is left alone.
2. **Vendored tools** — the launcher and binary under `.agents/mcp/memory/`.
   Replaced on `update`, deleted on `uninstall`.
3. **Your artifacts** — the memory store and `.agents/skills/`. Never
   modified, never deleted; `--purge` deletes the store on request.
   Pre-existing `.claude/skills` are adopted into `.agents/skills/` at
   install: a skill is a self-contained folder, so the move is mechanical,
   and it turns a Claude-only skill into a shared one. A name conflict is
   set aside as `<name>.from-claude` to merge manually.
4. **Your prose** — instruction files such as legacy `.cursorrules`, which
   only one agent reads. Merging prose is editorial, not mechanical, so
   `install` and `status` report them as parity breaks and never touch them.

`uninstall` removes classes 1 and 2. A non-empty `.claude/skills` mirror is
left as a static copy so Claude Code keeps its skills without the sync.

## Adopting an existing setup

On a project that already runs a memory server, shared skills, or its own
instructions, the same classes apply and nothing is guessed:

- A config with other MCP servers gets the memory entry merged in, the rest
  preserved. One that already has a `memory` entry pointing at a different
  server is reported with the replacement snippet; that entry is yours to swap.
- An existing sync script and hook are kept as they are; existing
  `.claude/skills` are adopted as described above.
- An `AGENTS.md` that already covers the memory tools gets a duplication note
  when the block is appended, so you can fold the overlap yourself.

## How memory works

Each memory is a markdown file with `created`, `tags`, `strength`, and
`lastAccessed` frontmatter. `memory_search` scores entries by
`match × exp(-ageDays / strength)` and bumps `strength` on recall, so
frequently used memories persist while stale ones sink.

## How skills work

Drop standard Agent Skills (`<name>/SKILL.md`) into `.agents/skills/`. Codex,
Cursor, and Antigravity CLI load them from there directly. For Claude Code, the
installed SessionStart hook runs the platform sync script (`sync-claude.sh` on
Unix, `sync-claude.ps1` on native Windows), which recreates `.claude/skills`
and `.claude/settings.json` from the `.agents/` source at the start of every
session. Edit only the source; the generated copy is disposable.
`.claude/settings.local.json` is never touched, so machine-local settings stay
local.

## License

MIT
