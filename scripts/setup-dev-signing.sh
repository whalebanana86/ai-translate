#!/usr/bin/env bash
# 이 맥에서만 쓰는 개발용 코드 서명 인증서를 로그인 키체인에 만든다. 이미 있으면 아무것도 하지 않는다.
#
# 임시 서명(ad-hoc)은 macOS가 실행 파일 해시로 화면 기록 권한을 기억해서, 다시 빌드할 때마다 권한이 풀린다.
# 인증서로 서명하면 권한이 `번들 ID + 인증서` 기준이 되어 다시 빌드해도 유지된다. Apple 계정·팀 ID는 필요 없다.
# 신뢰하는 인증서가 아니므로 다른 맥에서는 의미가 없고, 배포용 서명(Developer ID)을 대신하지 않는다.
#
# 지우려면: security delete-identity -c "AITranslate Local Development"
set -euo pipefail

readonly NAME="AITranslate Local Development"
readonly KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "이미 있음: $NAME"
    exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# p12 파일을 잠깐 감싸는 일회용 비밀번호. 파일과 함께 바로 지운다
passphrase=$(/usr/bin/openssl rand -hex 16)

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NAME" \
    -keyout "$work/key.pem" -out "$work/cert.pem" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "$NAME" \
    -out "$work/identity.p12" -passout "pass:$passphrase"
# 개인 키는 codesign만 쓸 수 있게 한다
security import "$work/identity.p12" -k "$KEYCHAIN" -P "$passphrase" -T /usr/bin/codesign >/dev/null

echo "만듦: $NAME"
