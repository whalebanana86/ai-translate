# TASK-015: LMT-60 1.7B 비교, Ollama보다 빠른 Apple Silicon 실행 환경 조사

- 상태: COMPLETED
- 생성일: 2026-10-30

## 요청

사용자: "3번까지 진행해보자 그리고 ollama보다 맥북m시리즈로 성능을 더 끌어올릴 수 있는 앱도 찾아줘"
(3번 = LMT-60 1.7B도 비교한 뒤 결정. 1번(Hy-MT2 단독)·2번(Hy-MT2 → haiku 교체) 선택은 이 결과를 보고 정함)

## 완료 조건 (Acceptance Criteria)

- [x] AC1. LMT-60 1.7B를 같은 문단으로 측정해 Hy-MT2 1.8B·haiku와 속도·품질을 비교한다 (못 돌리면 원인 기록).
- [x] AC2. Apple Silicon용 실행 환경 후보를 조사해 속도 근거·앱 내장 가능성·라이선스와 함께 보고한다.
- [x] AC3. 가능한 후보는 같은 모델로 Ollama와 속도를 직접 비교한다.

## 진행 기록

- 2026-10-30: TASK 생성.
- 2026-10-30: 라이선스 확인 (공식 저장소 파일 원문): `tencent/Hy-MT2-1.8B`·`-GGUF`의 LICENSE.txt는 Apache-2.0 원문 그대로,
  지역 제한·사용자 수 조건 없음 (제3자 MLX 변환판 카드의 "EU 금지" 문구는 HY-MT1.5 라이선스를 잘못 옮긴 것으로 보임).
  `NiuTrans/LMT-60-1.7B`는 LICENSE 파일 없음, README 메타데이터만 apache-2.0.
- 2026-10-30: 준비: LMT-60 GGUF(mradermacher, Q4_K_M)를 Ollama로, 스크래치 `mlx`에 uv로 mlx-lm 환경(Python 3.12),
  `mlx-community/Hy-MT2-1.8B-4bit` 받기, `NiuTrans/LMT-60-1.7B` 공식 가중치를 mlx_lm.convert로 4비트 변환(934MB).
  mlx-lm은 hunyuan_v1_dense·qwen3 구조 지원. 측정 스크립트: `engine-bench/bench_ollama.py`, `mlx/bench_mlx.py`,
  `mlx/micro.py`, 점검 `engine-bench/check.py`(Swift 점검과 같은 결과 확인).
- 2026-10-30: 페이지 측정 (문단마다 차례로, 초, 처음/이어서)

  | 엔진 | P1 트윗 | P2 안내 화면 | P3 까다로운 문장 | 점검 |
  |---|---|---|---|---|
  | haiku | 4.8 / 6.6 | 5.0 / 3.4 | 4.5 / 5.4 | 줄바꿈 10/10, AI 4/4, 지시문 1/2, 숫자·이름 28/28 |
  | Hy-MT2 Ollama | 3.9 / 3.1 | 2.3 / 2.3 | 3.1 / 3.0 | 줄바꿈 10/10, AI 0/4, 지시문 2/2, 숫자·이름 28/28 |
  | Hy-MT2 MLX | 4.5 / 2.6 | 2.0 / 1.8 | 2.6 / 2.6 | 같음 |
  | LMT-60 Ollama | 4.0 / 1.5 | 2.3 / 2.2 | 2.8 / 2.6 | 줄바꿈 0/10, 숫자·이름 12/28 |
  | LMT-60 MLX | 1.7 / 1.6 | 1.5 / 1.5 | 2.3 / 2.3 | 줄바꿈 0/10, 숫자·이름 12/28 |

  - LMT-60 1.7B는 내용을 빠뜨려서 빠름: 트윗 본문 문장 통째로 누락, 둘째 줄 누락, 지어냄("Get help" → "어린이를 도와주세요",
    "cheap Al … drafts" → "저렴한 알루미늄은 냉동용으로"), 이름을 한글로 음역("@블루록아이디"). → 쓸 수 없음. 모델은 Hy-MT2 1.8B
- 2026-10-30: 같은 모델(Hy-MT2 1.8B 4비트)·greedy·문장마다 5회 중앙값

  | 실행 환경 | 짧은 문구(10토큰) | 한 줄 문장(31토큰) | 긴 문단(111~114토큰) | 생성 속도 |
  |---|---|---|---|---|
  | Ollama (llama.cpp, Q4_K_M) | 0.179초 | 0.416초 | 1.314초 | 94~102 토큰/초 |
  | MLX (mlx-lm, 4bit) | 0.139초 | 0.334초 | 1.101초 | 109~121 토큰/초 |

  → MLX가 16~22% 빠름. Ollama의 MLX 모드는 메모리 32GB 이상 맥에서만 켜져(검색 결과) 이 맥(24GB)은 llama.cpp로 돎
- 2026-10-30: LM Studio llama.cpp 엔진(같은 GGUF를 Ollama 파일에서 하드 링크로 등록, `lms import -L`): 짧은 문구 0.127초,
  한 줄 문장 0.415초, 긴 문단 1.503초, 생성 77~87 토큰/초 → 요청 부담은 Ollama보다 작지만 생성은 느림. 이 맥에서 Ollama가
  특별히 느린 것은 아니고, 차이는 llama.cpp 대 MLX에서 남.
- 2026-10-30: LM Studio MLX 엔진용 모델 받기(`lms get https://huggingface.co/mlx-community/Hy-MT2-1.8B-4bit`)가
  약 1MB/초로 느리고 690MB에서 멈춤 → 받아 둔 파일을 하드 링크로 넣었으나 LM Studio가 인식하지 않음 → 다시 받기로 재개.
- 2026-10-30: 다시 받기는 99.9%에서 "Checksum failed"로 실패 (같은 폴더에 넣어 둔 하드 링크와 충돌한 것으로 보임).
  Hugging Face 캐시의 원본은 공개 해시와 일치(a9cecbc7…) 확인. LM Studio에 넣은 MLX 폴더·GGUF 하드 링크를 지우고 서버를 꺼
  원래 상태로 되돌림. → LM Studio MLX 엔진(M5 nax)은 측정하지 못함 (재시도하려면 LM Studio에서 깨끗하게 받기, 약 17분).
- 조사 결과 (실행 환경)
  - MLX(Apple): 짧은 요청에서 llama.cpp·Ollama보다 빠르다는 측정이 많음. 앱 내장: MLX Swift(mlx-swift-lm의 MLXLLM)로 앱 안에서
    직접 실행 가능 → 사용자가 Ollama·LM Studio를 설치할 필요 없음
  - Ollama MLX 모드: 2026-03 미리보기, 메모리 32GB 이상 맥에서만 켜짐(검색 결과) → 이 맥(24GB)은 llama.cpp
  - LM Studio: MLX 엔진(M5 뉴럴 가속기용 nax 판)·llama.cpp 엔진, 별도 설치 앱
  - 그 밖(제조사 주장, 미검증): Rapid-MLX, mlx-serve, oMLX. MLC-LLM은 한 연구에서 첫 토큰이 빠름
  - M5 뉴럴 가속기는 주로 프롬프트 처리(prefill)를 3~4배 빠르게 하고 생성(decode)은 메모리 대역폭에 묶임 → 짧은 문단 번역에는
    효과가 작음
- 결론: 모델은 Hy-MT2 1.8B, 실행은 MLX(앱에는 MLX Swift로 내장)가 이 맥에서 가장 빠름. 다음 결정: 1번(Hy-MT2 단독) 또는
  2번(Hy-MT2로 먼저 → haiku로 교체)
- 받아 둔 파일(저장소 밖): Ollama Hy-MT2 1.1GB·LMT-60 1.1GB, Hugging Face 캐시 Hy-MT2 MLX 1GB·LMT-60 원본 4GB,
  스크래치 LMT-60 MLX 4비트 0.9GB·mlx-lm 환경
