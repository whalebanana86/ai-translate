# TASK-068: 검증 루프에 AGENTS.md 크기 검사

- 상태: COMPLETED
- 생성일: 2026-11-03

## 요청

TASK-067(AGENTS.md 나누기) 보고에서 "규칙만으로는 다시 커질 수 있어 검증 루프에 크기 검사를 넣을지" 제안 → 사용자: "어 진행해".

## 설계

- `scripts/auto-fix-loop.sh` 첫 단계 `docs`: AGENTS.md가 24KB(24576바이트)를 넘으면 실패하고 옮길 곳(`docs/design/<영역>.md`,
  AGENTS.md 5.6)을 알린다. 상한은 스크립트 상단 상수(다른 제한값처럼 환경 변수로 바꿀 수 없음)
- AGENTS.md 5.3 검증 단계·5.6, README 명령 설명 갱신

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 24KB를 넘는 AGENTS.md에서 `docs` 단계가 실패하고 원인을 보여준다, 지금 크기(21.8KB)에서는 통과한다.
- [x] AC2. `./scripts/auto-fix-loop.sh TASK-068` 통과, 문서 갱신.

## 진행 기록

- 2026-11-03: TASK 생성.
- 2026-11-03: `docs` 단계(상수 `MAX_AGENTS_BYTES` 24576). 25000바이트 파일: exit 1, "error: AGENTS.md가 25000바이트로 상한
  24576바이트(24KB)를 넘는다" + 옮길 곳 안내. 지금 AGENTS.md(21934바이트): 통과. 한글 앞 변수는 중괄호로 감싼다(`$size바이트`가
  깨졌다). AGENTS.md 5.3·5.6·디렉터리 구조, README 두 개 갱신. 검증 루프 시도 1 통과
