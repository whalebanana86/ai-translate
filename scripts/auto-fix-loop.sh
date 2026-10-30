#!/usr/bin/env bash
# 자동 검증 루프의 한 회차를 실행한다: 타입 검사 → Lint → 빌드 → 테스트.
# 재시도 제한과 실행 기록은 이 스크립트가 강제한다 (AGENTS.md 5.3).
#
# 사용법
#   ./scripts/auto-fix-loop.sh                 .agent/PROGRESS.md의 현재 TASK로 실행
#   ./scripts/auto-fix-loop.sh TASK-002        TASK를 지정해 실행
#   ./scripts/auto-fix-loop.sh --reset "사유"  중단된 루프를 새로 시작 (사용자 승인 필요)
#
# 종료 코드
#   0   검증 통과
#   1   검증 실패. 원인을 고친 뒤 다시 실행할 수 있다
#   2   루프 중단 (재시도 초과, 시간 초과, 동일 오류 반복). 더 재시도하지 말고 보고한다
#   3   실행 거부. 이미 중단된 루프이며 사용자 승인 후 --reset이 필요하다
#   64  사용법 오류
set -uo pipefail

# 제한값. 환경 변수로 덮어쓰지 않는다
readonly MAX_RETRIES=3 # 최초 실행 포함 총 MAX_RETRIES+1회
readonly TIME_LIMIT_SEC=$((15 * 60))
readonly STEPS="typecheck lint build test"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 64
LOG_DIR="$ROOT/.build/auto-fix-loop"

usage() {
    sed -n '2,15p' "$0" | sed -E 's/^# ?//'
    exit "${1:-64}"
}

step_command() {
    case "$1" in
    typecheck)
        echo "swift build --package-path Packages/TranslateCore -Xswiftc -warnings-as-errors"
        ;;
    lint)
        echo "swift format lint --strict --recursive --configuration .swift-format" \
            "App Packages/TranslateCore/Package.swift Packages/TranslateCore/Sources Packages/TranslateCore/Tests"
        ;;
    build)
        echo "xcodegen generate --quiet &&" \
            "xcodebuild -project AITranslate.xcodeproj -scheme AITranslate -configuration Debug" \
            "-derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -quiet build"
        ;;
    test)
        echo "swift test --package-path Packages/TranslateCore"
        ;;
    esac
}

now() { date +%s; }
timestamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# key=value 쌍을 JSON 한 줄로 기록한다
json_append() {
    python3 -I - "$ATTEMPTS" "$@" <<'PY'
import json, sys
path, *pairs = sys.argv[1:]
int_keys = {"loop", "attempt", "exit_code", "duration_s", "started_epoch"}
entry = {}
for pair in pairs:
    key, _, value = pair.partition("=")
    entry[key] = int(value) if key in int_keys else value[:2000]
with open(path, "a", encoding="utf-8") as f:
    f.write(json.dumps(entry, ensure_ascii=False) + "\n")
PY
}

# 출력: <루프 번호> <현재 루프의 실행 횟수> <첫 실행 epoch> <직전 실패 서명> <중단 여부>
# 루프는 통과(pass) 또는 reset 기록에서 끝나고, 그다음 기록부터 새 루프가 시작된다
read_state() {
    python3 -I - "$ATTEMPTS" <<'PY'
import json, os, sys
path = sys.argv[1]
entries = []
if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        entries = [json.loads(line) for line in f if line.strip()]
loop, current = 1, []
for entry in entries:
    current.append(entry)
    if entry.get("result") == "pass" or entry.get("event") == "reset":
        loop, current = loop + 1, []
runs = [e for e in current if e.get("result") in ("pass", "fail")]
fails = [e for e in runs if e["result"] == "fail"]
stopped = any(e.get("result") == "stopped" for e in current)
first = runs[0]["started_epoch"] if runs else 0
print(loop, len(runs), first, fails[-1]["signature"] if fails else "-", int(stopped))
PY
}

# 마감 시각까지 명령을 실행한다. 넘기면 프로세스 그룹 전체를 종료하고 124를 반환한다
run_until() {
    local deadline=$1 log=$2 command=$3 pid
    perl -e 'setpgrp(0, 0); exec @ARGV or die "exec failed: $!\n"' /bin/bash -c "$command" >"$log" 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if (($(now) >= deadline)); then
            kill -TERM -- "-$pid" 2>/dev/null
            sleep 2
            kill -KILL -- "-$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            echo "시간 제한 초과로 종료됨" >>"$log"
            return 124
        fi
        sleep 1
    done
    wait "$pid"
}

# 로그에서 오류로 보이는 줄을 중복 없이 뽑는다. 없으면 마지막 20줄
error_lines() {
    local lines
    lines=$(grep -E 'error:|warning:|✘|FAIL|[Ff]ailed' "$1" | awk '!seen[$0]++' | head -30)
    [[ -n "$lines" ]] || lines=$(tail -20 "$1")
    printf '%s\n' "${lines//"$ROOT"\//}"
}

# 위치가 붙은 진단(파일:줄:열: error/warning)과 테스트 실패 줄만 모아 서명을 만든다.
# 병렬 빌드라 드라이버 메시지와 출력 순서는 실행마다 달라지므로 제외하고 정렬한다.
# 숫자(줄·열 번호 등)도 지워서 코드가 조금 바뀌어도 같은 오류는 같은 서명이 되게 한다
error_signature() {
    local lines
    lines=$(grep -E ':[0-9]+:[0-9]+: (error|warning):|✘' "$2")
    [[ -n "$lines" ]] || lines=$(error_lines "$2")
    printf '%s\n%s\n' "$1" "${lines//"$ROOT"\//}" | sed -E 's/[0-9]+//g' | sort -u | shasum -a 256 | cut -c1-16
}

stop_loop() {
    json_append ts="$(timestamp)" result=stopped loop="$LOOP" reason="$1"
    echo "루프 중단 ($1): 더 재시도하지 말고 TASK 파일에 원인과 현재 상태를 기록한 뒤 보고하세요." >&2
    exit 2
}

TASK_ID=""
RESET_REASON=""
while (($#)); do
    case "$1" in
    --reset)
        [[ $# -ge 2 && -n "$2" ]] || usage
        RESET_REASON=$2
        shift 2
        ;;
    -h | --help) usage 0 ;;
    TASK-*)
        TASK_ID=$1
        shift
        ;;
    *) usage ;;
    esac
done

if [[ -z "$TASK_ID" ]]; then
    TASK_ID=$(grep -m1 '^- 현재 작업:' .agent/PROGRESS.md 2>/dev/null | grep -oE 'TASK-[0-9]+')
fi
if [[ -z "$TASK_ID" || ! -f ".agent/tasks/$TASK_ID.md" ]]; then
    echo "오류: 진행 중인 TASK 파일을 찾을 수 없습니다 (TASK: ${TASK_ID:-없음})" >&2
    exit 64
fi
ATTEMPTS=".agent/attempts/$TASK_ID.jsonl"

read -r LOOP RUNS FIRST_EPOCH LAST_SIG STOPPED <<<"$(read_state)"
if [[ -z "${STOPPED:-}" ]]; then
    echo "오류: $ATTEMPTS 기록을 읽을 수 없습니다" >&2
    exit 64
fi

if [[ -n "$RESET_REASON" ]]; then
    if ((!STOPPED)); then
        echo "오류: --reset은 중단된 루프에서만 쓸 수 있습니다 (루프 ${LOOP}는 진행 중)" >&2
        exit 64
    fi
    json_append ts="$(timestamp)" event=reset loop="$LOOP" reason="$RESET_REASON"
    echo "${TASK_ID}: 루프 ${LOOP}를 닫고 새 루프를 시작합니다. 사유: ${RESET_REASON}"
    exit 0
fi

if ((STOPPED)); then
    echo "실행 거부: ${TASK_ID}의 루프 ${LOOP}는 이미 중단됐습니다." \
        "사용자 승인 후 --reset \"사유\"로 새 루프를 시작하세요." >&2
    exit 3
fi

NOW=$(now)
START=$((RUNS > 0 ? FIRST_EPOCH : NOW))
DEADLINE=$((START + TIME_LIMIT_SEC))
ATTEMPT=$((RUNS + 1))

if ((NOW >= DEADLINE)); then stop_loop time_limit; fi
if ((ATTEMPT > MAX_RETRIES + 1)); then stop_loop max_retries; fi

mkdir -p "$LOG_DIR"
echo "$TASK_ID 루프 $LOOP, 시도 $ATTEMPT/$((MAX_RETRIES + 1)), 남은 시간 $(((DEADLINE - NOW) / 60))분"

for step in $STEPS; do
    log="$LOG_DIR/$step.log"
    step_start=$(now)
    printf '  %-10s ' "$step"
    run_until "$DEADLINE" "$log" "$(step_command "$step")"
    code=$?
    if ((code == 0)); then
        echo "ok ($(($(now) - step_start))s)"
        continue
    fi
    echo "실패 (exit $code, $(($(now) - step_start))s)"

    signature=$(error_signature "$step" "$log")
    json_append ts="$(timestamp)" started_epoch="$NOW" loop="$LOOP" attempt="$ATTEMPT" result=fail \
        step="$step" exit_code="$code" duration_s="$(($(now) - NOW))" signature="$signature" \
        summary="$(error_lines "$log")"
    echo "----- $step 오류 (전체 로그: ${log#"$ROOT"/}) -----"
    error_lines "$log"
    echo "-----"

    if ((code == 124 || $(now) >= DEADLINE)); then stop_loop time_limit; fi
    if [[ "$signature" == "$LAST_SIG" ]]; then stop_loop repeated_error; fi
    if ((ATTEMPT >= MAX_RETRIES + 1)); then stop_loop max_retries; fi
    echo "검증 실패: 남은 재시도 $((MAX_RETRIES + 1 - ATTEMPT))회. 원인을 고친 뒤 다시 실행하세요."
    exit 1
done

json_append ts="$(timestamp)" started_epoch="$NOW" loop="$LOOP" attempt="$ATTEMPT" result=pass \
    duration_s="$(($(now) - NOW))"
echo "검증 통과"
