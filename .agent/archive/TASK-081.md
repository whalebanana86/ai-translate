# TASK-081: 이 서비스의 전체 구조·저장 형식·통신 형식·공개 인터페이스 문서

- 상태: COMPLETED
- 생성일: 2026-11-05
- 브랜치: `docs/architecture-map`

## 요청

"브랜치 만들고 이거 알려줘" + 붙여 넣은 글(개발자에게 필요한 세 가지: 기초·전체 구조 파악·필요할 때 깊게 파기 / 에이전트에게 맡겨도
사람이 챙길 곳: 박스와 선 구조도와 시퀀스 다이어그램, DB 스키마 직접 설계, 저장 데이터 형식·통신 프로토콜·공개 API 변경은 사람이 리뷰)
→ "이 서비스에 대입해서 알려주면 되". 붙여 넣은 기준을 이 앱에 대입해 설명한다.

## 요구사항

1. 박스와 선 구조도: 앱 타깃·TranslateCore·macOS·기기 밖이 어떻게 연결되는지
2. 시퀀스 다이어그램: 단축키부터 번역 표시까지 렌즈 한 번의 처리 순서
3. 저장 데이터 형식(DB 대신): 번역 기억 파일, 로컬 모델 파일, UserDefaults 키. 바꾸면 무엇이 깨지는지
4. 통신 형식: Claude Code·Codex CLI 입출력, 로컬 모델 프롬프트, 모델 받기, Codex 모델 목록. 누가 형식을 정하는지
5. 공개 인터페이스: 바깥에 여는 API가 없음을 밝히고, 모듈 경계(TranslateCore `public`)와 사용자에게 보이는 약속
6. 기초(동시성·비용·네트워크)로 느려질 때 짐작할 곳, 증상별로 먼저 볼 곳
7. 이 서비스에서 사람이 꼭 리뷰할 변경 목록
8. 코드에서 확인한 사실만 쓴다. 새 규칙이나 코드 변경은 더하지 않는다(필요해 보이는 것은 제안으로만 보고)

## 완료 조건 (Acceptance Criteria)

- [x] AC1. `docs/design/architecture.md`에 요구사항 1~7이 있다
- [x] AC2. AGENTS.md 3장 영역 문서 표에 이 문서가 있다 (5.6: 새 영역 문서는 표에 더한다), AGENTS.md 24KB 이하
- [x] AC3. `./scripts/auto-fix-loop.sh TASK-081` 통과

## 진행 기록

- 2026-11-05 작업 생성. 코드에서 확인: `TranslationLensController`·`LensSession`(흐름·동시성), `TranslationPayload`·
  `TranslationPrompt`·`ClaudeCodeProvider`·`CodexProvider`·`HyMTPrompt`(통신 형식), `TranslationMemoryStore`·
  `TranslationMemory`·`ModelStore`·`LocalModel`·UserDefaults 키(저장 형식), `CaptureSchedule`·`ChangeTracker`(주기·기준값)
- 확인한 점: 요청 JSON은 바이트 그대로 고정한 테스트가 있지만(`TranslationPayloadTests`), 번역 기억 파일은 저장→읽기 왕복과
  파일 이름만 검사한다(`TranslationMemoryStoreTests`). 필드 이름을 바꿔도 테스트는 통과하고 이전 파일은 조용히 빈 기억이 된다.
  고치지 않고 보고만 한다(요구사항 8)
- `docs/design/architecture.md` 작성(1~7장). Mermaid 그림 두 개는 헤드리스 Chrome + mermaid 10.9.1로 오류 없이 그려지는 것을 확인.
  구조도는 클래스마다 박스를 두니 선이 엇갈려 읽기 어려워 역할 단위(화면 감시·글 읽기·번역 기억·엔진)로 묶음
- AGENTS.md 3장 표 맨 위에 한 줄. 23,438 → 23,747바이트 (상한 24,576)
- 이 작업은 테스트를 만들거나 고치지 않아 깨뜨려 확인할 대상이 없다
- 검증 루프: 시도 1 통과 (docs·typecheck·lint·build·strings·test)
- 2026-11-05: 사용자 요청("글보다는 그림위주로 설명해주고 왜 해당 기술을 사용했는지로")으로 그림 위주의 `docs/design/architecture.html`을 더함(구조·처리 순서·기술별 고른 것과 안 고른 것·측정 차트, 인라인 SVG). 근거는 영역 문서와 TASK-012·014·015·045·072 측정값만 썼다. 코드·테스트 변경 없음
