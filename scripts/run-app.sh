#!/usr/bin/env bash
# 앱을 빌드하고 개발 인증서로 서명해 실행한다. 이미 실행 중이면 종료한 뒤 다시 띄운다.
#
# 개발 인증서(`scripts/setup-dev-signing.sh`)로 서명하면 화면 기록 권한이 인증서 기준이라 다시 빌드해도 유지된다.
# 인증서가 없으면 임시 서명(ad-hoc)으로 실행하며, 빌드할 때마다 권한이 풀릴 수 있다. 그때는 기록을 지우고 다시 허용한다:
#   tccutil reset ScreenCapture com.example.AITranslate
set -euo pipefail
cd "$(dirname "$0")/.."

readonly APP=.build/DerivedData/Build/Products/Debug/AITranslate.app
readonly SIGNING_IDENTITY="AITranslate Local Development"

xcodegen generate --quiet
xcodebuild -project AITranslate.xcodeproj -scheme AITranslate -configuration Debug \
    -derivedDataPath .build/DerivedData \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" -quiet build

if security find-certificate -c "$SIGNING_IDENTITY" >/dev/null 2>&1; then
    # Debug 빌드는 실행 파일 옆에 라이브러리(AITranslate.debug.dylib 등)를 둔다. 안쪽 라이브러리부터 같은 인증서로 서명한다.
    # 강화된 런타임(--options runtime)은 쓰지 않는다: 라이브러리를 팀 ID가 같을 때만 로드하는데 자체 서명 인증서에는
    # 팀 ID가 없어 앱이 시작하자마자 종료된다. Xcode의 임시 서명 Debug 빌드도 강화된 런타임 없이 서명된다
    find "$APP/Contents/MacOS" -name '*.dylib' -exec codesign --force --sign "$SIGNING_IDENTITY" {} \;
    codesign --force --preserve-metadata=entitlements --sign "$SIGNING_IDENTITY" "$APP"
else
    echo "경고: 개발 인증서가 없어 임시 서명으로 실행합니다. 빌드할 때마다 화면 기록 권한이 풀릴 수 있습니다." >&2
    echo "      ./scripts/setup-dev-signing.sh 를 한 번 실행하세요." >&2
fi

if pgrep -x AITranslate >/dev/null; then
    pkill -x AITranslate
    while pgrep -x AITranslate >/dev/null; do sleep 0.2; done
fi
open "$APP"
echo "실행: $APP"
