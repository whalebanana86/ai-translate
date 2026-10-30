# TASK-010: 개발 빌드의 화면 기록 권한 유지 (이 맥 전용 개발 서명)

- 상태: COMPLETED
- 생성일: 2026-10-30

## 요청

사용자: "권한유지에 필요한거 진행해". 지금은 팀 ID가 없어 임시 서명(ad-hoc)으로 실행한다. 임시 서명은 macOS가 실행 파일
해시(cdhash)로 권한을 기억하므로, 코드를 바꿔 다시 빌드할 때마다 화면 기록 권한이 풀린다.

## 설계

- 이 맥에서만 쓰는 자체 서명 코드 서명 인증서("AITranslate Local Development")를 로그인 키체인에 만든다.
  인증서로 서명하면 서명 요구사항(designated requirement)이 `identifier + 인증서` 기준이 되어 다시 빌드해도 같다
  → 권한이 유지된다. Apple 계정·팀 ID가 필요 없다
- `scripts/setup-dev-signing.sh`: 인증서가 없을 때만 만든다 (LibreSSL로 키·인증서 생성 → p12 → `security import`,
  codesign만 키 사용 허용). 임시 파일은 끝나면 지운다. 개인 키는 키체인에만 남는다
- `scripts/run-app.sh`: 빌드 후 이 인증서로 다시 서명한다 (`--options runtime`, 엔타이틀먼트 유지). 인증서가 없으면
  지금처럼 임시 서명으로 실행하고 설정 스크립트를 안내한다
- 처음 서명할 때 macOS가 키체인 접근을 물을 수 있다 ("항상 허용"을 한 번 누르면 된다)
- 바뀐 서명으로 처음 실행할 때 권한을 한 번 더 허용해야 한다. 그 뒤로는 유지된다

## 요구사항

1. `scripts/setup-dev-signing.sh` 추가, 실행해 인증서 생성
2. `scripts/run-app.sh`가 개발 인증서로 다시 서명
3. 두 번 빌드(코드 변경 포함)해도 서명 요구사항이 같음을 확인
4. `AGENTS.md`의 서명 규칙 갱신

범위 밖: 팀 서명(Personal Team·Developer ID), 권한 재요청 처리 개선

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 개발 인증서가 키체인에 있고 codesign으로 서명할 수 있다.
- [x] AC2. `run-app.sh`로 만든 앱의 서명이 개발 인증서이고, 서명 요구사항이 `identifier "com.example.AITranslate" and certificate leaf = ...` 형태다.
- [x] AC3. 코드를 바꿔 다시 빌드해도 서명 요구사항이 같다.
- [x] AC4. 설정 스크립트를 다시 실행해도 인증서를 중복으로 만들지 않는다.
- [x] AC5. `AGENTS.md` 갱신.
- [x] AC6. `./scripts/auto-fix-loop.sh` 통과.

## 진행 기록

- 2026-10-30: TASK 생성. 현재 코드 서명 인증서 0개, 앱은 임시 서명(`flags=0x2(adhoc)`), Frameworks 없음(패키지는 정적 연결).
- 2026-10-30: `scripts/setup-dev-signing.sh` 작성·실행. 인증서 생성(`CSSMERR_TP_NOT_TRUSTED`는 자체 서명이라 정상),
  다시 실행하면 "이미 있음". 시험 서명이 키체인 확인 창 없이 성공, 서명 요구사항이 인증서 기준.
- 2026-10-30: `run-app.sh` 1차(앱만 다시 서명): 시작 즉시 종료. 원인: Debug 빌드의 `AITranslate.debug.dylib`가 임시 서명으로
  남아 "different Team IDs"로 로드 거부. 2차(dylib도 서명, `--options runtime`): 같은 이유로 종료. 강화된 런타임의 라이브러리
  검증은 팀 ID가 같아야 하는데 자체 서명 인증서는 팀 ID가 없음. 기존 Xcode 임시 서명 Debug 빌드도 강화된 런타임 없이
  서명됨(`flags=0x2(adhoc)`)을 확인 → 개발 서명에서 강화된 런타임 제외. 3차: 정상 실행(pid 2100), 오류 보고서 없음.
- 2026-10-30: AC3 확인: 앱 복사본의 Info.plist와 라이브러리를 바꿔 다시 서명 → 앱 cdhash 5577e785… → 302d56be…로 바뀌었지만
  서명 요구사항은 `identifier "com.example.AITranslate" and certificate leaf = H"27fd86b8…"`로 같음.
  실제 권한 유지는 다음 재빌드(TASK-011) 후 사용자가 확인.
- 2026-10-30: `AGENTS.md` 서명 규칙·개발 명령 갱신. 검증 루프 시도 1 통과.
