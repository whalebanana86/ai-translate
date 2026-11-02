#!/usr/bin/env bash
# 이 맥에서 쓸 릴리즈 빌드를 만들어 /Applications에 설치하고 실행한다. 이미 실행 중이면(개발 빌드 포함) 종료한다.
#
# 외부 배포용이 아니다: Developer ID 서명·공증이 없어 다른 맥에서는 열리지 않는다 (AGENTS.md 출시 전 필수 조건).
# 개발 빌드(`scripts/run-app.sh`)와 같은 개발 인증서로 서명하므로 화면 기록 권한과 설정(UserDefaults)·받은 모델을 함께 쓴다.
# 번들 ID가 같아 둘이 함께 뜨면 메뉴바 아이콘과 단축키가 겹치므로 하나만 띄운다.
set -euo pipefail
cd "$(dirname "$0")/.."

readonly BUILT=.build/DerivedData/Build/Products/Release/AITranslate.app
readonly INSTALLED=/Applications/AITranslate.app
readonly SIGNING_IDENTITY="AITranslate Local Development"

# 임시 서명은 설치할 때마다 화면 기록 권한이 풀리므로 설치하지 않는다
if ! security find-certificate -c "$SIGNING_IDENTITY" >/dev/null 2>&1; then
    echo "개발 인증서가 없습니다. ./scripts/setup-dev-signing.sh 를 먼저 실행하세요." >&2
    exit 1
fi

xcodegen generate --quiet
# 이 맥 아키텍처만 빌드한다 (Release 기본값은 Intel·Apple Silicon 둘 다)
xcodebuild -project AITranslate.xcodeproj -scheme AITranslate -configuration Release \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" -quiet build

# 안쪽 라이브러리부터 같은 인증서로 서명한다. 강화된 런타임은 쓰지 않는다(run-app.sh와 같은 이유: 자체 서명 인증서에는
# 팀 ID가 없어 라이브러리를 로드하지 못한다)
find "$BUILT/Contents/Frameworks" -name '*.dylib' -exec codesign --force --sign "$SIGNING_IDENTITY" {} \;
codesign --force --preserve-metadata=entitlements --sign "$SIGNING_IDENTITY" "$BUILT"
codesign --verify --strict "$BUILT"

if pgrep -x AITranslate >/dev/null; then
    pkill -x AITranslate
    while pgrep -x AITranslate >/dev/null; do sleep 0.2; done
fi
rm -rf "$INSTALLED"
ditto "$BUILT" "$INSTALLED"
open "$INSTALLED"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALLED/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INSTALLED/Contents/Info.plist")
echo "설치: $INSTALLED ($version, 빌드 $build)"
