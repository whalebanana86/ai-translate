# 번역 엔진과 번역 순서

다루는 범위: 번역 기억, 이미 대상 언어인 문단 건너뛰기, 엔진·모델 고르기, 묶음·순서·요청 버리기, 로컬 모델(MLX).

이 영역의 코드를 바꾸기 전에 읽고, 바꾼 동작과 그 이유(사용자 요청·측정값·실패한 방법)를 여기에 적는다.
모든 작업에 공통인 규칙은 [AGENTS.md](../../AGENTS.md)에 있다.

- 번역: `TranslationMemory`로 (원문, 언어)별 번역을 기억해 새 문단만 보낸다. 요청은 동시에 하나만. 실패하면 다음 변화 때 재시도
- 이미 대상 언어로 쓰인 문단은 보내지 않고 원문 그대로 둔다(`LanguageDetection`, `TextBlock.needsTranslation(to:)`, TASK-045:
  한국어 유튜브 화면은 "@아이디 1년 전"·"답글 4개"·"자세히 알아보기"까지 하나씩 보내 본문 번역이 늦었다. 캡처 한 화면 12개 → 5개).
  확실할 때만 건너뛴다(틀리면 외국어가 남는다): 아이디("@이름")를 빼고, 대상 언어 문자가 아닌 글자가 25% 이하(글자 하나짜리
  다른 문자 단어는 세지 않음: 아이콘 오인식 "V"), macOS 언어 판별(`NLLanguageRecognizer`, 기기 안) 확률 0.9 이상. 판별은 약 0.4ms라
  (글, 언어)별로 기억한다. 라틴 문자 언어는 짧은 글귀("Reply")를 확신하지 못해 그대로 번역한다
- 병렬 번역은 하지 않는다: 로컬 모델로 댓글 본문 8개를 동시에 보내도 전체 시간이 하나씩과 거의 같았다(2.6~2.8초 → 2개 동시
  2.4~2.5초, 4·8개 동시 약 2.5초. GPU 하나를 나눠 쓴다). 동시에 보내면 위 문단이 오히려 늦게 끝난다 (TASK-045 측정)
- 엔진 선택: `App/EngineSettings.swift`(선택값 UserDefaults `TranslationEngine`, CLI 설치 확인, 로컬 모델 받기·취소·지우기,
  엔진별 번역 엔진을 만들어 기억), 화면 `App/SettingsView.swift`, 창 `App/SettingsWindowController.swift`(메뉴 "설정…" ⌘,)
  - 엔진을 아직 고르지 않았으면(처음 실행) 같은 화면을 시작 안내로 띄우고, ⌘⇧1도 렌즈 대신 안내를 띄운다
  - 엔진을 바꾸면 열린 렌즈가 진행 중 요청을 취소하고 기억한 번역을 비워 새 엔진으로 다시 번역한다
  - CLI 엔진 모델 고르기(TASK-053, 설정 카드 안, UserDefaults `ClaudeModel`·`CodexModel`): Claude는 Claude Code 별칭
    (`ClaudeCodeProvider.models`: haiku 기본·sonnet·opus·fable, Claude Code가 그때의 최신 모델로 바꿈), Codex는 Codex가 받아 두는
    `~/.codex/models_cache.json`의 보이는 모델(`CodexModelCatalog`, 계정·버전마다 달라 고정하지 않음) + 기본값(모델을 넘기지 않음).
    Codex는 고른 모델이 있을 때만 `--model`. Claude는 Haiku가 아니면 시간 제한 180초(측정 안 함, Haiku 60초보다 느림).
    고른 엔진의 모델을 바꾸면 엔진을 바꿀 때처럼 렌즈가 다시 번역한다. 번역 기억은 엔진·모델별 파일(기본 모델은 예전 `<엔진>.json`)
  - 묶음은 `TranslationScheduling.batch`: 엔진의 `preferredBatchSize`(로컬 1: 번역되는 대로 보임), 새 화면이면
    `firstBatchSize`(Claude 3: 위쪽 문단 먼저, Codex는 요청 고정 비용이 커서 나누지 않음), 그 밖에는 남은 문단을 한 번에
  - 렌즈 위·아래 끝에 걸친(잘린) 문단은 스크롤마다 글이 바뀌므로 맨 뒤에 번역한다(`LensGeometry.isCutOff`)
  - 진행 중 요청의 문단이 절반 넘게 화면에서 지나가면 요청을 버리고 지금 화면부터 번역한다(`TranslationScheduling.shouldAbandon`)
- 로컬 모델: `TranslateCore/LocalModel.swift`(Hugging Face `mlx-community/Hy-MT2-1.8B-4bit`, 리비전·파일 크기·해시 고정),
  `ModelStore`(`~/Library/Application Support/AITranslate/Models/<id>`), `ModelDownloader`(받는 중에는 `<id>.partial`,
  파일마다 SHA-256/git 블롭 SHA-1 확인 후 옮김, 실패·취소 시 삭제). 자동으로 받지 않는다 (사용자가 "모델 받기")
  - MLX 실행: `App/LocalTextGenerator.swift`. mlx-swift-lm(3.32.3 고정, `hunyuan_v1_dense` 지원 확인)의 MLXLLM으로 받은 폴더에서
    바로 불러온다(다운로더 안 씀). 토크나이저는 swift-transformers를 프로토콜로 직접 연결(매크로·다운로더 패키지 안 씀).
    프롬프트에 특수 토큰이 있으므로 `addSpecialTokens: false`. 샘플링은 모델 카드 권장값. 측정(M5): 불러오기 1.25초,
    생성 초당 101~112토큰, 짧은 문구 0.14초·한 줄 0.35초·긴 문단 1.2초
  - 빌드에 Metal 툴체인이 필요하다 (Xcode 26은 따로 받음: `xcodebuild -downloadComponent MetalToolchain`)
  - Intel 제외: `TranslationEngine.isSupported(onAppleSilicon:)`, 앱은 `arch(arm64)`로 판단(`EngineSettings.isAppleSilicon`). Intel·Rosetta에서는 설정의 로컬 카드를 끄고, 저장된 선택이 로컬이면 다시 고르게 한다
  - 로컬 엔진은 생성되는 대로 보여준다(`onPartial`, 화면 갱신 0.05초 간격). 최종 번역이 오면 그것으로 바꾼다
  - 미리 준비: 앱 시작·엔진 변경·모델 받기 완료 때 `EngineSettings.prepare()`로 엔진을 만들어 둔다(같은 엔진 준비는 하나만).
    로컬 모델은 불러온 뒤 짧은 예열 생성으로 GPU 커널을 준비한다(첫 생성 4.3초 측정). 로컬 엔진을 고른 동안은 모델(약 1.2GB)을
    메모리에 둔다. 렌즈는 엔진 준비를 기다리지 않고 OCR부터 하고, 준비가 끝나면 번역을 시작한다
