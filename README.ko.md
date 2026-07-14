# agent-parity

<p align="center">
  <img src="assets/logo.png" alt="agent-parity" width="360">
</p>

[English](README.md) · [한국어](README.ko.md)

코딩 에이전트는 저마다 메모리, 스킬, 지침 파일을 따로 둡니다. 그래서 에이전트를 바꾸거나 팀과 저장소를 공유하면 동작이 제각각이고 매번 다시 설정해야 합니다. agent-parity는 이 문제를 해결합니다. 한 번 설치하면 Claude Code, Codex, Cursor, Antigravity가 같은 메모리를 공유하고 같은 스킬과 지침(`AGENTS.md`)을 읽으며, 이 모든 것이 git을 통해 저장소와 함께 옮겨 다닙니다.

## 지원 에이전트

2026-07-10 검증 기준입니다. 표는 agent-parity 설치 후에도 남는 승인 관문을 보여 줍니다. 패키지가 설치하는 프로젝트 설정으로 자동 승인할 수 있는 관문은 모두 자동으로 처리합니다. 프로젝트 신뢰는 언제나 수동 1회 프롬프트이고, `필요`로 남은 셀은 그 에이전트에서 프로젝트 파일로 자동화할 수 없는 관문입니다.

| 에이전트 | 기준 버전 | 프로젝트 신뢰 | MCP 서버 승인 | 도구 실행 승인 |
| --- | --- | --- | --- | --- |
| Claude Code | 2.1.197 | 필요 | 불필요 | 불필요 |
| Codex CLI | 0.144.1 | 필요 | 불필요 | 불필요 |
| Cursor Agent | 2026.06.24-00-45-58-9f61de7 | 필요 | 필요 | 불필요 |
| Antigravity CLI | 1.0.12 | 필요 | 불필요 | 필요 |

## 사용 방법

아래 설치 명령을 프로젝트 루트에서 실행한 뒤, 평소처럼 에이전트를 실행하면 끝입니다. 설치가 끝나면 새 세션에서 `memory` 서버가 네 가지 도구(`memory_recent`, `memory_add`, `memory_search`, `memory_get`)와 함께 올라오므로, 따로 할 일은 없습니다.

### 설치

Linux/macOS/WSL:

```sh
curl -fsSL https://raw.githubusercontent.com/libkim/agent-parity/main/install.sh | sh -s -- install
```

Native Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/libkim/agent-parity/main/install.ps1 | iex
```

설치 명령이 하는 일은 다음과 같습니다.

- 지원 플랫폼용 사전 빌드 바이너리를 내려받습니다(호스트에 Go가 필요 없습니다). 커밋해 두면 저장소를 pull한 어떤 머신에서도 추가 설정 없이 동작합니다.
- 프로젝트 로컬 관리 스크립트(`.agents/bin/agent-parity`)를 설치합니다.
- 각 에이전트 설정에 `memory` 서버를 등록합니다. 기존 설정에는 항목을 병합해 넣고 다른 MCP 서버는 그대로 둡니다(JSON은 다시 파싱하고, TOML은 테이블을 덧붙입니다). 이미 다른 서버를 가리키는 `memory` 항목이 있으면 건드리지 않고 교체용 스니펫만 출력합니다.
- 스킬 동기화를 배선하고, `AGENTS.md`에 지침 블록을 덧붙이고, `.agents/memory`에 메모리 저장소를 만듭니다.

## 관리 명령어

첫 설치 후에는 프로젝트 로컬 관리 스크립트를 씁니다. 각 명령은 Linux/macOS/WSL에서 `./.agents/bin/agent-parity <명령>`, Windows PowerShell에서 `.\.agents\bin\agent-parity.cmd <명령>`으로 실행합니다. bootstrap 스크립트를 직접 실행할 때 `[dir]`을 생략하면 현재 디렉터리를 대상으로 합니다.

- `status` — 프로젝트 파일과 로컬에서 쓸 수 있는 에이전트 CLI를 점검합니다.
- `version` — 설치된 서버 바이너리의 버전을 보고합니다. 바이너리 자체는 `.agents/mcp/memory/dist/memory-mcp-<os>-<arch> -version`으로도 답합니다.
- `update` — 바이너리와 배선 파일을 최신 릴리스로 교체합니다.
- `uninstall` — 설치 산출물을 제거합니다. `--purge`를 붙이면 메모리 저장소까지 함께 지웁니다.

<details>
<summary><code>status</code> 출력 항목</summary>

`status`는 이미 실행 중인 에이전트 세션 자체는 들여다보지 않으므로, 그 세션에 지금 메모리 도구가 노출돼 있는지는 알 수 없습니다.

| 출력 항목 | 값 | 의미 |
| --- | --- | --- |
| `target` | `<경로>` | 점검 대상 프로젝트 디렉터리입니다. |
| `server` | `dev` | 현재 소스로 로컬 빌드한 바이너리입니다. `-version`은 지원하지만 릴리스 버전이 주입되지 않았습니다. |
|  | `vX.Y.Z` | 릴리스 버전이 찍힌 바이너리입니다. 최신 릴리스와 버전을 비교할 수 있습니다. |
|  | `unknown (pre-versioning build)` | 바이너리는 존재하고 실행되지만 `-version`을 지원하지 않습니다. 버전 보고 기능이 추가되기 전 빌드입니다. |
|  | `missing` | 이 OS·아키텍처용 바이너리가 예상한 `dist/` 경로에 없습니다. |
| `launcher` | `ok` | 현재 OS용 런처가 있습니다. |
|  | `missing` | 런처가 없어 에이전트가 포함된 바이너리를 시작할 수 없습니다. |
| `latest release` | `vX.Y.Z` | GitHub에서 최신 릴리스를 찾았습니다. |
|  | `unknown` | 네트워크를 쓸 수 없는 경우처럼 최신 릴리스를 확인하지 못했습니다. |
| `update available` | `<설치본> -> <최신본>` | 두 버전이 모두 유효한 시맨틱 버전이고 최신 릴리스가 더 새로울 때만 출력합니다. |
| `mcp registrations` | `registered` | 에이전트 설정이 이 설치본의 런처를 가리킵니다. |
|  | `registered for Windows` / `registered for Unix` | 설정이 다른 OS용 런처를 가리킵니다. 현재 OS에서 `install` 또는 `update`를 실행해 재지정합니다. |
|  | `points elsewhere` | `memory` MCP 항목은 있지만 다른 런처를 가리킵니다. 기존 설정을 덮어쓰지 않습니다. |
|  | `config missing` | 에이전트 설정 파일이 없습니다. |
|  | `not registered` | 설정 파일은 있지만 이 설치본에 쓸 수 있는 등록 항목이 없습니다. |
| `agent-specific diagnostics` | CLI 있음/없음, 등록 결과 | 설치된 에이전트 CLI가 제공하는 추가 검사입니다. 현재 에이전트 세션의 도구 노출 여부를 검사하지는 않습니다. |
| `skills` | `<n> in .agents/skills; sync script present` | 공유 스킬 원본과 Claude 동기화 스크립트가 설치돼 있습니다. |
|  | `sync wiring missing` | Claude 스킬 동기화 스크립트가 없습니다. |
| `hook` | `registered` / `missing` | Claude 세션 시작 훅이 `.claude/skills`로 스킬을 동기화하는지 여부입니다. |
| `AGENTS.md` | `memory block present` / `missing` | 관리되는 메모리 지침 블록의 존재 여부입니다. |
| `memory store` | `<n> entries` / `missing` | 저장된 메모리 마크다운 파일 수, 또는 저장소 디렉터리 부재입니다. |
| `git` | `all artifacts tracked` | 설치 산출물이 Git으로 동기화될 수 있습니다. |
|  | `IGNORED ...` | 일부 산출물이 무시돼 있습니다. `install` 또는 `update`가 관리하는 `.gitignore` 블록을 고치기 전까지 동기화되지 않습니다. |
| `parity` | `<파일> exists ...` | 에이전트별 지침 파일이 동작을 갈라놓습니다. 내용을 `AGENTS.md`로 합쳐 주세요. |

</details>

## 설치 시 생성되는 파일

| 경로 | 내용 |
| --- | --- |
| `.agents/mcp/memory/` | 메모리 서버: 런처(`run.sh`, `run.cmd`) + `dist/<바이너리>` |
| `.agents/bin/` | 프로젝트 로컬 관리 명령(`agent-parity`, `.cmd`, `.ps1`) |
| `.agents/memory/` | 메모리 저장소 — 메모리 하나가 마크다운 파일 하나 |
| `.agents/skills/` | 공유 스킬 원본 (사용자가 채우는 곳) |
| `.agents/scripts/sync-claude.{sh,ps1}` | 스킬을 `.claude`로 미러링하는 동기화 스크립트. 설치한 OS의 것만 생성됩니다(Unix는 `.sh`, Windows는 `.ps1`). |
| `.agents/claude/settings.json` | 동기화 훅이 담긴 Claude 설정 원본 (OS별 내용) |
| `.agents/mcp_config.json` | Antigravity CLI 등록 |
| `.mcp.json` | Claude Code 등록 |
| `.cursor/mcp.json` | Cursor 등록 |
| `.cursor/cli.json` | Cursor 도구 자동 승인 허용목록 |
| `.codex/config.toml` | Codex 등록 |
| `AGENTS.md` | 마커로 구분된 지침 블록 |
| `CLAUDE.md` | `@AGENTS.md` 임포트 래퍼 (없을 때만 생성) |

관리 스크립트는 `.agents/bin/` 아래에 있는 프로젝트 로컬 파일입니다. 설치기는 셸 프로필, 사용자 PATH, 시스템 앱 등록 정보를 건드리지 않습니다. 더 짧은 명령을 원하면 `.agents/bin`을 직접 PATH에 추가하면 됩니다.

이 파일들은 모두 커밋합니다. 첫 머신에서 `install`을 한 번 실행하면 바이너리와 배선이 저장소에 벤더링(vendoring)되므로, **그 뒤로 저장소를 pull하는 다른 머신은 무설치(zero-install)** 입니다 — pull만 하면 실행되고 `npx`·`uvx` 기반 도구처럼 환경마다 다시 install하지 않습니다. 메모리 저장소와 스킬은 프로젝트의 맥락이고, `.claude/`는 세션마다 `.agents/`에서 다시 생성되므로 git 밖에 둡니다.

git은 선택입니다. 깃허브를 통해 공유하는 것은 팀이나 여러 머신과 함께 쓸 때만 필요하고, 한 머신에서만 쓴다면 git 없이도 설치·실행됩니다.

프로젝트의 `.gitignore`가 이 파일들을 가리면(예: 전부 무시하고 화이트리스트만 추적하는 정책), `install`과 `update`가 마커로 감싼 규칙 블록을 넣어 원본은 추적되고 생성물 `.claude/`는 추적되지 않게 합니다. `uninstall`은 그 블록을 제거하고, `status`는 아직 가려진 산출물이 있으면 경고합니다. `.gitignore`가 방해하지 않는 프로젝트에서는 아무것도 하지 않습니다.

## 거버넌스

도구가 건드리는 것은 네 부류로 나뉘고, 부류마다 규칙은 하나입니다.

1. **관리 영역** — `AGENTS.md`와 `.gitignore`의 마커로 구분된 블록, 그리고 그대로(verbatim) 써넣은 배선 파일들입니다: 에이전트 설정, `CLAUDE.md` 래퍼, 동기화 스크립트, 훅 설정. `install`이 만들고 `update`가 다시 쓰고 `uninstall`이 제거합니다. 소유권은 마커 또는 바이트 동일성으로 판별하므로, 사용자가 한 번 고치면 더 이상 도구의 것이 아니게 되어 건드리지 않습니다.
2. **함께 넣는 도구** — `.agents/mcp/memory/` 아래의 런처와 바이너리입니다. `update`가 교체하고 `uninstall`이 삭제합니다.
3. **사용자의 산출물** — 메모리 저장소와 `.agents/skills/`입니다. 수정도 삭제도 하지 않습니다. `--purge`를 주면 저장소만 삭제합니다. 기존 `.claude/skills`는 설치할 때 `.agents/skills/`로 승격합니다: 스킬은 self-contained 폴더라 이동이 기계적이고, Claude 전용 스킬이 공유 스킬이 됩니다. 이름이 충돌하면 `<이름>.from-claude`로 비켜 두니 직접 병합하면 됩니다.
4. **사용자의 산문** — `GEMINI.md`나 레거시 `.cursorrules`처럼 한 에이전트만 읽는 지침 파일입니다. 산문 병합은 기계가 아니라 편집의 일이므로, `install`과 `status`가 parity 위반으로 보고만 하고 절대 건드리지 않습니다.

`uninstall`은 1·2부류를 제거합니다. 내용이 있는 `.claude/skills` 미러는 정적 사본으로 남겨, 동기화 없이도 Claude Code가 스킬을 유지하게 합니다.

## 기존 설정이 있는 프로젝트에 도입하기

이미 메모리 서버, 공유 스킬, 자체 지침을 운영 중인 프로젝트에도 같은 부류 규칙이 그대로 적용되며, 아무것도 추측하지 않습니다.

- 다른 MCP 서버가 있는 설정에는 memory 항목을 병합하고 나머지는 보존합니다. 이미 다른 서버를 가리키는 `memory` 항목이 있으면 교체 스니펫과 함께 보고하며, 그 항목의 교체는 사용자가 합니다.
- 기존 동기화 스크립트와 훅은 그대로 두고, 기존 `.claude/skills`는 위에서 설명한 대로 승격합니다.
- 이미 메모리 도구를 다루는 `AGENTS.md`에는 블록을 덧붙일 때 중복 검토 안내를 출력합니다. 겹치는 부분은 사용자가 직접 합칩니다.

## 메모리 동작 방식

각 메모리는 `created`, `tags`, `strength`, `lastAccessed` 프론트매터를 가진 마크다운 파일입니다. `memory_search`는 `일치 × exp(-경과일 / strength)`로 점수를 매기고, 회상할 때 `strength`를 올립니다. 자주 쓰는 메모리는 살아남고 묵은 것은 가라앉습니다.

## 스킬 동작 방식

표준 Agent Skills(`<name>/SKILL.md`)를 `.agents/skills/`에 넣습니다. Codex, Cursor, Antigravity CLI는 거기서 바로 불러옵니다. Claude Code는 설치된 SessionStart 훅이 플랫폼 동기화 스크립트(Unix는 `sync-claude.sh`, native Windows는 `sync-claude.ps1`)를 실행해 세션이 시작될 때마다 `.agents/` 원본에서 `.claude/skills`와 `.claude/settings.json`을 다시 만듭니다. 수정은 원본에만 하고, 생성된 사본은 언제든 버려도 됩니다. `.claude/settings.local.json`은 절대 건드리지 않으므로 머신 로컬 설정은 로컬에 남습니다.

## 라이선스

MIT
