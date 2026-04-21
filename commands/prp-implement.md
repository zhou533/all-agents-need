---
description: 在严格的验证循环中执行实施计划
argument-hint: <path/to/plan.md>
---

> 改编自 Wirasm 的 PRPs-agentic-eng。属于 PRP 工作流系列的一部分。

# PRP Implement

按步骤执行 plan 文件，每一步改动都立即验证 —— 绝不累积损坏状态。

**核心理念**：验证循环能尽早捕获错误。每次改动后运行检查，立刻修复发现的问题。

**黄金法则**：若某项验证失败，先修复再继续。绝不让损坏状态堆积。

---

## 阶段 0 —— DETECT

### 检测包管理器

| 存在的文件 | 包管理器 | 运行器 |
|---|---|---|
| `bun.lockb` | bun | `bun run` |
| `pnpm-lock.yaml` | pnpm | `pnpm run` |
| `yarn.lock` | yarn | `yarn` |
| `package-lock.json` | npm | `npm run` |
| `pyproject.toml` 或 `requirements.txt` | uv / pip | `uv run` 或 `python -m` |
| `Cargo.toml` | cargo | `cargo` |
| `go.mod` | go | `go` |

### 校验脚本

检查 `package.json`（或等价文件）里可用的脚本：

```bash
# Node.js 项目
cat package.json | grep -A 20 '"scripts"'
```

记录以下类别的可用命令：type-check、lint、test、build。

---

## 阶段 1 —— LOAD

读取 plan 文件：

```bash
cat "$ARGUMENTS"
```

从 plan 中抽取以下字段：
- **Summary** —— 要构建什么
- **Patterns to Mirror** —— 要遵循的代码约定
- **Files to Change** —— 要新建或修改的文件
- **Step-by-Step Tasks** —— 实施序列
- **Validation Commands** —— 如何验证正确性
- **Acceptance Criteria** —— 完成的定义

若文件不存在或不是有效的 plan：
```
Error: Plan file not found or invalid.
Run /prp-plan <feature-description> to create a plan first.
```

**CHECKPOINT**：plan 已加载，所有段落已识别，任务已抽取。

---

## 阶段 2 —— PREPARE

### Git 状态

```bash
git branch --show-current
git status --porcelain
```

### 分支决策

| 当前状态 | 动作 |
|---|---|
| 已在 feature 分支 | 使用当前分支 |
| 在 main，工作树干净 | 创建 feature 分支：`git checkout -b feat/{plan-name}` |
| 在 main，工作树脏 | **停止** —— 请用户先 stash 或 commit |
| 在该 feature 的 git worktree 中 | 使用该 worktree |

### 同步远端

```bash
git pull --rebase origin $(git branch --show-current) 2>/dev/null || true
```

**CHECKPOINT**：分支正确，工作树就绪，远端已同步。

---

## 阶段 3 —— EXECUTE

按顺序处理 plan 里的每个任务。

### 单任务循环

对 **Step-by-Step Tasks** 中的每个任务：

1. **读取 MIRROR 引用** —— 打开任务 MIRROR 字段引用的模式文件。理解约定后再写代码。

2. **实现** —— 严格按照模式编写代码。留意 GOTCHA 警告。使用指定的 IMPORTS。

3. **立即验证** —— 每次修改文件后：
   ```bash
   # 运行类型检查（按项目调整命令）
   [来自阶段 0 的 type-check 命令]
   ```
   若 type-check 失败 → 修复后再处理下一个文件。

4. **跟踪进度** —— 日志：`[done] Task N: [task name] — complete`

### 处理偏差

若实现需要偏离 plan：
- 记录 **WHAT** 变了
- 记录 **WHY** 变了
- 继续修正后的做法
- 这些偏差将在报告中汇总

**CHECKPOINT**：所有任务已执行，偏差已记录。

---

## 阶段 4 —— VALIDATE

运行 plan 里的全部验证层级。每个层级的问题先修复，再进入下一层。

### Level 1：静态分析

```bash
# 类型检查 —— 要求零错误
[项目的 type-check 命令]

# Lint —— 尽量自动修复
[项目的 lint 命令]
[项目的 lint-fix 命令]
```

若自动修复后仍有 lint 错误，手工修复。

### Level 2：单元测试

为每个新函数编写测试（按 plan 的 Testing Strategy）。

```bash
[针对受影响区域的项目测试命令]
```

- 每个函数至少一个测试
- 覆盖 plan 中列出的边界情况
- 若测试失败 → 修复实现（而非测试，除非测试本身错了）

### Level 3：构建检查

```bash
[项目的 build 命令]
```

必须零错误构建成功。

### Level 4：集成测试（若适用）

```bash
# 启动服务器、运行测试、停止服务器
[项目的 dev server 命令] &
SERVER_PID=$!

# 等待服务器就绪（按需调整端口）
SERVER_READY=0
for i in $(seq 1 30); do
  if curl -sf http://localhost:PORT/health >/dev/null 2>&1; then
    SERVER_READY=1
    break
  fi
  sleep 1
done

if [ "$SERVER_READY" -ne 1 ]; then
  kill "$SERVER_PID" 2>/dev/null || true
  echo "ERROR: Server failed to start within 30s" >&2
  exit 1
fi

[集成测试命令]
TEST_EXIT=$?

kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true

exit "$TEST_EXIT"
```

### Level 5：边界情况测试

按 plan 的 Testing Strategy 清单走一遍边界情况。

**CHECKPOINT**：5 个层级全部通过，零错误。

---

## 阶段 5 —— REPORT

### 创建实施报告

```bash
mkdir -p .claude/PRPs/reports
```

将报告写入 `.claude/PRPs/reports/{plan-name}-report.md`：

```markdown
# Implementation Report: [Feature Name]

## Summary
[实现了什么]

## Assessment vs Reality

| Metric | Predicted (Plan) | Actual |
|---|---|---|
| Complexity | [来自 plan] | [实际] |
| Confidence | [来自 plan] | [实际] |
| Files Changed | [来自 plan] | [实际数量] |

## Tasks Completed

| # | Task | Status | Notes |
|---|---|---|---|
| 1 | [task name] | [done] Complete | |
| 2 | [task name] | [done] Complete | Deviated — [原因] |

## Validation Results

| Level | Status | Notes |
|---|---|---|
| Static Analysis | [done] Pass | |
| Unit Tests | [done] Pass | 新写 N 个测试 |
| Build | [done] Pass | |
| Integration | [done] Pass | 或 N/A |
| Edge Cases | [done] Pass | |

## Files Changed

| File | Action | Lines |
|---|---|---|
| `path/to/file` | CREATED | +N |
| `path/to/file` | UPDATED | +N / -M |

## Deviations from Plan
[列出偏差，含 WHAT 与 WHY，或写 "None"]

## Issues Encountered
[遇到的问题及处理方式，或写 "None"]

## Tests Written

| Test File | Tests | Coverage |
|---|---|---|
| `path/to/test` | N tests | [覆盖范围] |

## Next Steps
- [ ] 通过 `/code-review` 审查代码
- [ ] 通过 `/prp-pr` 创建 PR
```

### 更新 PRD（若适用）

若本次实施对应 PRD 的某个 phase：
1. 将该 phase 状态由 `in-progress` 置为 `complete`
2. 在 phase 引用处加入报告路径

### 归档 plan

```bash
mkdir -p .claude/PRPs/plans/completed
mv "$ARGUMENTS" .claude/PRPs/plans/completed/
```

**CHECKPOINT**：报告已创建，PRD 已更新，plan 已归档。

---

## 阶段 6 —— OUTPUT

向用户汇报：

```
## Implementation Complete

- **Plan**: [plan 文件路径] → 已归档到 completed/
- **Branch**: [当前分支名]
- **Status**: [done] All tasks complete

### Validation Summary

| Check | Status |
|---|---|
| Type Check | [done] |
| Lint | [done] |
| Tests | [done] (N 个新写) |
| Build | [done] |
| Integration | [done] 或 N/A |

### Files Changed
- [N] 个文件新建，[M] 个文件修改

### Deviations
[摘要，或 "None — implemented exactly as planned"]

### Artifacts
- Report: `.claude/PRPs/reports/{name}-report.md`
- Archived Plan: `.claude/PRPs/plans/completed/{name}.plan.md`

### PRD Progress（若适用）
| Phase | Status |
|---|---|
| Phase 1 | [done] Complete |
| Phase 2 | [next] |
| ... | ... |

> 下一步：运行 `/prp-pr` 创建 PR，或先运行 `/code-review` 审查改动。
```

---

## 故障处理

### Type Check 失败
1. 仔细读错误信息
2. 在源文件中修复类型错误
3. 重新运行 type-check
4. 通过后再继续

### 测试失败
1. 判断 bug 在实现还是测试里
2. 修复根本原因（通常是实现）
3. 重新运行测试
4. 全绿后再继续

### Lint 失败
1. 先自动修复
2. 剩余错误手动修复
3. 重新运行 lint
4. 通过后再继续

### Build 失败
1. 通常是类型或 import 问题 —— 看错误信息
2. 修复问题文件
3. 重新构建
4. 通过后再继续

### 集成测试失败
1. 确认服务器已正确启动
2. 确认 endpoint/route 存在
3. 确认请求格式与期望一致
4. 修复后重试

---

## 成功标准

- **TASKS_COMPLETE**：plan 里所有任务都执行完毕
- **TYPES_PASS**：零类型错误
- **LINT_PASS**：零 lint 错误
- **TESTS_PASS**：所有测试绿，新增测试已写
- **BUILD_PASS**：构建成功
- **REPORT_CREATED**：实施报告已保存
- **PLAN_ARCHIVED**：plan 已移入 `completed/`

---

## 下一步

- 运行 `/code-review` 在提交前审查改动
- 运行 `/prp-commit` 以描述性信息提交
- 运行 `/prp-pr` 创建 PR
- 若 PRD 还有后续 phase，运行 `/prp-plan <next-phase>`
