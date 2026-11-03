# 개발 서명과 이 맥용 릴리즈

다루는 범위: 개발 인증서 서명, 화면 기록 권한 유지, `install-release.sh`.

이 영역의 코드를 바꾸기 전에 읽고, 바꾼 동작과 그 이유(사용자 요청·측정값·실패한 방법)를 여기에 적는다.
모든 작업에 공통인 규칙은 [AGENTS.md](../../AGENTS.md)에 있다.

- 개발 빌드는 다시 빌드해도 서명 요구사항이 같게 서명한다. 임시 서명(ad-hoc)은 macOS가 실행 파일 해시로 권한을 기억해
  빌드할 때마다 화면 기록 권한이 풀린다
  - 팀 ID가 없으므로 이 맥 전용 자체 서명 인증서 "AITranslate Local Development"를 쓴다. `scripts/setup-dev-signing.sh`를
    한 번 실행해 로그인 키체인에 만들고(개인 키는 codesign만 사용), `scripts/run-app.sh`가 빌드 후 이 인증서로 다시 서명한다.
    서명 요구사항: `identifier "com.example.AITranslate" and certificate leaf = H"..."` (실행 파일이 바뀌어도 같음)
  - Debug 빌드의 `Contents/MacOS/*.dylib`(AITranslate.debug.dylib 등)도 같은 인증서로 먼저 서명한다. 강화된 런타임은 쓰지
    않는다: 라이브러리를 팀 ID가 같을 때만 로드하는데 자체 서명 인증서에는 팀 ID가 없어 앱이 시작하자마자 종료된다.
    강화된 런타임과 공증은 배포 서명(Developer ID)에서 한다
  - 인증서가 없으면 `run-app.sh`는 임시 서명으로 실행하고 경고한다. 권한이 풀리면
    `tccutil reset ScreenCapture com.example.AITranslate` 후 다시 허용한다
  - 팀 ID가 생기면 `project.yml`에 넣고 팀 서명으로 바꾼다
  - 이 맥용 릴리즈(`scripts/install-release.sh`, TASK-049): Release 빌드(이 맥 아키텍처만, 약 4분)를 같은 개발 인증서로 서명해
    `/Applications/AITranslate.app`에 설치한다. 서명 요구사항이 개발 빌드와 같아 화면 기록 권한·설정·받은 모델을 함께 쓴다.
    번들 ID가 같아 개발 빌드와 함께 띄우지 않는다(스크립트가 실행 중인 앱을 종료). 외부 배포용이 아니다(Developer ID·공증 없음).
    버전은 `project.yml`의 `MARKETING_VERSION`이고 릴리즈마다 `v<버전>` 태그를 붙인다
