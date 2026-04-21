# Harness Audit 命令

对仓库执行确定性的 harness 审计，并返回按优先级排列的评分卡。

## 用法

`/harness-audit [scope] [--format text|json] [--root path]`

- `scope`（可选）：`repo`（默认）、`hooks`、`skills`、`commands`、`agents`
- `--format`：输出风格（`text` 默认，`json` 用于自动化）
- `--root`：审计指定路径，而非当前工作目录

## 确定性引擎

始终运行：

```bash
node scripts/harness-audit.js <scope> --format <text|json> [--root <path>]
```

该脚本是评分与检查项的单一事实来源。不要自行发明额外维度或临时加分项。

评分规则版本：`2026-03-30`。

脚本计算 7 个固定类别（各归一化到 `0-10`）：

1. Tool Coverage
2. Context Efficiency
3. Quality Gates
4. Memory Persistence
5. Eval Coverage
6. Security Guardrails
7. Cost Efficiency

分数均由明确的文件/规则检查推导得出，对同一 commit 可重现。
脚本默认审计当前工作目录，会自动识别目标是 AAN 仓库本身还是使用 AAN 的下游项目。

## 输出约定

返回：

1. `overall_score` / `max_score`（`repo` 模式下 max 为 70；范围更窄的审计最大值更小）
2. 分类分数与具体发现
3. 失败的检查项，附精确的文件路径
4. 来自确定性输出的前 3 条动作（`top_actions`）
5. 建议后续调用的 AAN 技能

## 清单

- 直接采用脚本输出；不要手动再打分。
- 若请求 `--format json`，原样返回脚本的 JSON。
- 若请求文本格式，汇总失败项和 top actions。
- 展示来自 `checks[]` 与 `top_actions[]` 的精确文件路径。

## 示例结果

```text
Harness Audit (repo): 66/70
- Tool Coverage: 10/10 (10/10 pts)
- Context Efficiency: 9/10 (9/10 pts)
- Quality Gates: 10/10 (10/10 pts)

Top 3 Actions:
1) [Security Guardrails] Add prompt/tool preflight security guards in hooks/hooks.json. (hooks/hooks.json)
2) [Tool Coverage] Sync commands/harness-audit.md and .opencode/commands/harness-audit.md. (.opencode/commands/harness-audit.md)
3) [Eval Coverage] Increase automated test coverage across scripts/hooks/lib. (tests/)
```

## 参数

$ARGUMENTS：
- `repo|hooks|skills|commands|agents`（可选，范围）
- `--format text|json`（可选，输出格式）
