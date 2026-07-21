# agent-parity

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.png">
    <img src="assets/logo.png" alt="agent-parity" width="360">
  </picture>
</p>

<p align="center"><a href="README.md">English</a> · <a href="README.ko.md">한국어</a></p>

코딩 에이전트는 저마다 메모리, 스킬, 지침 파일을 따로 둡니다. 그래서 에이전트를 바꾸거나 팀과 저장소를 공유하면 동작이 제각각이고 매번 다시 설정해야 합니다. agent-parity는 이 공유 환경(메모리·스킬·지침)을 저장소에 커밋하는 **코드형 환경(Environment as Code)** 으로 정의해 이 문제를 해결합니다. 한 번 설치하면 Claude Code, Codex, Cursor, Antigravity가 같은 메모리를 공유하고 같은 스킬과 지침(`AGENTS.md`)을 읽습니다.

## 특징

- **의존성 없음**: 메모리를 제공하는 `memory-mcp`와 JSON/TOML을
  안전하게 수정하는 `agent-parity-config`, 두 개의 정적 네이티브 실행 파일을
  사용합니다. Go·Node·Python 런타임은 필요하지 않습니다.
- **비침습**: 프로젝트 설정만 변경하고 에이전트 전역 설정은
  건드리지 않습니다. 릴리스 실행 파일은 여러 프로젝트가 공유하는 사용자별
  캐시에 저장합니다.
- **무설치**: 설치된 배선을 한 번 커밋하면 새 머신에서 install이나 update
  명령을 실행할 필요가 없습니다. 첫 에이전트 세션이 현재 플랫폼 실행 파일을
  자동으로 내려받아 검증하며, 크로스 OS 교정 뒤에는 에이전트 세션만 재시작하면
  됩니다.

## 지원 에이전트 (2026-07-10 검증 기준)

| 에이전트 | 기준 버전 |
| --- | --- |
| Claude Code | 2.1.197 |
| Codex CLI | 0.144.1 |
| Cursor Agent | 2026.06.24-00-45-58-9f61de7 |
| Antigravity CLI | 1.1.1 |

## 지원 플랫폼

| OS | 아키텍처 |
| --- | --- |
| Linux | x86_64, arm64 |
| macOS | x86_64, arm64 |
| Windows | x86_64 |

## 사용 방법

프로젝트 루트에서 설치 명령을 실행한 뒤 에이전트 세션을 재시작하세요.

### 설치

POSIX sh (Linux/macOS):

```sh
curl -fsSL https://github.com/libkim/agent-parity/releases/latest/download/install.sh | sh
```

PowerShell (Windows):

```powershell
irm https://github.com/libkim/agent-parity/releases/latest/download/install.ps1 | iex
```

### 기존 설정이 있는 프로젝트에 도입하기

이미 메모리 서버, 공유 스킬, 자체 지침을 운영 중인 프로젝트에 설치해도 기존 내용을 덮어쓰지 않고 임의로 판단하지 않습니다. 다만 기존 에이전트별 스킬은 아래 설명처럼 공유 스킬 원본으로 이동할 수 있습니다.

- 다른 MCP 서버가 이미 등록된 설정에는 agent-parity의 메모리 서버 항목만 추가하고 나머지는 그대로 둡니다. 이미 `memory`라는 이름의 항목이 다른 서버를 가리키고 있으면 덮어쓰지 않고 교체용 스니펫만 알려 주며, 그 항목의 교체는 사용자가 합니다.
- 프로젝트에 이미 있던 에이전트 스킬(`.claude`·`.codex`·`.cursor`의 `skills/`)은 공유 폴더 `.agents/skills/`로 자동으로 옮겨지니 별도 작업이 필요 없습니다.
- 이미 메모리 도구를 다루는 `AGENTS.md`에는 블록을 덧붙일 때 중복 검토 안내를 출력합니다. 겹치는 부분은 사용자가 직접 합칩니다.

### 승인

여러 에이전트가 메모리를 동일한 방식으로 사용할 수 있도록 `memory` MCP를 사용합니다. 표에서 '필요'로 표시된 항목은 에이전트 세션에서 뜨는 승인 창에서 허용을 선택해 직접 승인해야 사용할 수 있습니다.

| 에이전트 | MCP 서버 승인 | 도구 실행 승인 |
| --- | --- | --- |
| Claude Code | 불필요 | 불필요 |
| Codex CLI | 불필요 | 불필요 |
| Cursor Agent | 필요 | 불필요 |
| Antigravity CLI | 불필요 | 필요 |

Claude Code의 사전 승인은 정확한 프로젝트 폴더가 신뢰돼 있어야 적용됩니다. 상위 폴더만 신뢰된 경우 신뢰 다이얼로그는 생략되지만 memory 서버 승인 창이 한 번 뜹니다([claude-code#79612](https://github.com/anthropics/claude-code/issues/79612)).

### 관리 명령어

agent-parity는 관리 명령들을 `agent-parity` 스킬로 노출하므로, 각 에이전트가 자신의 스킬 인터페이스로 실행할 수 있습니다.

| 명령 | 설명 |
| --- | --- |
| `status` | 프로젝트 파일과 로컬에서 쓸 수 있는 에이전트 CLI를 점검합니다. |
| `version` | 설치된 버전과 최신 버전을 보고합니다. |
| `update` | 최신 릴리스로 관리 대상을 전부 다시 적용합니다: 고정 런타임 메타데이터·런처·등록·스킬 배선·Claude 설정·마커 블록. |
| `uninstall` | 프로젝트 배선을 제거하되 공유 실행 파일 캐시와, 기본적으로 메모리 저장소는 남깁니다. `--purge`를 붙이면 메모리 저장소도 지웁니다. |

| 위치 | 자동 스킬 호출 | 수동 스킬 호출 |
| --- | --- | --- |
| Claude Code | "agent-parity 업데이트해줘" | `/agent-parity update` |
| Codex CLI | "agent-parity 업데이트해줘" | `$agent-parity update` |
| Cursor Agent | "agent-parity 업데이트해줘" | `/agent-parity` 입력 후 선택 |
| Antigravity CLI | "agent-parity 업데이트해줘" | — |
| POSIX sh (Linux/macOS) | — | `./.agents/bin/agent-parity update` |
| PowerShell (Windows) | — | `.\.agents\bin\agent-parity.cmd update` |

<details>
<summary><code>status</code> 출력 항목</summary>

`status`는 이미 실행 중인 에이전트 세션 자체는 들여다보지 않으므로, 그 세션에 지금 메모리 도구가 노출돼 있는지는 알 수 없습니다.

| 출력 항목 | 값 | 의미 |
| --- | --- | --- |
| `target` | `<경로>` | 점검 대상 프로젝트 디렉터리입니다. |
| `server` | `vX.Y.Z (shared cache, downloaded on demand)` | 고정된 릴리스 버전입니다. 플랫폼 바이너리는 저장소에 넣지 않고, 런처가 처음 사용할 때 공유 캐시로 내려받습니다. 최신 릴리스와 비교할 수 있습니다. |
|  | `dev (shared cache, downloaded on demand)` | 릴리스 대신 개발용 메타데이터가 고정돼 있습니다. |
|  | `missing` | 고정된 `VERSION` 또는 `RELEASE` 메타데이터가 없습니다. |
| `launcher` | `ok` | 현재 OS용 런처가 있습니다. |
|  | `missing` | 런처가 없어 에이전트가 캐시된 런타임을 찾을 수 없습니다. |
| `latest release` | `vX.Y.Z` | GitHub에서 최신 릴리스를 찾았습니다. |
|  | `unknown (network unavailable)` | 네트워크 요청이 실패했거나 유효한 릴리스를 돌려주지 않아 최신 릴리스를 확인하지 못했습니다. |
| `update available` | `<설치본> -> <최신본>` | 두 버전이 모두 유효한 시맨틱 버전이고 최신 릴리스가 더 새로울 때만 출력합니다. |
| `mcp registrations` | `registered` | 에이전트 설정이 이 설치본의 런처를 가리킵니다. |
|  | `registered for Windows` / `registered for Unix` | 설정이 다른 OS용 런처를 가리킵니다. 신뢰된 self-heal 훅이 다음 에이전트 세션 시작 시 현재 OS용 런처로 재지정합니다. |
|  | `points elsewhere` | `memory` MCP 항목은 있지만 다른 런처를 가리킵니다. 기존 설정을 덮어쓰지 않습니다. |
|  | `config missing` | 에이전트 설정 파일이 없습니다. |
|  | `not registered` | 설정 파일은 있지만 이 설치본에 쓸 수 있는 등록 항목이 없습니다. |
| `claude wrapper` | `registered (CLAUDE.md)` / `missing` / `not registered` | `CLAUDE.md`가 `@AGENTS.md` 임포트 래퍼인지 여부입니다. 래퍼가 아닌 기존 `CLAUDE.md`는 보존합니다. |
| `agent-specific diagnostics` | CLI 있음/없음, 등록 결과 | 설치된 에이전트 CLI가 제공하는 추가 검사입니다. 현재 에이전트 세션의 도구 노출 여부를 검사하지는 않습니다. |
| `self-heal hooks` | `registered` / `missing` | 관리 훅이 메모리 런처를 재지정할 수 있는지 여부입니다. Claude와 Codex는 `SessionStart`, Cursor는 `sessionStart`, Antigravity는 `PreInvocation`을 사용합니다. Codex 프로젝트 훅은 사용자가 검토하고 신뢰해야 합니다. |
| `skills` | `<n> in .agents/skills; sync script present` | 공유 스킬 원본과 Claude 동기화 스크립트가 설치돼 있습니다. |
|  | `sync wiring missing` | Claude 스킬 동기화 스크립트가 없습니다. |
|  | `management skill: present` / `missing` | 관리되는 `agent-parity` 스킬의 설치 여부입니다. |
| `hook` | `registered` / `missing` | Claude 세션 시작 훅이 `.claude/skills`로 스킬을 동기화하는지 여부입니다. |
| `cursor cli` | `memory allowlist present` / `allowlist missing` | `.cursor/cli.json`이 Cursor에 메모리 도구 자동 승인을 부여하는지 여부입니다. |
| `AGENTS.md` | `memory block present` / `missing` | 관리되는 메모리 지침 블록의 존재 여부입니다. |
| `memory store` | `<n> entries` / `missing` | 저장된 메모리 마크다운 파일 수, 또는 저장소 디렉터리 부재입니다. |
| `git` | `all artifacts tracked` | 설치 산출물이 Git으로 동기화될 수 있습니다. |
|  | `IGNORED ...` | 일부 산출물이 무시돼 있습니다. `install` 또는 `update`가 관리하는 `.gitignore` 블록을 고치기 전까지 동기화되지 않습니다. |
|  | `memory merge driver: registered` / `missing` | `.agents/memory` 파일용 git 머지 드라이버가 `.git/config`에 등록됐는지 여부입니다. |
| `parity` | `<파일> exists ...` | 에이전트별 지침 파일이 동작을 갈라놓습니다. 내용을 `AGENTS.md`로 합쳐 주세요. |

</details>

### 주의사항

메모리 저장소는 저장소 안에 평문으로 들어가 공개 저장소면 노출됩니다. agent-parity가 에이전트에게 비밀 정보를 넣지 않도록 안내하지만, 저장되는 내용의 책임은 사용자에게 있습니다.

## 동작 방식

이식 가능한 배선, 릴리스 메타데이터, 메모리와 스킬은 저장소에 커밋하지만 MCP 바이너리는 커밋하지 않습니다. `run.sh` / `run.cmd`는 처음 사용할 때 프로젝트에 고정된 릴리스에서 현재 플랫폼 바이너리 하나만 내려받고 `checksums.txt`로 검증한 뒤 프로젝트들이 공유하는 사용자 캐시에 저장합니다. install/update는 같은 캐시에 현재 플랫폼용 소형 `agent-parity-config` 편집기도 설치합니다. 빈 캐시에서 처음 실행되는 self-heal도 동일하게 고정된 편집기를 자동으로 내려받아 검증합니다. 설정을 다루는 관리 명령은 캐시된 편집기로 JSON/TOML을 파싱하고 수정하므로 MCP 서버를 시작하거나 내려받지 않습니다. `status`와 `version`은 최신 릴리스 필드를 확인하는 제한된 네트워크 요청만 수행합니다. 기본 캐시는 Unix에서 `$XDG_CACHE_HOME/agent-parity`(없으면 `~/.cache/agent-parity`), Windows에서 `%LOCALAPPDATA%\agent-parity\cache`이며 `AGENT_PARITY_CACHE`로 바꿀 수 있습니다. `uninstall`은 공유 캐시를 지우지 않습니다. Claude 산출물은 `.agents/`에서 생성합니다. `.claude/skills/`는 git에서 제외하지만, 생성된 `.claude/settings.json`은 커밋하여 새로 받은 저장소에도 다시 생성하는 데 필요한 훅이 있도록 합니다. `.gitignore`가 추적할 배선 파일을 가리는 프로젝트면 `install`이 마커 블록으로 추적 규칙을 맞추고 `uninstall`이 되돌립니다. git은 여러 머신·팀과 공유할 때만 필요한 선택입니다.

agent-parity는 사용자 콘텐츠와 자체 배선을 다르게 다룹니다. 에이전트 설정과 Claude 설정에는 자기 항목만 병합하므로, 그 안의 다른 설정과 사용자가 다른 서버로 바꿔 둔 `memory` 항목은 보존됩니다. `AGENTS.md`·`.gitignore`의 마커 블록과 생성 shim(런처, 동기화 스크립트, 관리 명령, `agent-parity` 스킬)은 `update`가 최신 상태로 다시 만드니 그 사본은 직접 고치지 마세요. `uninstall`은 자신이 넣은 것을 제거합니다. 메모리 저장소와 `.agents/skills/`의 사용자 스킬은 수정도 삭제도 하지 않습니다(`--purge`를 줘야 저장소를 지웁니다). 기존에 에이전트별 폴더(`.claude`·`.codex`·`.cursor`의 `skills/`)에 있던 스킬은 설치할 때 `.agents/skills/`로 옮겨 모든 에이전트가 함께 쓰게 합니다. `uninstall` 후에도 `.claude/skills` 사본은 남겨, 공유 폴더를 못 읽는 Claude가 동기화 없이 스킬을 유지합니다.

### 크로스 OS self-heal

커밋된 MCP 설정은 `run.sh` 또는 `run.cmd` 중 하나를 가리킵니다. 관리 훅은 네 설정을 검사하고, agent-parity가 소유한 `memory` 명령만 현재 OS용 런처로 바꿉니다. Claude와 Codex는 `SessionStart`, Cursor는 `sessionStart`, Antigravity는 `PreInvocation`에서 실행합니다. 사용자가 직접 등록한 다른 `memory` 서버는 덮어쓰지 않습니다. 설정이 바뀌면 MCP 도구가 교정 전에 이미 로드됐을 수 있으므로 현재 에이전트 세션을 재시작하라고 안내하며, 변경이 없으면 아무것도 출력하지 않습니다. 빈 캐시에서는 고정된 설정 편집기만 내려받아 검증하며 MCP 서버 바이너리는 다운로드하거나 실행하지 않습니다. Codex 프로젝트 훅은 실행 전에 `/hooks` 또는 Hooks UI에서 검토하고 신뢰해야 합니다.

### 메모리

각 메모리는 `created`, `tags`, `strength`, `lastAccessed` 프론트매터를 가진 마크다운 파일입니다. `memory_search`는 `일치 × exp(-경과일 / strength)`로 점수를 매기고, 회상할 때 `strength`를 올립니다. 그래서 자주 회상되는 메모리는 검색 상위에 오래 남고, 오래 안 쓴 메모리는 점수가 낮아져 검색에서 밀립니다.

회상 기록은 동기화할 가치가 있는 상태이므로, 두 머신이 동기화 전에 같은 메모리를 회상해도 함께 설치되는 git 머지 드라이버가 충돌 대신 병합합니다: `strength`는 더 높은 쪽, `lastAccessed`는 최신 값을 취합니다. 본문이 양쪽에서 다르게 수정된 메모리는 원래대로 충돌합니다.

### 스킬

표준 Agent Skills(`<name>/SKILL.md`)를 `.agents/skills/`에 넣습니다. Codex, Cursor, Antigravity CLI는 거기서 바로 불러옵니다. Claude Code의 SessionStart 훅은 `.agents/bin/agent-parity sync-claude`를 호출하고, 프로젝트 로컬 런처가 Unix에서는 `sync-claude.sh`, Windows에서는 `sync-claude.ps1`을 선택합니다. MCP self-heal은 별도의 Claude SessionStart 훅으로 독립 실행됩니다. 그러면 세션이 시작될 때마다 `.agents/` 원본에서 `.claude/skills`와 `.claude/settings.json`을 다시 만듭니다. 수정은 원본에만 하고, 생성된 사본은 언제든 버려도 됩니다. `.claude/settings.local.json`은 절대 건드리지 않으므로 머신 로컬 설정은 로컬에 남습니다.

## 설치 시 생성되는 파일

| 경로 | 내용 |
| --- | --- |
| `.agents/mcp/memory/` | 메모리 서버 런처와 고정된 `VERSION`·`RELEASE` 메타데이터; 바이너리는 없음 |
| `.agents/memory/` | 메모리 저장소: 메모리 하나가 마크다운 파일 하나 |
| `.agents/skills/` | 공유 스킬 원본 (사용자가 채우는 곳) |
| `.agents/skills/agent-parity/` | 어느 에이전트에서든 관리 명령을 실행하는 관리 스킬 |
| `.agents/bin/` | 프로젝트 로컬 런처(`agent-parity`, `agent-parity.cmd`) |
| `.agents/scripts/common.{sh,ps1}` | 로컬 관리 명령이 공유하는 공통 함수 |
| `.agents/scripts/{status,version,uninstall}.{sh,ps1}` | 서로 분리된 프로젝트 로컬 관리 명령 |
| `.agents/scripts/sync-claude.{sh,ps1}` | 스킬을 `.claude`로 미러링하는 동기화 스크립트 |
| `.agents/scripts/self-heal.{sh,ps1}` | 관리되는 MCP 등록을 현재 OS용 런처로 재지정하는 스크립트 |
| `.agents/scripts/merge-memory.sh` | 동시 회상을 병합하는 git 머지 드라이버 |
| `.agents/claude/settings.json` | 플랫폼 독립 동기화 훅이 담긴 Claude 설정 원본 |
| `.agents/mcp_config.json` | Antigravity CLI에 메모리 서버 등록 |
| `.agents/hooks.json` | Antigravity self-heal 훅 |
| `.claude/settings.json` | 생성된 Claude 설정 부트스트랩; 커밋하며 `.agents/claude/settings.json`에서 갱신 |
| `.claude/skills/` | 생성된 Claude 스킬 미러; Git에서 제외하며 세션 시작 시 갱신 |
| `.codex/config.toml` | Codex에 메모리 서버 등록 |
| `.codex/hooks.json` | Codex 세션 시작 self-heal 훅(신뢰 승인 필요) |
| `.cursor/mcp.json` | Cursor에 메모리 서버 등록 |
| `.cursor/cli.json` | Cursor용 메모리 도구 자동 승인 허용목록 |
| `.cursor/hooks.json` | Cursor 세션 시작 self-heal 훅 |
| `.mcp.json` | Claude Code에 메모리 서버 등록 |
| `AGENTS.md` | 마커로 구분된 지침 블록 |
| `CLAUDE.md` | `@AGENTS.md` 임포트 래퍼 |
| `.gitattributes` | 메모리 파일을 머지 드라이버로 보내는 관리 블록 |
| `.gitignore` | 제외 규칙이 설치 배선이나 생성된 Claude 파일을 가릴 때 사용하는 관리 마커 블록 |

`install.sh` / `install.ps1`은 원격 설치 전용 진입점입니다. `agent-parity update`를 실행하면 프로젝트 런처가 최신 릴리스의 버전 내장 `update.sh` / `update.ps1` asset을 받습니다. 스크립트에 내장된 버전이 동일 태그의 Raw 템플릿과 설정 편집기 asset을 선택하고 MCP 런처 메타데이터도 그 릴리스로 고정합니다. `.agents/scripts`에는 업데이트 파일을 두지 않습니다.

`uninstall`은 완전히 오프라인으로 동작하며 MCP 런처를 실행하지 않습니다. Windows와 Unix 모두 구조화된 JSON/TOML 변경에 공유 캐시에 설치된 검증된 `agent-parity-config` 편집기를 사용합니다. 어느 쪽도 Python이나 별도의 사용자 설치 런타임을 요구하지 않습니다.
