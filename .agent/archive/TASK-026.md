# TASK-026: 작은 정리 (색 추출 표본, 창 목록 재사용, 번역 기억 디스크 저장)

- 상태: COMPLETED
- 생성일: 2026-10-30

## 요청

TASK-019 개선 방안 8번.

## 설계

- 색 추출 표본 문단당 20,000 → 4,000 (Debug 빌드 실측 74ms, 최적화 빌드 2ms)
- 화면 캡처: `SCShareableContent` 조회와 필터를 화면별로 5초 동안 재사용, 실패하면 다시 조회
- 번역 기억 디스크 저장: `TranslationMemoryStore`(엔진별 JSON, `~/Library/Application Support/AITranslate/TranslationMemory`,
  파일 권한 0600, 엔진별 최대 500개). 렌즈를 만들 때 불러오고, 닫을 때·엔진을 바꿀 때·앱을 끌 때 저장.
  엔진을 바꾸면 그 엔진의 기억으로 바꿔 끼운다. 설정에 "번역 기억 지우기"(파일과 열린 렌즈의 기억 모두)
- 개인정보: 원문·번역 글이 기기 안에 남으므로 AGENTS.md 개인정보 규칙에 저장 위치·지우는 방법을 적는다

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 번역 기억 저장·불러오기(순서·용량 유지), 깨진 파일은 빈 기억, 지우기 테스트.
- [x] AC2. 색 추출 테스트가 줄인 표본으로 통과.
- [x] AC3. 캡처 재사용·기억 연결·설정 버튼, 앱 빌드·실행.
- [x] AC4. `AGENTS.md` 갱신, `./scripts/auto-fix-loop.sh` 통과.

## 진행 기록

- 2026-10-30: TASK 생성.
- 2026-10-30: 색 추출 표본 4,000. `TranslationMemory.Entry`·`entries`·`init(capacity:entries:)`(비공개 저장소 이름이 겹쳐
  `table`로 바꿈), `TranslationMemoryStore`(+ 테스트 4개) → 131개 통과. `ScreenCapturer`를 메인 액터 클래스로 바꿔 필터 5초 재사용.
  렌즈: 엔진별 기억 불러오기·저장(닫기·엔진 변경·앱 종료), `clearMemory()`. 설정 "번역 기억" 영역과 지우기 버튼.
  `AGENTS.md` 개인정보·캡처 규칙 갱신. 검증 루프 시도 1 통과, 앱 실행 정상.
- 2026-10-30: (참고) 확인 실행 중 `open`이 -600(프로세스 없음)으로 한 번 실패, 다시 열어 정상. 이전 앱 종료 직후의 일시적 오류로 보임.
