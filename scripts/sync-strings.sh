#!/usr/bin/env bash
# 코드의 화면 글을 문자열 카탈로그(Localizable.xcstrings)와 맞춘다 (TASK-058).
# 마지막 빌드(auto-fix-loop.sh·run-app.sh)에서 컴파일러가 뽑아 둔 글(.stringsdata)로 새 글을 카탈로그에 더하고, 코드에서 없어진 글은
# stale로 표시한다. 그다음 새 글에 영어 번역을 채운다: 번역이 빠졌거나 stale이 남으면 swift test(LocalizationCatalogTests)가 실패한다
set -euo pipefail
cd "$(dirname "$0")/.."

readonly INTERMEDIATES=.build/DerivedData/Build/Intermediates.noindex

sync_catalog() {
    local catalog=$1 objects=$2
    local args=()
    for file in "$objects"/*.stringsdata; do
        args+=(--stringsdata "$file")
    done
    if [ ${#args[@]} -eq 0 ]; then
        echo "빌드 결과가 없습니다: $objects (./scripts/auto-fix-loop.sh 또는 ./scripts/run-app.sh로 먼저 빌드)" >&2
        exit 1
    fi
    xcrun xcstringstool sync "$catalog" "${args[@]}"
    echo "맞춤: $catalog"
}

sync_catalog App/Localizable.xcstrings \
    "$INTERMEDIATES/AITranslate.build/Debug/AITranslate.build/Objects-normal/$(uname -m)"
sync_catalog Packages/TranslateCore/Sources/TranslateCore/Resources/Localizable.xcstrings \
    "$INTERMEDIATES/TranslateCore.build/Debug/TranslateCore.build/Objects-normal/$(uname -m)"
