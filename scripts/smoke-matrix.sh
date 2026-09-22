#!/usr/bin/env bash
#
# smoke-matrix.sh — 测算接口冒烟矩阵
#
# 对健康检查与 POST /api/schedule 发一组请求，覆盖四类用例：
#   1. valid_persist_false   合法请求 persist=false  -> 成功，calc_runs 条数不变，run_id 为 null
#   2. valid_persist_true    合法请求 persist=true   -> 成功，calc_runs 条数 +1，run_id 非空，回包带月供
#   3. invalid_principal     本金非正 (<=0)          -> 非成功状态，calc_runs 条数不变
#   4. invalid_months        期数非法 (months<=0)    -> 非成功状态，calc_runs 条数不变
#
# 计数来自“默认库”的 calc_runs（docker compose 下即后端容器内 /data/app.db）。
# 脚本在矩阵前后各读一次计数：除 valid_persist_true 允许 +1 外，其余任何步骤
# （含健康检查、persist=false、两类非法请求）都不得改动条数，否则点名失败。
#
# 后端未启动 / 健康检查不可达 -> 立即非零退出。
# 任一用例失败 -> 收集全部失败用例名，结尾点名并以非零码退出。
#
# 用法（在仓库根目录、docker compose 起服后执行）：
#   docker compose up --build -d
#   ./scripts/smoke-matrix.sh
#
# 可选环境变量：
#   SMOKE_BASE_URL    后端地址，默认 http://localhost:9400
#   SMOKE_DB_PATH     直接读取宿主机上的 sqlite 文件（非容器化本地起服时用）
#   SMOKE_COUNT_CMD   完全自定义计数命令，其 stdout 须为 calc_runs 条数
#
# 注意：本脚本只断言 monthly_payment 为正数，绝不硬编码种子月供数字，
#       因此用例是否通过与种子数据中的金额无关。

set -u
set -o pipefail

BASE_URL="${SMOKE_BASE_URL:-http://localhost:9400}"
# 仓库根目录（脚本位于 <root>/scripts/ 下），用于定位 docker-compose.yml
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"
ERRF="$(mktemp)"
trap 'rm -f "$ERRF"' EXIT

HTTP=""
BODY=""
CURL_ERR=""
FAILURES=()

# ---------------------------------------------------------------------------
# 输出 calc_runs 当前条数到 stdout；失败时返回非零。
# 优先级：SMOKE_COUNT_CMD > SMOKE_DB_PATH > docker compose exec（默认库）。
# ---------------------------------------------------------------------------
count_runs() {
  local n
  if [ -n "${SMOKE_COUNT_CMD:-}" ]; then
    n="$(bash -c "$SMOKE_COUNT_CMD" 2>/dev/null)"
  elif [ -n "${SMOKE_DB_PATH:-}" ]; then
    n="$(SMOKE_DB_PATH="$SMOKE_DB_PATH" python3 - <<'PY' 2>/dev/null
import os, sqlite3
print(sqlite3.connect(os.environ["SMOKE_DB_PATH"])
      .execute("SELECT COUNT(*) FROM calc_runs").fetchone()[0])
PY
)"
  else
    # 默认：compose 后端容器里的默认库 /data/app.db
    # 用 -f 固定 compose 文件，使脚本可从任意目录调用
    n="$(docker compose -f "$COMPOSE_FILE" exec -T backend python -c \
      'import sqlite3; print(sqlite3.connect("/data/app.db").execute("SELECT COUNT(*) FROM calc_runs").fetchone()[0])' \
      2>/dev/null)"
  fi
  n="${n//[[:space:]]/}"
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$n"
}

# 从 stdin 读取 JSON，按 $1 表达式（变量 d 为回包对象）求值，打印 True/False。
# 表达式与程序均为本脚本内置；JSON 通过环境变量传入，避免与 stdin 抢占。
json_eval() {
  local json
  json="$(cat)"
  PY_EXPR="$1" PY_JSON="$json" python3 -c '
import json, os
try:
    d = json.loads(os.environ["PY_JSON"])
    ok = bool(eval(os.environ["PY_EXPR"], {"d": d}))
except Exception:
    ok = False
print("True" if ok else "False")'
}

http_get() { # $1 = path
  local out
  CURL_ERR=""
  out="$(curl -sS --connect-timeout 3 --max-time 10 \
        -w $'\n%{http_code}' "$BASE_URL$1" 2>"$ERRF")" || {
    CURL_ERR="$(cat "$ERRF")"; HTTP="000"; BODY=""; return 1; }
  HTTP="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
}

http_post_schedule() { # $1 = json body
  local out
  CURL_ERR=""
  out="$(curl -sS --connect-timeout 3 --max-time 15 \
        -H 'Content-Type: application/json' -X POST \
        -w $'\n%{http_code}' "$BASE_URL/api/schedule" -d "$1" 2>"$ERRF")" || {
    CURL_ERR="$(cat "$ERRF")"; HTTP="000"; BODY=""; return 1; }
  HTTP="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
}

record_fail() { FAILURES+=("$1"); printf '    [FAIL] %s\n' "$1"; }

# ---------------------------------------------------------------------------
# 0. 前置：健康检查。后端未启动 -> 立即失败退出。
# ---------------------------------------------------------------------------
printf '== health_check (GET %s/api/health)\n' "$BASE_URL"
if ! http_get "/api/health"; then
  printf '[FATAL] preflight:health_unreachable — 后端未启动或不可达: %s\n' "$CURL_ERR" >&2
  exit 1
fi
if [ "$HTTP" != "200" ]; then
  printf '[FATAL] preflight:health_status — 健康检查返回非 200: %s\n' "$HTTP" >&2
  exit 1
fi
if [ "$(json_eval 'd.get("ok") is True and d.get("project") == "mortgage"' <<<"$BODY")" != "True" ]; then
  printf '[FATAL] preflight:health_payload — 健康检查回包不符合预期: %s\n' "$BODY" >&2
  exit 1
fi
printf '    [PASS] http=200, payload ok\n'

# 矩阵前基线计数
baseline="$(count_runs)" || {
  printf '[FATAL] preflight:db_count — 无法读取默认库 calc_runs 计数\n' >&2
  exit 1
}
prev="$baseline"
printf '    calc_runs baseline = %s\n' "$baseline"

# ---------------------------------------------------------------------------
# 通用用例执行器
#   $1 用例名  $2 请求体  $3 期望(ok|rejected)  $4 期望条数增量
#   $5 run_id 期望(null|notnull|ignore)
# ---------------------------------------------------------------------------
run_case() {
  local name="$1" body="$2" expect="$3" want_delta="$4" run_id_want="$5"
  local before after delta
  printf '== %s\n' "$name"

  before="$(count_runs)" || { record_fail "$name:count_before"; return; }
  http_post_schedule "$body" || true
  after="$(count_runs)" || { record_fail "$name:count_after"; return; }
  delta=$((after - before))

  if [ "$expect" = "ok" ]; then
    if [ "$HTTP" = "200" ]; then
      printf '    [PASS] http=200\n'
    else
      record_fail "$name:http_status(want 200 got $HTTP${CURL_ERR:+ $CURL_ERR})"
    fi
    if [ "$HTTP" = "200" ]; then
      # 回包必须带月供，且为正数（不与任何种子月供数字比较）
      if [ "$(json_eval 'isinstance(d.get("monthly_payment"), (int, float)) and not isinstance(d.get("monthly_payment"), bool) and d["monthly_payment"] > 0' <<<"$BODY")" = "True" ]; then
        printf '    [PASS] monthly_payment present and positive\n'
      else
        record_fail "$name:monthly_payment(回包缺少为正的月供)"
      fi
      case "$run_id_want" in
        null)
          if [ "$(json_eval 'd.get("run_id") is None' <<<"$BODY")" = "True" ]; then
            printf '    [PASS] run_id is null (未落库)\n'
          else
            record_fail "$name:run_id(persist=false 却返回了非空 run_id)"
          fi
          ;;
        notnull)
          if [ "$(json_eval 'd.get("run_id") is not None' <<<"$BODY")" = "True" ]; then
            printf '    [PASS] run_id present (已落库)\n'
          else
            record_fail "$name:run_id(persist=true 却返回了空 run_id)"
          fi
          ;;
      esac
    fi
  else # rejected：必须非成功状态
    if [ "$HTTP" = "000" ]; then
      record_fail "$name:request($CURL_ERR)"
    elif [ "$HTTP" -ge 200 ] && [ "$HTTP" -lt 300 ]; then
      record_fail "$name:expected_non_success(got $HTTP)"
    else
      printf '    [PASS] non-success http=%s\n' "$HTTP"
    fi
  fi

  if [ "$delta" = "$want_delta" ]; then
    printf '    [PASS] calc_runs delta=%s\n' "$delta"
  else
    record_fail "$name:run_count_delta(want $want_delta got $delta)"
  fi
  prev="$after"
}

# ---------------------------------------------------------------------------
# 四类用例（本金/期数使用与种子数据无关的入参；不断言任何固定月供数值）
# ---------------------------------------------------------------------------
run_case "valid_persist_false" \
  '{"principal":500000,"annual_rate":3.1,"months":240,"persist":false,"preview_rows":6}' \
  ok 0 null

run_case "valid_persist_true" \
  '{"principal":600000,"annual_rate":3.6,"months":300,"persist":true,"preview_rows":6}' \
  ok 1 notnull

run_case "invalid_principal_nonpositive" \
  '{"principal":0,"annual_rate":3.6,"months":300,"persist":true}' \
  rejected 0 ignore

run_case "invalid_months_illegal" \
  '{"principal":600000,"annual_rate":3.6,"months":0,"persist":true}' \
  rejected 0 ignore

# ---------------------------------------------------------------------------
# 全局不变量：整轮矩阵只允许 valid_persist_true 增加一条
# ---------------------------------------------------------------------------
total_delta=$((prev - baseline))
printf '== global_run_count\n'
printf '    calc_runs before=%s after=%s delta=%s\n' "$baseline" "$prev" "$total_delta"
if [ "$total_delta" = "1" ]; then
  printf '    [PASS] 仅 persist=true 增加一条，其余步骤未改动条数\n'
else
  record_fail "global:run_count_delta(want 1 got $total_delta)"
fi

# ---------------------------------------------------------------------------
# 汇总
# ---------------------------------------------------------------------------
echo
if [ "${#FAILURES[@]}" -eq 0 ]; then
  printf 'SMOKE MATRIX PASS — 全部用例通过，calc_runs %s -> %s (+1)\n' "$baseline" "$prev"
  exit 0
else
  printf 'SMOKE MATRIX FAIL — %d 个失败用例:\n' "${#FAILURES[@]}" >&2
  for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f" >&2; done
  exit 1
fi
