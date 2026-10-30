# TASK-013: Hugging Face 번역 전용 모델 조사

- 상태: COMPLETED
- 생성일: 2026-10-30

## 요청

사용자: "애플번역은 안쓸게 그리고 언어번역모델로 허깅페이스에서 찾아봐".
기준: 이 맥(M5, 24GB)에서 로컬 실행, 한국어 품질, 외부 배포 가능한 라이선스, Ollama 등으로 돌릴 수 있는 형식.

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 후보 모델의 크기·언어(한국어)·라이선스·실행 형식을 모델 카드에서 확인해 기록한다.
- [x] AC2. 비교할 후보와 제외 이유를 사용자에게 보고한다.
- [x] AC3. Apple 번역 제외 결정을 `AGENTS.md`에 기록한다.

## 진행 기록

- 2026-10-30: TASK 생성. 검색 + 모델 카드 확인 (Hy-MT2 1.8B/7B GGUF, TranslateGemma 4B·Ollama·Google 블로그,
  LMT-60 4B/8B, Seed-X-PPO-7B·OpenMDW 라이선스 본문).
- 확인 결과
  - Hy-MT2 (Tencent, 2026-05-21): 1.8B·7B·30B-A3B, 33개 언어(ko 포함), 메타데이터 apache-2.0(카드에 지역 제한 문구 없음,
    LICENSE 파일은 미확인). GGUF Q4_K_M 1.8B 1.13GB·7B 4.62GB, `ollama run hf.co/tencent/Hy-MT2-1.8B-GGUF:Q4_K_M`.
    카드에 "STQ 커널(llama.cpp PR #22836) 필요" 문구 → Ollama에서 도는지 확인 필요. 프롬프트: "Translate the following text into
    {target_lang}. … only output the translated result …" + 빈 줄 + 원문. 원문 언어 지정 불필요. 수치는 이미지·논문에만 있음
  - TranslateGemma (Google, 2026-01-15): 4B·12B·27B, Gemma 3 기반, 55개 언어(ko 포함), 라이선스 gemma(Gemma 이용약관, 동의 후
    다운로드). Ollama 공식 `translategemma:4b` 3.3GB·`:12b` 8.1GB. 프롬프트에 원문·대상 언어 이름과 코드를 넣어야 함(원문 언어
    판정 필요). WMT24++ MetricX 4B 5.32·12B 3.60, Comet 81.6·83.5. 한국어별 수치 없음
  - LMT-60 (NiuTrans, 2025-11): 0.6B~8B, Qwen3 기반, 60개 언어(ko는 중간 자원), apache-2.0, 공식 GGUF 없음, 중국어·영어 중심
  - Seed-X-PPO-7B (ByteDance, 2025-07): 28개 언어(ko 포함), OpenMDW-1.0(제한 없이 사용 허용, 재배포 시 라이선스·고지 유지),
    공식 양자화는 GPTQ·AWQ뿐(GGUF·MLX 없음), 비공식 양자화 비권장, 빔 서치 권장
  - 검색 결과로만 확인: Hunyuan-MT-7B는 같은 계열 라이선스에 한국·EU·영국 제외 조항(한국 사용자 배포에 부적합),
    NLLB는 비상업 라이선스, OPUS-MT en-ko는 영→한 전용 소형 모델
- 2026-10-30: `AGENTS.md` 2장에 "쓰지 않는 엔진: Apple 번역" 추가. 검증 루프 통과(코드 변경 없음).
- 추천 비교 후보: Hy-MT2-1.8B(속도), Hy-MT2-7B(품질), TranslateGemma 4B(대안), 여유 있으면 TranslateGemma 12B.
  다운로드 약 9GB(12B 포함 17GB) — 사용자 승인 후 진행.
- 통합 시 고려: 번역 전용 모델은 글 하나씩 번역하도록 학습됨 → 문단마다 따로 요청(JSON 묶음 대신). TranslateGemma는 원문 언어
  판정이 필요.
