# 15-mortgage（房贷月供）

Mortgage — 等额本息月供与逐期本金利息拆分

## 启动

```bash
docker compose up --build
```

| 入口 | 地址 |
| --- | --- |
| 前端 | http://localhost:4400 |
| API | http://localhost:9400 |

## 冒烟矩阵（测算接口）

起服后，对健康检查与 `POST /api/schedule` 跑一组冒烟用例，脚本为
`scripts/smoke-matrix.sh`。

### 调用顺序

```bash
# 1) 起服（首次或代码变更后加 --build）
docker compose up --build -d

# 2) 确认后端就绪（脚本内部也会先做这一步，未就绪会直接失败退出）
curl -fsS http://localhost:9400/api/health

# 3) 在仓库根目录执行冒烟矩阵
./scripts/smoke-matrix.sh
```

脚本必须在后端已启动时运行；**后端未启动 / 健康检查不可达会立即非零退出**。

### 覆盖用例

| 用例名 | 请求 | 期望 |
| --- | --- | --- |
| `valid_persist_false` | 合法入参，`persist=false` | 200，回包带月供，`run_id=null`，`calc_runs` 条数不变 |
| `valid_persist_true` | 合法入参，`persist=true` | 200，回包带月供，`run_id` 非空，`calc_runs` 条数 **+1** |
| `invalid_principal_nonpositive` | 本金 `<=0` | 非成功状态（422），`calc_runs` 条数不变 |
| `invalid_months_illegal` | 期数非法（`months<=0`） | 非成功状态（422），`calc_runs` 条数不变 |

### 计数与退出码

- 脚本在矩阵前后各读取一次**默认库**的 `calc_runs` 计数（compose 下即后端
  容器内 `/data/app.db`）。整轮矩阵只允许 `valid_persist_true` 增加一条，
  健康检查、`persist=false` 与两类非法请求都不得改动条数。
- 月供只断言“存在且为正数”，**不硬编码任何种子月供数字**，因此结果与种子
  数据中的金额无关，不靠改种子数字凑绿。
- 每跑一次脚本，`calc_runs` 会因 `persist=true` 用例净增一条（可重复执行）。
- 任一断言失败：收集全部失败点并**点名失败用例名**，结尾以非零码退出；
  全部通过退出 `0`。

可选环境变量：`SMOKE_BASE_URL`（默认 `http://localhost:9400`）、
`SMOKE_DB_PATH`（直接读宿主机 sqlite 文件，非容器化本地起服时用）、
`SMOKE_COUNT_CMD`（完全自定义计数命令，stdout 须为条数）。

## 主链

贷额期限利率 → 等额本息还款表 → 利息合计

## 技术栈

Python 3.12 + FastAPI + SQLite；Vue 3 + Vite + Nginx。
