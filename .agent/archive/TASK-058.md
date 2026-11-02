# TASK-058: 앱 화면 언어 고르기 (시스템 설정·한국어·English)

- 상태: COMPLETED
- 생성일: 2026-11-03

## 요청

"설정에 언어 기능 한글이랑 영어 선택하게 해주고 기본은 시스템설정으로 해줘" (2026-11-03). 앱 화면(메뉴, 설정, 렌즈 도구 막대,
알림창, 오류 문구) 언어를 고른다. 번역 대상 언어(도구 막대 언어 고르기)와는 다르다

## 설계

- 문자열 카탈로그(`Localizable.xcstrings`): 원문 언어 한국어(지금 코드의 한국어 글이 키), 영어 번역
  - 앱: `App/Localizable.xcstrings`. SwiftUI 글(`Text`, `Button`, `.help` 등)은 그대로 찾아지고, `NSAlert`·창 제목·오류 문구는
    `String(localized:)`
  - TranslateCore: 화면에 나오는 글(엔진 이름·설명·전송 대상, Claude 모델 설명, 오류 문구)을 `String(localized:bundle: .module)`,
    패키지 `defaultLocalization: "ko"`, `Resources/Localizable.xcstrings`
  - 번역 대상 언어 이름(한국어, English, 日本語 …)은 자국어 이름이라 그대로 둔다. 로그 문구는 화면에 나오지 않아 그대로 둔다
- 언어 고르기: macOS 앱별 언어와 같은 값(앱 도메인의 `AppleLanguages`)을 쓴다. 시스템 설정 = 값을 지움(기본), 한국어·English = 그 언어로 고정.
  화면 글은 앱이 시작할 때 정해지므로 바꾸면 "다시 시작" 버튼을 보여 준다(앱이 끝나기를 기다렸다가 다시 연다)
- 앱 언어를 영어로 고정해도 번역 대상 언어 기본값(저장한 값이 없을 때)은 시스템 언어를 따른다: 앱 도메인에 `AppleLanguages`를 두면
  `Locale.preferredLanguages`가 그 값을 돌려주므로 전역 값을 읽는다

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 설정에 언어 고르기(시스템 설정 기본·한국어·English). 바꾸면 다시 시작 안내와 버튼.
- [x] AC2. 영어로 실행하면 메뉴·설정·렌즈 도구 막대(툴팁 포함)·알림창·오류 문구가 영어 (실제 앱에서 확인). 시스템 설정이면 시스템 언어.
- [x] AC3. 카탈로그의 모든 글에 영어 번역이 있고 형식 자리(%@ 등)가 맞는다, TranslateCore 화면 글이 모두 카탈로그에 있다 (테스트).
- [x] AC4. 앱 언어를 영어로 해도 번역 대상 언어 기본값은 시스템 언어 (테스트 또는 실제 앱 확인).
- [x] AC5. README·`AGENTS.md` 갱신, `./scripts/auto-fix-loop.sh` 통과.

## 진행 기록

- 2026-11-03: TASK 생성.
- 2026-11-03: 카탈로그 두 개(앱 71개, TranslateCore 21개, 번역하지 않는 글 5개는 `shouldTranslate: false`), `AppLanguage`,
  `AppLanguageSettings`(설정 "언어", 다시 시작), 대상 언어 기본값은 전역 언어, `scripts/sync-strings.sh`, 테스트 2묶음(6개).
  - 처음 빌드는 `en.lproj`만 생기고 개발 언어가 en이라 한국어 시스템에서도 영어로 나왔다 → `developmentLanguage: ko`
  - SwiftPM 명령줄 빌드는 `.xcstrings`를 컴파일하지 않고 복사만 한다(시험 패키지로 확인) → 테스트는 카탈로그 JSON을 직접 읽는다
  - 테스트가 가려내는지 확인: 영어 번역을 지우거나 형식 자리를 바꾸거나 TranslateCore 키를 지우면 실패
  - 실제 앱(개발 빌드, 손쉬운 사용 API로 확인): 시스템(한국어) → 한국어 메뉴, `-AppleLanguages (en)` → 영어 메뉴·설정 창,
    `(ja)` → 한국어. 설정에서 English 고름 → "앱을 다시 시작하면 바뀝니다"·"다시 시작" → 누르면 새 프로세스로 영어 메뉴,
    렌즈 도구 막대 툴팁 영어, 번역 대상 언어 기본값은 한국어 그대로(저장한 값 없음). 시스템 설정으로 되돌려 다시 시작 → 한국어,
    앱 도메인 `AppleLanguages` 지워짐. 알림창(전송 안내·화면 기록 권한)은 띄우지 않아 화면으로는 보지 못함(카탈로그 테스트로 확인)
  - README 설정 그림을 다시 그림(언어 항목), 영어 README용 영어 그림 `settings-en.png`
  - 검증 루프 시도 1 통과
