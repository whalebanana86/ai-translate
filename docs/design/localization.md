# 앱 화면 언어

다루는 범위: 화면 글 문자열 카탈로그, 한국어·영어 고르기.

이 영역의 코드를 바꾸기 전에 읽고, 바꾼 동작과 그 이유(사용자 요청·측정값·실패한 방법)를 여기에 적는다.
모든 작업에 공통인 규칙은 [AGENTS.md](../../AGENTS.md)에 있다.

- 화면 언어(TASK-058, 사용자 요청: 한국어·영어, 기본은 시스템 설정): 화면 글은 문자열 카탈로그(`App/Localizable.xcstrings`,
  `TranslateCore/Resources/Localizable.xcstrings`)에 둔다. 원문 언어는 한국어(코드의 한국어 글이 키, `project.yml`
  `developmentLanguage: ko`, 패키지 `defaultLocalization: "ko"`)이고 영어 번역을 채운다
  - SwiftUI에 글자 그대로 넘기는 글(`Text`·`Button`·`.help` 등)은 그대로 찾아진다. `NSAlert`·창 제목·오류 문구처럼 `String`으로 넘기는
    글은 `String(localized:)`, TranslateCore는 `String(localized:bundle: .module)`. 로그와 번역 대상 언어 이름(자국어)은 번역하지 않는다
  - 새 화면 글: 빌드 뒤 `./scripts/sync-strings.sh`(컴파일러가 뽑은 `.stringsdata`로 카탈로그에 더함)를 돌리고 영어를 채운다.
    `LocalizationCatalogTests`가 영어 번역 누락·형식 자리(%@ 등) 불일치·쓰지 않는 글(stale)·카탈로그에 없는 TranslateCore 화면 글을 잡는다.
    `swift build`·`swift test`는 카탈로그를 컴파일하지 않아 테스트에서는 한국어 원문이 나온다(앱은 xcodebuild가 컴파일)
  - 언어 고르기(설정 "언어", `AppLanguage`, `App/AppLanguageSettings.swift`): macOS 앱별 언어와 같은 값(앱 도메인 `AppleLanguages`)을
    쓴다. 시스템 설정은 값을 지운다. 화면 글은 앱이 시작할 때 정해지므로 바꾸면 "다시 시작"을 보인다(앱이 끝나기를 기다렸다가 `open`으로
    다시 여는 `/bin/sh`를 띄우고 종료. 번역 엔진 호출이 아니라 `ProcessExecutor`를 쓰지 않는다). 시스템 언어가 한국어·영어가 아니면
    개발 언어인 한국어로 보인다(`-AppleLanguages (ja)`로 확인)
  - 앱 도메인에 `AppleLanguages`를 두면 `Locale.preferredLanguages`도 그 값만 돌려주므로, 번역 대상 언어 기본값은 전역 값
    (`AppLanguage.systemLanguages()`)으로 정한다(영어 화면에서도 대상 언어 기본값은 시스템 언어)
