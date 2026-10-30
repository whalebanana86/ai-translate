# TASK-016: 로컬 LLM 엔진 (Hy-MT2 1.8B, MLX Swift, 수동 다운로드)

- 상태: IN_PROGRESS
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

- [ ] AC1. 모델 받기: 진행률, 해시 확인, 실패·취소 시 부분 파일 정리, 끝나면 설치 상태가 된다 (가짜 서버 테스트).
- [ ] AC2. 지우기 후 설치 안 됨 상태가 된다 (테스트).
- [ ] AC3. 로컬 번역 엔진이 문단마다 생성기를 부르고 출력을 정리한다 (가짜 생성기 테스트).
- [ ] AC4. 실제 MLX Swift로 Hy-MT2를 불러 번역이 나온다 (확인 기록).
- [ ] AC5. 앱이 빌드된다. `AGENTS.md` 갱신.
- [ ] AC6. `./scripts/auto-fix-loop.sh` 통과.

## 진행 기록

- 2026-10-30: TASK 생성.
- 2026-10-30: 쓰지 않는 모델 삭제(사용자 요청): Ollama `hf.co/mradermacher/LMT-60-1.7B-GGUF:Q4_K_M`·
  `hf.co/tencent/Hy-MT2-1.8B-GGUF:Q4_K_M`, Hugging Face 캐시 `NiuTrans/LMT-60-1.7B`·`mlx-community/Hy-MT2-1.8B-4bit`
  (`hf cache rm`, 5.1GB), 스크래치 LMT-60 4비트 변환본(0.9GB). 원래 있던 qwen3.5 3종·LM Studio 모델·embeddinggemma는 유지.
- 2026-10-30: mlx-swift-lm 3.32.3(MIT, 2026-09-30)이 `hunyuan_v1_dense` 등록 확인. 3.x는 토크나이저·다운로더를 분리 →
  `swift-transformers`의 토크나이저를 프로토콜로 연결. Codex CLI 0.155.0(`~/.volta/bin/codex`) 확인.
