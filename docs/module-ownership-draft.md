# AAN 模块归属草案 v3.1

> **状态**：草案（draft）。仅作为后续 `install/manifests/*.json` 的设计输入与 feature-based 组织形式的过渡产物。**不代表**目录将立即重组。
>
> **版本**：v3.1（2026-04-22）
> **v3 → v3.1 主要变动**：
>
> * 新增 `golang-testing` skill（归 golang）
> * 新增 `python-testing` skill（归 python）
> * §3 模块容量表更新：golang.skills 1→2（合计 9）、python.skills 1→2（合计 8）、skills 总 18→20、总合计 135→137
> * §4 Skills 归属表追加两行
>
> **v2 → v3 主要变动**：
>
> * 纳入 `hooks/hooks.json` 中 26 个 hook 的模块归属（新增 §8）
> * §3 模块容量表追加 `hooks` 列，合计 109 → 135
> * §11 配置层将 `hooks/hooks.json` 处置建议调整为"源文件保持完整、manifest 以 hook id 白名单方式选择性启用"
> * §12 迁移路径阶段 1 明确 manifest 需同时声明 skills/agents/commands/rules/hooks 五类
>
> **v1 → v2 主要变动**：
>
> * `go` → `golang`（对齐上游命名与 `golang-patterns` skill）
> * `frontend` → `web`（对齐上游命名，承载 performance / design-quality）
> * 新增 22 条 rule（golang / python / typescript / web）

## 1. 目的

aan 当前采用 **type-based** 目录（`skills/`、`agents/`、`commands/`、`rules/`、`hooks/`）。本草案用 **feature-based** 的视角重新盘点 aan 所有产出物，为以下两件事提供依据：

1. **按需安装清单**：后续在 `install/manifests/<module>.json` 声明每个模块包含的文件。
2. **依赖完整性校验**：把 CLAUDE.md 中的依赖边扫描（command ↔ agent ↔ skill ↔ rule）投射到模块边界上，跨模块引用必须显式。

本草案**不改变目录结构**，仅给出模块 → 文件的映射。

## 2. 模块设计

按"语言 / 主题"两条轴切分；`common` 是公共底座。

| 模块 | 定义 | 依赖方向 |
|------|------|---------|
| `common` | 跨语言、跨主题的横向能力 | 不依赖任何模块 |
| `rust` | Rust 语言全链路 | → common |
| `golang` | Go 语言全链路 | → common |
| `python` | Python 语言全链路 | → common |
| `typescript` | TypeScript / JavaScript | → common |
| `web` | Web 前端通用 + E2E + 性能 + 设计品质 | → common |
| `database` | 数据库设计、迁移、postgres | → common |
| `mcp` | MCP server 开发 | → common |
| `harness-ops` | harness 自身运维与优化 | → common |
| `prp` | Plan-Review-Process 流水线 | → common |
| `continuous-learning` | 持续学习与 instinct 系统 | → common |
| `ml` | PyTorch / 深度学习（暂 1 项） | → common, python |

> `ml` 暂只 1 项，迁移期可折进 `python`，达到 ≥3 项后再独立。

## 3. 模块容量

| 模块 | skills | agents | commands | rules | hooks | 合计 |
|------|:---:|:---:|:---:|:---:|:---:|:---:|
| common | 7 | 15 | 14 | 10 | 9 | 55 |
| web | 2 | 1 | 1 | 7 | 1 | 12 |
| harness-ops | 0 | 2 | 2 | 0 | 7 | 11 |
| continuous-learning | 2 | 0 | 6 | 0 | 3 | 11 |
| typescript | 0 | 1 | 0 | 5 | 4 | 10 |
| rust | 2 | 2 | 0 | 5 | 0 | 9 |
| golang | 2 | 2 | 0 | 5 | 0 | 9 |
| python | 2 | 1 | 0 | 5 | 0 | 8 |
| prp | 0 | 0 | 5 | 0 | 0 | 5 |
| mcp | 1 | 0 | 0 | 0 | 2 | 3 |
| database | 2 | 1 | 0 | 0 | 0 | 3 |
| ml | 0 | 1 | 0 | 0 | 0 | 1 |
| **合计** | **20** | **27** | **28** | **37** | **26** | **137** |

> `agents` 合计 27，其中 pytorch-build-resolver 同时计入 ml（或 python 暂入）；`commands` 合计 28 指归入各语言/主题模块的数量，剩余 1 项（`e2e`）归入 web。`hooks` 合计 26 按 hook id 唯一归属。

## 4. Skills 归属（18）

| Skill | 模块 |
|-------|------|
| coding-standards | common |
| documentation-lookup | common |
| security-review | common |
| tdd-workflow | common |
| verification-loop | common |
| api-design | common |
| backend-patterns | common |
| e2e-testing | web |
| frontend-patterns | web |
| rust-patterns | rust |
| rust-testing | rust |
| golang-patterns | golang |
| golang-testing | golang |
| python-patterns | python |
| python-testing | python |
| postgres-patterns | database |
| database-migrations | database |
| mcp-server-patterns | mcp |
| continuous-learning | continuous-learning |
| continuous-learning-v2 | continuous-learning |

## 5. Agents 归属（27）

| Agent | 模块 |
|-------|------|
| architect | common |
| code-architect | common |
| planner | common |
| code-reviewer | common |
| code-explorer | common |
| code-simplifier | common |
| refactor-cleaner | common |
| build-error-resolver | common |
| performance-optimizer | common |
| security-reviewer | common |
| silent-failure-hunter | common |
| type-design-analyzer | common |
| pr-test-analyzer | common |
| tdd-guide | common |
| doc-updater | common |
| docs-lookup | common |
| e2e-runner | web |
| rust-build-resolver | rust |
| rust-reviewer | rust |
| go-build-resolver | golang |
| go-reviewer | golang |
| python-reviewer | python |
| typescript-reviewer | typescript |
| database-reviewer | database |
| pytorch-build-resolver | ml（或暂入 python） |
| harness-optimizer | harness-ops |
| loop-operator | harness-ops |

## 6. Commands 归属（29）

| Command | 模块 |
|---------|------|
| plan | common |
| feature-dev | common |
| code-review | common |
| review-pr | common |
| refactor-clean | common |
| build-fix | common |
| quality-gate | common |
| verify | common |
| test-coverage | common |
| tdd | common |
| tdd-v2 | common |
| docs | common |
| update-codemaps | common |
| update-docs | common |
| e2e | web |
| harness-audit | harness-ops |
| skill-create | harness-ops |
| prp-plan | prp |
| prp-implement | prp |
| prp-pr | prp |
| prp-prd | prp |
| prp-commit | prp |
| learn | continuous-learning |
| evolve | continuous-learning |
| promote | continuous-learning |
| projects | continuous-learning |
| instinct-export | continuous-learning |
| instinct-import | continuous-learning |
| instinct-status | continuous-learning |

## 7. Rules 归属（37）

| 模块 | 文件 |
|------|------|
| common | agents / code-review / coding-style / development-workflow / git-workflow / hooks / patterns / performance / security / testing |
| rust | coding-style / hooks / patterns / security / testing |
| golang | coding-style / hooks / patterns / security / testing |
| python | coding-style / hooks / patterns / security / testing |
| typescript | coding-style / hooks / patterns / security / testing |
| web | coding-style / design-quality / hooks / patterns / performance / security / testing |

## 8. Hooks 归属（26）

上游 `everything-claude-code/hooks/hooks.json` 定义了 26 条 hook。归属口径：**按 hook 脚本的真实语义判定**，不按生命周期（PreToolUse/PostToolUse 不代表模块）。每条 hook id 只归一个模块，避免 manifest 出现重复键。

| Hook id | 生命周期 | 职责 | 模块 |
|--------|---------|------|---------|
| `pre:bash:dispatcher` | PreToolUse | Bash 预检分发（quality / tmux / push / GateGuard） | common |
| `pre:write:doc-file-warning` | PreToolUse | 非标准文档文件警告（warn-only） | common |
| `pre:edit-write:suggest-compact` | PreToolUse | 在逻辑节点建议手动 compact | harness-ops |
| `pre:observe:continuous-learning` | PreToolUse | 学习观察器（前置） | continuous-learning |
| `pre:governance-capture` | PreToolUse | 采集 governance 事件（secrets / policy） | common |
| `pre:config-protection` | PreToolUse | 阻止修改 linter/formatter 配置 | common |
| `pre:mcp-health-check` | PreToolUse | MCP 服务健康预检 | mcp |
| `pre:edit-write:gateguard-fact-force` | PreToolUse | 首次编辑前事实强制门 | common |
| `pre:compact` | PreCompact | 压缩前保存状态 | harness-ops |
| `session:start` | SessionStart | 会话启动：加载上下文 + 探测包管理器 | common |
| `post:bash:dispatcher` | PostToolUse | Bash 后处理分发（logging / PR / 构建通知） | common |
| `post:quality-gate` | PostToolUse | 编辑后质量门 | common |
| `post:edit:design-quality-check` | PostToolUse | 前端"像模板"漂移告警 | web |
| `post:edit:accumulator` | PostToolUse | 累积 JS/TS 编辑路径供批量校验 | typescript |
| `post:edit:console-warn` | PostToolUse | `console.log` 告警 | typescript |
| `post:governance-capture` | PostToolUse | 后置 governance 事件采集 | common |
| `post:session-activity-tracker` | PostToolUse | 每会话工具调用 / 活动度量 | harness-ops |
| `post:observe:continuous-learning` | PostToolUse | 学习观察器（后置） | continuous-learning |
| `post:mcp-health-check` | PostToolUseFailure | MCP 失败追踪 / 重连 | mcp |
| `stop:format-typecheck` | Stop | 批量 Biome/Prettier + `tsc` | typescript |
| `stop:check-console-log` | Stop | `console.log` 终检 | typescript |
| `stop:session-end` | Stop | 持久化会话状态 | harness-ops |
| `stop:evaluate-session` | Stop | 评估会话可抽取模式 | continuous-learning |
| `stop:cost-tracker` | Stop | token/费用度量 | harness-ops |
| `stop:desktop-notify` | Stop | 桌面通知 | harness-ops |
| `session:end:marker` | SessionEnd | 会话结束生命周期标记 | harness-ops |

### 8.1 按模块汇总

| 模块 | hooks 数 | 清单 |
|------|:---:|------|
| common | 9 | pre:bash:dispatcher / pre:write:doc-file-warning / pre:governance-capture / pre:config-protection / pre:edit-write:gateguard-fact-force / session:start / post:bash:dispatcher / post:quality-gate / post:governance-capture |
| harness-ops | 7 | pre:edit-write:suggest-compact / pre:compact / post:session-activity-tracker / stop:session-end / stop:cost-tracker / stop:desktop-notify / session:end:marker |
| typescript | 4 | post:edit:accumulator / post:edit:console-warn / stop:format-typecheck / stop:check-console-log |
| continuous-learning | 3 | pre:observe:continuous-learning / post:observe:continuous-learning / stop:evaluate-session |
| mcp | 2 | pre:mcp-health-check / post:mcp-health-check |
| web | 1 | post:edit:design-quality-check |

> rust / golang / python / database / prp / ml 当前无 hook。

### 8.2 归属判断依据

* **common（9）**：语言无关、贯穿所有会话的基线——bash 预/后分发、governance 捕获、GateGuard、config 保护、质量门、doc-warning、`session:start`（含通用包管理器探测）都属于"任何模块组合都应存在"的底座。
* **harness-ops（7）**：harness 自身生命周期 / 观测 / UX——compact 建议、PreCompact 快照、session 活动埋点、cost/token 追踪、桌面通知、session 结束标记。
* **typescript（4）**：明确作用于 JS/TS 文件的——edit accumulator、console-warn、Biome/Prettier + tsc 批量格式+类型检查、stop 阶段 console.log 扫描。
* **continuous-learning（3）**：三个 observe/evaluate-session 钩子由 `continuous-learning-v2/hooks/observe.sh` 或 `evaluate-session.js` 驱动，必须原子绑定，不允许单独选装。
* **mcp（2）**：健康检查前/后置对，共享健康注册表，manifest 需作为同一 entry 声明。
* **web（1）**：`design-quality-check` 仅对前端文件生效。

## 9. 健康度观察

* **common 占比**：纳入 hooks 后 55/135 ≈ 41%（v2 时未计 hook 为 46/109 ≈ 42%），整体分布保持均衡，未因 hook 纳入而失衡。
* **typescript 模块跃升至独立粒度**：v2 时仅 6 条（rule 5 + agent 1），纳入 4 条 hook 后升至 10 条，与 rust/golang 量级相当。
* **harness-ops 从最弱模块变为第三大模块**：v2 时仅 4 条，纳入 7 条 hook 后升至 11 条，印证其 "harness 自身运维 / 观测" 的定位实质承载。
* **最弱的两个模块仍是 mcp（3）与 ml（1）**：mcp 因主题独特且有健康检查对 hook 加入，保持独立；ml 暂折进 python。
* **0-hook 模块**：rust / golang / python / database / prp。其中语言类 0-hook 是符合预期的——hook 是跨语言的 harness 层行为，语言模块主要靠 skill/agent/rule 表达。

## 10. 歧义条目（迁移前需拍板）

| 条目 | 候选 | 倾向 |
|------|------|------|
| `e2e-testing` / `e2e-runner` / `/e2e` | common ↔ web | web |
| `api-design`、`backend-patterns` | common ↔ 新建 backend | common（不到 3 项不开新模块） |
| `pytorch-build-resolver` | python ↔ 新建 ml | 暂入 python，标注 ml 候选 |
| `skill-create` | harness-ops ↔ continuous-learning | harness-ops |
| `code-architect` vs `architect` | 都在 common，是否合并 | 第二步合并 |
| `tdd` 与 `tdd-v2` shim | 都在 common | 第二步删除 tdd-v2 shim |
| `learn` shim | continuous-learning | OK |
| `session:start` | common ↔ harness-ops | common（所有模块组合前置，迁到 harness-ops 会导致"只装 common"无 session-start） |
| `pre:edit-write:gateguard-fact-force` | common ↔ harness-ops | common（对应 `gateguard` 跨语言安全底座） |
| `stop:evaluate-session` | continuous-learning ↔ harness-ops | continuous-learning（挂在 Stop 阶段但服务于 instinct 抽取） |
| `stop:desktop-notify` | harness-ops ↔ common | harness-ops（桌面通知非基线，属 UX） |
| `post:bash:dispatcher` 内部的 PR/构建通知 | common ↔ harness-ops | common（整体归 common；若将来拆独立子 hook，再考虑下沉 harness-ops/prp） |

## 11. 配置层

| 路径 | 处置建议 |
|------|---------|
| `hooks/hooks.json` | **源文件保持完整、单一真源**。按 manifest 声明的 hook id 白名单，在安装时过滤装配（不拆分成 `<module>/hooks/*.json`）。每条 hook 条目必须包含稳定 `id` 字段，且 id 唯一、归属唯一；CI 校验 manifest 的 id 与 `hooks.json` 的 id 集合一致。 |
| `mcp/mcp-servers.json` | 同 `hooks.json` 思路：源文件保持完整，manifest 可声明每个模块所需 MCP server 名；暂留根。 |
| `install/claude/`、`install/cursor/` | 升级为 "读 manifest → 汇流复制 + id 白名单过滤"。 |
| `scripts/hooks` | 与 hooks 配合，暂留根。按 hook id 维度而非目录维度做 manifest 映射。 |

## 12. 迁移路径（分两步）

1. **形式化模块清单（阶段 1，零破坏）**
   * 不动目录结构，新增 `install/manifests/<module>.json` 显式列出每个 feature 的文件清单。
   * manifest 的 schema 固定为 `{skills, agents, commands, rules, hooks}` 五类（v2 原为四类，v3 纳入 hooks）。
   * `hooks` 字段是 id 白名单（字符串数组），不嵌入 hook 定义本身。
   * 安装脚本支持 `--include <module>[,<module>...]`，按依赖闭包合并五类清单，并对 `hooks.json` 按 id 过滤写入目标环境。
   * 依赖检查脚本基于 manifest 扫描跨模块引用 + hook id 归属完整性。

2. **目录迁移到 feature-based（阶段 2，清单稳定 1-2 个月后）**
   * 批量 `git mv` skills/agents/commands/rules 到 `<module>/...`。
   * `hooks.json` **不拆分**，保持单文件；仅通过 manifest 表达归属。
   * 脚本批量更新反向引用。
   * 安装脚本由"读 manifest"回落为"读目录树 + hook id 白名单"。

## 13. 下一步（离开本草案后）

1. 对本草案作评审，锁定 §10 的歧义条目（含新增的 5 条 hook 相关）。
2. 起草 `install/manifests/` 的 JSON schema（含 `hooks: string[]` 字段）与首个模块样板。
3. 给 `hooks/hooks.json` 每条条目确保 `id` 字段完整、稳定、唯一，并加入 CI 校验。
4. 把现有 `install/claude/install.sh` 的"目录自动发现"逻辑升级为"支持 manifest 过滤 + hook id 白名单"。
