---
created: 2026-07-18T00:00:00Z
tags:
    - agent-parity
    - issue-5
    - windows
    - crlf
    - implemented
strength: 1
lastAccessed: 2026-07-18T00:00:00Z
---
agent-parity 문제 5를 수정했다. `store.go`의 `parseEntry`는 입력의 CRLF를 LF로 정규화한 뒤 frontmatter를 파싱하므로 Windows checkout 파일에서도 created, tags, strength, lastAccessed와 본문을 정상 인식한다. 제품 코드에는 정상 LF/CRLF 입력 지원만 둔다. 작업 중 구 파서가 만든 중첩 손상 상태를 영구 호환 대상으로 추가했던 것은 실제 릴리스 이력이 아닌 일회성 상태를 배포 코드에 누적한 잘못이므로 제거했다. CRLF 직접 파싱과 CRLF 메모리 검색 후 비중첩 LF 재저장 테스트만 유지한다. 이미 손상된 메모리 6개는 제품 마이그레이션 없이 원래 created·tags와 누적 strength·lastAccessed를 합쳐 물리 복구했다.
