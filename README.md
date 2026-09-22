# 15-mortgage（房贷月供）

Mortgage — 等额本息月供与逐期本金利息拆分

## 启动

```bash
docker compose up --build -d
```

| 入口 | 地址 |
| --- | --- |
| 前端 | http://localhost:4400 |
| API | http://localhost:9400 |

## 冒烟矩阵（schedule 测算接口）

调用顺序：先起服，待健康检查可通，再跑冒烟脚本。脚本对默认库（`/data/app.db`）的 `calc_runs`
做矩阵前后计数对比，只发 HTTP 请求、通过 `docker compose exec` 读计数，不直接改库。

```bash
# 1. 起服（detached）
docker compose up --build -d

# 2. 跑冒烟矩阵（后端未启动会直接失败退出）
./scripts/smoke_schedule.sh
```

矩阵覆盖：

| 用例 | 请求 | 断言 |
| --- | --- | --- |
| health | `GET /api/health` | HTTP 200 且 `ok:true` |
| legal-persist-false | 合法入参，`persist:false` | 成功、`run_id:null`、`calc_runs` 条数不变 |
| legal-persist-true | 合法入参，`persist:true` | 成功、回包带正数月供、条数恰好 +1 |
| bad-principal | `principal:0` | 非成功状态（4xx）、条数不变 |
| bad-months | `months:0` | 非成功状态（4xx）、条数不变 |

全程除 `legal-persist-true` 允许条数加一外，其它任何步骤都不得改动 `calc_runs`。
任一条失败，脚本点名失败用例并以非零码退出。可用 `BASE_URL` 覆盖后端地址（默认 `http://localhost:9400`）。

## 主链

贷额期限利率 → 等额本息还款表 → 利息合计

## 技术栈

Python 3.12 + FastAPI + SQLite；Vue 3 + Vite + Nginx。
