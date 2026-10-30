# TASK-016: 로컬 LLM 엔진 (Hy-MT2 1.8B, MLX Swift, 수동 다운로드)

- 상태: COMPLETED
- 생성일: 2026-10-30

## 요청

사용자: "처음 앱 설치시 또는 설정에서 클로드코드 코덱스 로컬llm을 선택하게 해주고 로컬llm선택시 Hy-mT2 모델다운로드 수동으로
할수 있게 해줘 그리고 쓰지 않는 모델은 삭제해"

작업 분리: TASK-016 로컬 LLM 엔진(모델 받기·지우기·번역), TASK-017 Codex 엔진, TASK-018 엔진 선택 화면(처음 실행·설정)과 렌즈 연결.
(쓰지 않는 모델 삭제는 코드 변경이 아니라 이 TASK 진행 기록에 남김)

## 설계

- 모델: `mlx-community/Hy-MT2-1.8B-4bit` (Apache-2.0, 약 1GB), 리비전 고정, 파일마다 크기·해시 확인
- 저장 위치: `~/Library/Application Support/AITranslate/Models/<모델 id>`. 받는 중에는 `<id>.partial`에 받고 모두 확인되면 이름을 바꿈
- 받기는 사용자가 버튼으로 시작(수동). 진행률·취소·지우기 지원
- 실행: MLX Swift(`mlx-swift-lm`의 MLXLLM, 토크나이저는 `swift-transformers`). 로컬 폴더에서 불러오고 다운로더는 쓰지 않음
- 번역: 문단마다 따로(번역 전용 모델), 모델 카드 프롬프트·권장 샘플링, 줄바꿈 앞 공백 두 칸 제거
- 테스트할 수 있는 부분(모델 정보, 받기·확인, 프롬프트, 문단별 번역)은 `TranslateCore`에, MLX 실행은 Xcode로만 빌드되는 쪽에 둔다
  (`swift build`는 MLX의 Metal 셰이더를 만들지 못함)

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 모델 받기: 진행률, 해시 확인, 실패·취소 시 부분 파일 정리, 끝나면 설치 상태가 된다 (가짜 서버 테스트).
- [x] AC2. 지우기 후 설치 안 됨 상태가 된다 (테스트).
- [x] AC3. 로컬 번역 엔진이 문단마다 생성기를 부르고 출력을 정리한다 (가짜 생성기 테스트).
- [x] AC4. 실제 MLX Swift로 Hy-MT2를 불러 번역이 나온다 (확인 기록).
- [x] AC5. 앱이 빌드된다. `AGENTS.md` 갱신.
- [x] AC6. `./scripts/auto-fix-loop.sh` 통과.

## 진행 기록

- 2026-10-30: TASK 생성.
- 2026-10-30: 쓰지 않는 모델 삭제(사용자 요청): Ollama `hf.co/mradermacher/LMT-60-1.7B-GGUF:Q4_K_M`·
  `hf.co/tencent/Hy-MT2-1.8B-GGUF:Q4_K_M`, Hugging Face 캐시 `NiuTrans/LMT-60-1.7B`·`mlx-community/Hy-MT2-1.8B-4bit`
  (`hf cache rm`, 5.1GB), 스크래치 LMT-60 4비트 변환본(0.9GB). 원래 있던 qwen3.5 3종·LM Studio 모델·embeddinggemma는 유지.
- 2026-10-30: mlx-swift-lm 3.32.3(MIT, 2026-09-30)이 `hunyuan_v1_dense` 등록 확인. 3.x는 토크나이저·다운로더를 분리 →
  `swift-transformers`의 토크나이저를 프로토콜로 연결. Codex CLI 0.155.0(`~/.volta/bin/codex`) 확인.
- 2026-10-30: `TranslateCore`에 `LocalModel`(Hy-MT2 MLX 4비트, 리비전 e5c6fe56 고정, 파일 8개 크기·해시), `ModelStore`,
  `ModelDownloader`(세션 대리자로 진행률, 파일마다 SHA-256/git 블롭 SHA-1 확인, 실패·취소 시 `.partial` 삭제),
  `LocalTranslationProvider`·`HyMTPrompt`(문단마다, 줄바꿈 앞 공백 제거, 특수 토큰 문자열 무력화), `TranslationProvider.preferredBatchSize`
  추가. 테스트 11개 추가(가짜 서버 `StubURLProtocol`, 가짜 생성기) → 103개 통과.
- 2026-10-30: 스크래치에서 mlx-swift-lm 시험 프로그램 빌드 시도
  - 1차(`-skipMacroValidation` 포함): 자동 권한 검사가 "외부 코드"로 거부 → 매크로 신뢰 확인을 건너뛰는 옵션을 빼고 재시도
  - 2차: 빌드는 진행됐으나 "missing Metal Toolchain" (Xcode 26은 Metal 툴체인을 따로 받음). 시스템 개발 도구 설치이므로
    사용자에게 `xcodebuild -downloadComponent MetalToolchain` 실행을 요청함
- 상태: COMPLETED. 완료: AC1~AC3. 남음: AC4(실제 MLX 실행), AC5(앱 빌드·AGENTS.md), AC6.
  다음 행동: 툴체인 설치 확인(`xcodebuild -showComponent MetalToolchain`) → 시험 프로그램으로 Hy-MT2 실행 → 앱에 MLX 연결
- 2026-10-30: 사용자가 Metal 툴체인 설치(17F109, 687.9MB) → 재개.
- 2026-10-30: 스크래치 시험 프로그램(Release) 실행: 불러오기 1.25초, 특수 토큰이 한 토큰으로 인식(`<｜hy_User｜>`=120006),
  끝 토큰에서 멈춤, 생성 초당 101~112토큰, 짧은 문구 0.135초·한 줄 0.348초·긴 문단 1.175초(이어서). Python MLX와 같은 수준.
- 2026-10-30: 앱 연결: `project.yml`에 mlx-swift-lm(3.32.3 고정, MLXLLM·MLXLMCommon)·swift-transformers(1.3.5~, Tokenizers),
  `LocalTextGenerator`를 실제 MLX 구현으로 교체(시험 프로그램과 같은 토크나이저 연결·생성 코드, 권장 샘플링, 취소 확인).
  빌드 경고는 MLX 패키지 내부 Metal C++17 경고뿐(우리 대상 아님). 검증 루프 시도 1 통과. 앱 실행(pid 61942) 정상,
  `Contents/Resources/mlx-swift_Cmlx.bundle` 포함, 서명 요구사항 동일.
- 남은 확인(사용자): 설정에서 로컬 LLM 선택 → "모델 받기" → 렌즈에서 로컬 번역. (모델을 미리 넣지 않음: 수동 받기 요청)
