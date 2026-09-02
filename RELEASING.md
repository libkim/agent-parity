# Releasing

A release is cut by pushing a `v*` git tag. Everything version-specific is
derived from that tag — there are no version strings to bump by hand in the
source before tagging.

## How versioning flows (why nothing needs hand-editing)

- **The tag is the version.** `build.sh` reads it (`git describe`, or the
  `VERSION` env the CI passes) and stamps it into the binaries and into each
  release copy of `install.sh` / `install.ps1` / `update.sh` / `update.ps1`
  (the `PACKAGED_VERSION` / `$PackagedVersion` line — kept `"dev"` in source on
  purpose, replaced only in the published asset).
- **`.agents/mcp/memory/VERSION` and `RELEASE` are not release inputs.** They are
  written by `install`/`update` into a target project, pinned to the release
  they ran from. The value checked into this repo just reflects the last local
  install; the release process neither reads nor updates it. Do not bump it to
  cut a release.
- **README carries no version.** Install commands use
  `releases/latest/download/…`, so a new latest release is picked up with no doc
  edit.
- `go.mod` / `go.sum` are dependency versions, unrelated to the release.

## Before tagging

1. Working tree committed and pushed to `main`; `git status` clean.
2. No machine or personal data in tracked files (absolute home paths, usernames,
   local cache paths). Execution paths stay env/`$HOME`-derived, never
   hardcoded.
3. Commit messages carry no `Co-Authored-By` trailer.
4. Run the release gates the way CI does — `go test` alone does not cover the
   shell/PowerShell layer:
   ```sh
   go test ./...
   go test -tags configeditor ./...
   VERSION=v0.0.0-ci bash build.sh
   for t in test_release_assets test_markers test_uninstall test_install_markers \
            test_readme_install test_zero_install test_memory_merge test_update \
            test_pre_push test_launcher_store_dir test_gitattributes; do
     sh tests/$t.sh v0.0.0-ci 2>/dev/null || sh tests/$t.sh
   done
   ```
   PowerShell tests (`test_powershell_syntax`, `test_atomic_write`,
   `test_powershell_newlines`, `test_install_windows`,
   `test_windows_launcher_update`) need `pwsh`; if unavailable locally, rely on
   the CI `test-windows` job.

## Coverage across OS × agent × feature

Behavior is verified along three axes. The CI `test-unix` matrix runs Linux
amd64/arm64 and macOS intel/arm64; `test-windows` runs windows-latest. Keep this
table honest — when a feature or agent is added, a cell here should point at a
test, and a known gap should be named, not left blank.

Agent × feature (the four registered agents: Claude `.mcp.json`, Cursor, Codex,
Antigravity `.agents/mcp_config.json`):

| feature | Claude | Cursor | Codex | Antigravity |
| --- | --- | --- | --- | --- |
| MCP registration | zero_install(.sh/.ps1) | same | same | same |
| cross-OS self-heal | zero_install four-config loop | same | same | same |
| uninstall removal | uninstall.sh / install_windows.ps1 | same | same | same |
| hook convergence | install_windows.ps1, update.sh | cursor hooks | codex config | Antigravity block |
| Claude wrapper | claude_wrapper.ps1 | n/a | n/a | n/a |

Feature × OS (agent-neutral core):

| feature | unix | windows |
| --- | --- | --- |
| Go units (store/config/merge) | go test ×2 | go test ×2 |
| release assets + version stamp | test_release_assets.sh | release job |
| marker blocks | test_markers.sh | test_markers.ps1 |
| memory merge driver | test_memory_merge.sh | test_memory_merge.sh (git bash) |
| .gitattributes managed block | test_gitattributes.sh | (unix only; the LF pin it writes is what the windows checkout needs) |
| atomic write | (Go) | test_atomic_write.ps1 |
| update idempotence | test_update.sh | test_install_windows.ps1 |
| CRLF / newlines | (Go parseEntry) | test_powershell_newlines.ps1 |
| pre-push, shell path | test_pre_push.sh | n/a |
| pre-push, PowerShell path | n/a | test_pre_push_windows.ps1 |
| launcher command dispatch | (native sh launcher) | test_git_bash.sh (git bash → .cmd) |

Both installer paths for the pre-push dispatcher have behavior tests:
`test_pre_push.sh` drives the shell installer (unix), and
`test_pre_push_windows.ps1` drives `install.ps1` in a real git repo — covering
dispatcher install, user-hook preserve-as-`pre-push.user` + chain, uninstall
restore, and `core.hooksPath` deferral. (`test_install_windows.ps1` runs in a
non-git temp dir where `Test-GitRepo` short-circuits, so pre-push is verified by
the dedicated test, not there.)

## Cutting the release

1. Pick the next tag. The agent never bumps the version on its own — the user
   chooses the number.
2. `git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z`
3. The `release` workflow (`.github/workflows/release.yml`) triggers on the
   `v*` tag: it runs the unix matrix and the Windows job, builds assets with the
   tag baked in, and publishes the GitHub release via `softprops/action-gh-release`
   (which updates the release if the tag already exists).
4. Confirm the run is green and `releases/latest` resolves to the new tag.

## If a release fails

- The workflow failed and no GitHub release was created: amend the commit for
  the same patch version and move the tag, then retry. Do not bump to the next
  patch without the user's approval.
- A bad release was published: delete it and its tag
  (`gh release delete vX.Y.Z --cleanup-tag`), then re-cut once fixed.
