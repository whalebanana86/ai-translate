# TASK-066: OCR이 "AI"를 "Al"로 읽은 것을 문맥으로 고치기

- 상태: COMPLETED
- 생성일: 2026-11-03

## 요청

사용자: "AI ai Ai 등등을 알 이라고 번역하는건 무슨 문제야?" → 원인 설명, 글꼴 질문("글꼴을 바꾸는건?") 뒤
"문맥보고 고치는 방향으로 진행".

## 원인 (측정, 스크래치)

- OCR: SF·SF bold·Helvetica·Arial(28pt, 14pt)에서 "AI"를 늘 "Al"(소문자 L)로 읽었다("OpenAI" → "OpenAl" 포함). Georgia는 맞게 읽음.
  "ai"·"Ai"는 맞게 읽음. 이 글꼴들은 I와 l의 높이가 같고 폭 차이가 글자 크기의 0.3~1%라 픽셀로 가릴 수 없다.
  Vision 단어 힌트(`customWords`)는 효과 없음
- 로컬 모델(Hy-MT2, 5회씩): "Al" → "알" 5/5, "Generative Al for everyone" → "모두를 위한 생성형 알고리즘" 5/5,
  "AI"·"ai" → AI 5/5, "Ai" → "아이" 5/5. Claude·Codex는 시스템 프롬프트에 "Al"↔"AI" 안내가 있다(TASK-006). 로컬은 모델 카드
  프롬프트라 안내가 없다(지시를 더하면 짧은 글을 대화로 알아들었다, TASK-048)
- 번역 기억(local.json, 단어 수만 셈): 원문 "AI" 0건, "Al" 2건 모두 "알"
- "ai"·"Ai" → "알"은 재현하지 못함 (사용자에게 화면 요청)
- macOS 이름 찾기(`NLTagger` nameType)는 못 씀: "Al Pacino" 놓침, "Use Al Studio"·"Al tools"의 "Al"을 사람 이름으로 봄.
  언어 판별(`NLLanguageRecognizer`)은 스페인어·이탈리아어 "Al"(a+el) 문장을 0.98~1.00으로 가림

## 설계

- `AIMisreading.corrected(_:)`: 번역 엔진에 보내는 문단 글만 고친다(`RegionTranslator.translate`). 문단 글(`TextBlock.text`,
  번역 기억 열쇠)은 OCR 그대로
  - 소문자 바로 뒤 "Al"(뒤에 라틴 글자·숫자 없음): "OpenAl", "GenAl", "xAl" → 늘 "AI"
  - 따로 쓴 "Al"(앞뒤에 라틴 글자·숫자 없음, 앞이 "@"가 아님) → "AI". 한글·가나 조사가 붙어도("Al가") 따로 쓴 것으로 본다. 단:
    - 다음 단어(빈칸·하이픈 뒤)가 대문자 + 소문자로 시작하는 이름 모양이면 둔다("Al Gore", "Al-Nassr"). 제목처럼 단어마다 대문자인
      글(라틴 글자 4개 이상 단어 2개 이상 중 75% 넘게 대문자로 시작)이면 대문자가 이름 표시가 아니므로 고친다("New Al Model")
    - 글이 스페인어·이탈리아어·카탈루냐어·루마니아어("Al"이 보통 낱말)거나 "alumin"이 있으면 둔다
- AGENTS.md OCR 오인식 항목 갱신

## 완료 조건 (Acceptance Criteria)

- [x] AC1. "Al"·"OpenAl"·"Al 모델이"·"Al-powered"·제목 "New Al Model" 등은 "AI"로, "Al Gore"·"Al-Nassr"·스페인어 "Al final"·
  "Aluminium (Al)"·"@Al"·"Also"·"Al2O3"는 그대로 (테스트).
- [x] AC2. 엔진 요청에는 고친 글, 결과의 원문 문단은 OCR 그대로 (테스트).
- [x] AC3. 로컬 모델에 고친 글을 넣으면 AI로 번역된다 (스크래치 측정).
- [x] AC4. `./scripts/auto-fix-loop.sh TASK-066` 통과, AGENTS.md 갱신.

## 진행 기록

- 2026-11-03: TASK 생성. 원인 측정(위).
- 2026-11-03: `AIMisreading.corrected`, `RegionTranslator.translate`가 엔진에 고친 글을 보낸다. 언어는 가장 높은 언어 하나가 아니라
  "Al"이 낱말인 언어들의 확률 합으로 본다("Al" 하나는 루마니아어 0.33, "Al tools"는 카탈루냐어 0.31이 가장 높아 고치지 못했다.
  합: "Al" 0.85, "Al tools" 0.64, "Al final"·"Al revés"·"Al menos" 0.94~0.97). 테스트 33개 추가(고침 15, 둠 17, 엔진 요청 1).
  로컬 모델에 고친 글 9개를 5번씩: 45/45 "AI" 유지("AI tools" → "AI 도구들", "Google Launches New AI Model" → "구글, 새로운 AI 모델을
  출시함", "AI-powered search" → "AI 기반 검색"). 검증 루프 시도 1 통과. 실제 렌즈 화면 확인은 사용자 확인 필요
