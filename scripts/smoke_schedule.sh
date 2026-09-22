#!/usr/bin/env bash
# schedule 测算接口冒烟矩阵
#
# 前置：docker compose 已起服（docker compose up --build -d），后端健康检查可通。
#
# 矩阵用例：
#   1. health                 健康检查 GET /api/health
#   2. legal-persist-false    合法请求 persist=false：成功、run_id=null、calc_runs 条数不变
#   3. legal-persist-true     合法请求 persist=true ：成功、回包带月供、条数恰好 +1
#   4. bad-principal          本金非正 principal<=0：非成功状态、条数不变
#   5. bad-months             期数非法 months<=0：非成功状态、条数不变
#
# 矩阵前后各读一次默认库 calc_runs 计数：全程除 legal-persist-true 外不得有任何 +1。
# 任一条失败：点名失败用例并以非零码退出；后端未启动直接失败。
#
# 可用环境变量：
#   BASE_URL   后端地址（默认 http://localhost:9400）
#   COMPOSE_CMD compose 命令（默认自动探测 docker compose / docker-compose）
#   SERVICE    后端服务名（默认 backend）
set -uo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(dirname "$SCRIPT_DIR")
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"

BASE_URL="${BASE_URL:-http://localhost:9400}"
SERVICE="${SERVICE:-backend}"
if [ -z "${COMPOSE_CMD:-}" ]; then
  if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
  else
    COMPOSE=(docker compose)
  fi
else
  # COMPOSE_CMD 可由环境覆盖，按空白拆分为单词
  read -r -a COMPOSE <<< "$COMPOSE_CMD"
fi

FAILS=()
PASS_COUNT=0

die() {
  echo "FATAL: $*" >&2
  exit 2
}

record_fail() {
  local name=$1 reason=$2
  local seen=0 f
  if [ "${#FAILS[@]}" -gt 0 ]; then
    for f in "${FAILS[@]}"; do [ "$f" = "$name" ] && { seen=1; break; }; done
  fi
  [ "$seen" -eq 0 ] && FAILS+=("$name")
  echo "  FAIL: $name — $reason" >&2
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "  PASS: $1"
}

is_uint() { [[ $1 =~ ^[0-9]+$ ]]; }

# 在后端容器内用应用自身的默认库配置读取 calc_runs 条数
count_runs() {
  "${COMPOSE[@]}" -f "$COMPOSE_FILE" exec -T "$SERVICE" python -c \
    'import sqlite3; from app.config import DATA_DIR, DB_FILENAME; c=sqlite3.connect(str(DATA_DIR/DB_FILENAME)); print(c.execute("SELECT COUNT(*) FROM calc_runs").fetchone()[0])'
}

must_count() {
  local where=$1 n
  n=$(count_runs) || die "读取默认库 calc_runs 计数失败（$where），请确认后端容器已启动"
  is_uint "$n" || die "calc_runs 计数异常（$where）：$n"
  printf '%s' "$n"
}

# post_schedule <payload>；结果写入全局 HTTP / BODY
post_schedule() {
  local payload=$1 out
  out=$(curl -sS -m 10 -w $'\n%{http_code}' \
    -X POST "$BASE_URL/api/schedule" \
    -H 'Content-Type: application/json' \
    -d "$payload" 2>/dev/null)
  if [ $? -ne 0 ]; then
    HTTP="000"; BODY=""
  else
    HTTP=${out##*$'\n'}
    BODY=${out%$'\n'*}
  fi
}

# 从响应 JSON 取 monthly_payment（FastAPI 紧凑 JSON），输出数值
extract_monthly_payment() {
  printf '%s' "$1" | sed -n 's/.*"monthly_payment"[[:space:]]*:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' | head -1
}

# run_case <名称> <payload> <期望:ok|error> <是否落库:0|1>
run_case() {
  local name=$1 payload=$2 expect=$3 insert=$4
  local before after delta want_delta http_ok mp
  echo "[$name] $payload"

  before=$(must_count "$name 前置") || return 1
  post_schedule "$payload"
  after=$(must_count "$name 后置") || return 1
  delta=$((after - before))
  want_delta=$insert

  local ok=1

  if [ "$HTTP" = "000" ]; then
    record_fail "$name" "请求未到达后端（连接失败）"; return 1
  fi
  http_ok=0
  if [ "$expect" = ok ] && [ "$HTTP" -ge 200 ] && [ "$HTTP" -lt 300 ]; then http_ok=1; fi
  if [ "$expect" = error ] && [ "$HTTP" -ge 400 ]; then http_ok=1; fi
  if [ "$http_ok" -ne 1 ]; then
    record_fail "$name" "状态码不符：期望 $([ "$expect" = ok ] && echo 2xx || echo '>=400')，实际 $HTTP"
    ok=0
  fi

  if [ "$expect" = ok ]; then
    if ! printf '%s' "$BODY" | grep -Eq '"run_id"[[:space:]]*:'; then
      record_fail "$name" "回包缺少 run_id 字段"; ok=0
    fi
    if [ "$insert" -eq 0 ]; then
      if ! printf '%s' "$BODY" | grep -Eq '"run_id"[[:space:]]*:[[:space:]]*null'; then
        record_fail "$name" "persist=false 应回 run_id=null，实际：$BODY"; ok=0
      fi
    else
      if ! printf '%s' "$BODY" | grep -Eq '"run_id"[[:space:]]*:[[:space:]]*[0-9]+'; then
        record_fail "$name" "persist=true 应回非空数字 run_id，实际：$BODY"; ok=0
      fi
    fi
    mp=$(extract_monthly_payment "$BODY")
    if [ -z "$mp" ] || ! awk -v v="$mp" 'BEGIN{exit !(v+0>0)}'; then
      record_fail "$name" "回包未带正数月供 monthly_payment，实际：$BODY"; ok=0
    fi
  fi

  if [ "$delta" -ne "$want_delta" ]; then
    record_fail "$name" "calc_runs 条数变化 $before→$after（Δ=$delta），期望 Δ=$want_delta"
    ok=0
  fi

  if [ "$ok" -eq 1 ]; then
    pass "$name（HTTP $HTTP，calc_runs $before→$after，月供 ${mp:-n/a}）"
  fi
}

command -v curl >/dev/null 2>&1 || die "缺少 curl"
[ -f "$COMPOSE_FILE" ] || die "找不到 $COMPOSE_FILE（请在仓库内运行）"

# 1) 健康检查：后端未启动必须失败，不做等待重试
echo "[health] GET $BASE_URL/api/health"
HEALTH=$(curl -sS -m 5 -w $'\n%{http_code}' "$BASE_URL/api/health" 2>&1) || \
  die "后端未启动或不可达：$BASE_URL/api/health（curl 失败）"
HEALTH_HTTP=${HEALTH##*$'\n'}
HEALTH_BODY=${HEALTH%$'\n'*}
if [ "$HEALTH_HTTP" -ne 200 ] || ! printf '%s' "$HEALTH_BODY" | grep -Eq '"ok"[[:space:]]*:[[:space:]]*true'; then
  die "健康检查未通过：HTTP $HEALTH_HTTP，响应：$HEALTH_BODY"
fi
pass "health（HTTP 200，$HEALTH_BODY）"

# 2) 矩阵前基线计数
COUNT_BEFORE=$(must_count "矩阵开始") || die "无法取得矩阵前计数"
echo "矩阵前 calc_runs 条数：$COUNT_BEFORE"

# 3) 四类用例（月供只断言为正数，不与任何种子数字挂钩）
run_case legal-persist-false \
  '{"principal":500000,"annual_rate":3.9,"months":240,"persist":false}' ok 0

run_case legal-persist-true \
  '{"principal":750000,"annual_rate":3.2,"months":300,"persist":true}' ok 1

run_case bad-principal \
  '{"principal":0,"annual_rate":3.5,"months":360,"persist":true}' error 0

run_case bad-months \
  '{"principal":500000,"annual_rate":3.5,"months":0,"persist":true}' error 0

# 4) 矩阵后总计数：全矩阵只允许 legal-persist-true 加一条
COUNT_AFTER=$(must_count "矩阵结束") || die "无法取得矩阵后计数"
echo "矩阵后 calc_runs 条数：$COUNT_AFTER"
EXPECTED_AFTER=$((COUNT_BEFORE + 1))
if [ "$COUNT_AFTER" -ne "$EXPECTED_AFTER" ]; then
  record_fail "matrix-count" "矩阵总条数 $COUNT_BEFORE→$COUNT_AFTER，期望 $EXPECTED_AFTER（仅 persist=true 允许 +1）"
else
  pass "matrix-count（全程仅 legal-persist-true 增加一条）"
fi

echo "----------------------------------------"
if [ "${#FAILS[@]}" -ne 0 ]; then
  echo "冒烟矩阵失败，失败用例 ${#FAILS[@]} 个：" >&2
  for n in "${FAILS[@]}"; do echo "  - $n" >&2; done
  exit 1
fi
echo "全部用例通过（$PASS_COUNT 项），calc_runs $COUNT_BEFORE→$COUNT_AFTER"
