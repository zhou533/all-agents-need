# AAN 模块归属草案 v2

> **状态**：草案（draft）。仅作为后续 `install/manifests/*.json` 的设计输入与 feature-based 组织形式的过渡产物。**不代表**目录将立即重组。
>
> **版本**：v2（2026-04-21）
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

| 模块 | skills | agents | commands | rules | 合计 |
|------|:---:|:---:|:---:|:---:|:---:|
| common | 7 | 15 | 14 | 10 | 46 |
| web | 2 | 1 | 1 | 7 | 11 |
| rust | 2 | 2 | 0 | 5 | 9 |
| golang | 1 | 2 | 0 | 5 | 8 |
| continuous-learning | 2 | 0 | 6 | 0 | 8 |
| python | 1 | 1 | 0 | 5 | 7 |
| typescript | 0 | 1 | 0 | 5 | 6 |
| prp | 0 | 0 | 5 | 0 | 5 |
| harness-ops | 0 | 2 | 2 | 0 | 4 |
| database | 2 | 1 | 0 | 0 | 3 |
| mcp | 1 | 0 | 0 | 0 | 1 |
| ml | 0 | 1 | 0 | 0 | 1 |
| **合计** | **18** | **27** | **28** | **37** | **109** |

> `agents` 合计 27，其中 pytorch-build-resolver 同时计入 ml（或 python 暂入）；`commands` 合计 28 指归入各语言/主题模块的数量，剩余 1 项（`e2e`）归入 web。

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
| python-patterns | python |
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

## 8. 健康度观察

* **common 占比 42%**（v1 时为 52%）——新增语言 rule 稀释了 common 的权重，分布更均匀。
* **语言模块已达独立粒度**：golang 8 / python 7 / typescript 6 / web 11，均越过"足够独立打包"的阈值（≥5）。
* **最弱的两个模块**：mcp（1）与 ml（1）。mcp 因主题独特保持独立；ml 暂折进 python。

## 9. 歧义条目（迁移前需拍板）

| 条目 | 候选 | 倾向 |
|------|------|------|
| `e2e-testing` / `e2e-runner` / `/e2e` | common ↔ web | web |
| `api-design`、`backend-patterns` | common ↔ 新建 backend | common（不到 3 项不开新模块） |
| `pytorch-build-resolver` | python ↔ 新建 ml | 暂入 python，标注 ml 候选 |
| `skill-create` | harness-ops ↔ continuous-learning | harness-ops |
| `code-architect` vs `architect` | 都在 common，是否合并 | 第二步合并 |
| `tdd` 与 `tdd-v2` shim | 都在 common | 第二步删除 tdd-v2 shim |
| `learn` shim | continuous-learning | OK |

## 10. 配置层（不属于 manifest）

| 路径 | 处置建议 |
|------|---------|
| `hooks/hooks.json` | 基线 hooks，暂留根；未来可拆为 `<module>/hooks/*.json` |
| `mcp/mcp-servers.json` | 基线 MCP 配置，暂留根 |
| `install/claude/`、`install/cursor/` | 升级为 "读 manifest → 汇流复制" |
| `scripts/hooks` | 与 hooks 配合，暂留根 |

## 11. 迁移路径（分两步）

1. **形式化模块清单（阶段 1，零破坏）**
   * 不动目录结构，只新增 `install/manifests/<module>.json`（或等价 YAML）显式列出每个 feature 的文件清单。
   * 安装脚本支持 `--include <module>[,<module>...]` 按需安装。
   * 依赖检查脚本基于 manifest 扫描跨模块引用。

2. **目录迁移到 feature-based（阶段 2，清单稳定 1-2 个月后）**
   * 批量 `git mv` 到 `<module>/skills/...`、`<module>/agents/...` 等。
   * 脚本批量更新反向引用。
   * 安装脚本由"读 manifest" 回落为"读目录树"。

## 12. 下一步（离开本草案后）

1. 对本草案作评审，锁定第 9 节的歧义条目。
2. 起草 `install/manifests/` 的 JSON schema 与首个模块样板（推荐用 `rust` 或 `golang` 做首个试点）。
3. 把现有 `install/claude/install.sh` 的"目录自动发现"逻辑升级为"支持 manifest 过滤"。
