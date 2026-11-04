#!/usr/bin/env bash
# 코드의 화면 글을 문자열 카탈로그(Localizable.xcstrings)와 맞춘다 (TASK-058).
# 마지막 빌드(auto-fix-loop.sh·run-app.sh)에서 컴파일러가 뽑아 둔 글(.stringsdata)로 새 글을 카탈로그에 더하고, 코드에서 없어진 글은
# stale로 표시한다. 그다음 새 글에 영어 번역을 채운다: 번역이 빠졌거나 stale이 남으면 swift test(LocalizationCatalogTests)가 실패한다
#
# 사용법
#   ./scripts/sync-strings.sh          카탈로그에 새 글을 더하고 없어진 글을 표시한다
#   ./scripts/sync-strings.sh --check  카탈로그는 바꾸지 않고, 맞출 글이 있으면 실패한다 (검증 루프 strings 단계, TASK-076)
set -euo pipefail
cd "$(dirname "$0")/.."

readonly INTERMEDIATES=.build/DerivedData/Build/Intermediates.noindex

CHECK=0
case "${1:-}" in
"") ;;
--check) CHECK=1 ;;
*)
    echo "사용법: $0 [--check]" >&2
    exit 64
    ;;
esac

# 지금 있는 소스 파일에서 나온 .stringsdata. 지운 소스 파일의 결과가 빌드 폴더에 남아 있으면 없어진 글을 알아보지 못한다
current_stringsdata() {
    python3 -I - "$1" <<'PY'
import glob, json, os, sys
for path in sorted(glob.glob(os.path.join(sys.argv[1], "*.stringsdata"))):
    with open(path, encoding="utf-8") as f:
        source = json.load(f).get("source")
    if not source or os.path.exists(source):
        print(path)
PY
}

# 맞추기 전·후 카탈로그를 비교해 새 글과 없어진 글을 보여준다. 있으면 exit 1
compare_catalogs() {
    python3 -I - "$1" "$2" "$3" <<'PY'
import json, sys
name, before_path, after_path = sys.argv[1:]
with open(before_path, encoding="utf-8") as f:
    before = json.load(f)["strings"]
with open(after_path, encoding="utf-8") as f:
    after = json.load(f)["strings"]
added = sorted(set(after) - set(before))
removed = sorted(
    key for key in before
    if key not in after or (after[key].get("extractionState") == "stale" and before[key].get("extractionState") != "stale"))
for key in added:
    print(f"error: {name}: 카탈로그에 없는 화면 글: {key}")
for key in removed:
    print(f"error: {name}: 코드에서 없어진 글: {key}")
sys.exit(1 if added or removed else 0)
PY
}

FAILED=0

sync_catalog() {
    local catalog=$1 objects=$2
    local args=() file
    while IFS= read -r file; do
        args+=(--stringsdata "$file")
    done < <(current_stringsdata "$objects")
    if [ ${#args[@]} -eq 0 ]; then
        echo "error: 빌드 결과가 없습니다: $objects (./scripts/auto-fix-loop.sh 또는 ./scripts/run-app.sh로 먼저 빌드)" >&2
        exit 1
    fi
    if ((!CHECK)); then
        xcrun xcstringstool sync "$catalog" "${args[@]}"
        echo "맞춤: $catalog"
        return
    fi
    # 표 이름은 파일 이름에서 오므로 사본도 Localizable.xcstrings로 둔다 (다른 이름이면 모든 글이 stale이 된다)
    local scratch
    scratch=$(mktemp -d)
    cp "$catalog" "$scratch/Localizable.xcstrings"
    xcrun xcstringstool sync "$scratch/Localizable.xcstrings" "${args[@]}"
    compare_catalogs "$catalog" "$catalog" "$scratch/Localizable.xcstrings" || FAILED=1
    rm -rf "$scratch"
}

sync_catalog App/Localizable.xcstrings \
    "$INTERMEDIATES/AITranslate.build/Debug/AITranslate.build/Objects-normal/$(uname -m)"
sync_catalog Packages/TranslateCore/Sources/TranslateCore/Resources/Localizable.xcstrings \
    "$INTERMEDIATES/TranslateCore.build/Debug/TranslateCore.build/Objects-normal/$(uname -m)"

if ((FAILED)); then
    echo "error: 화면 글 카탈로그가 코드와 맞지 않습니다. ./scripts/sync-strings.sh를 돌리고 새 글에 영어를 채우세요 (AGENTS.md 3장)"
    exit 1
fi
if ((CHECK)); then
    echo "화면 글 카탈로그가 코드와 맞습니다"
fi
