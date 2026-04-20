---
description: 强制执行带 Git 检查点与 RED/GREEN 门禁的测试驱动开发。每个阶段创建可审计的提交证据，仅在有效 RED 后允许改生产代码、仅在有效 GREEN 后允许进入 refactor。
---

# TDD v2 命令

此命令在 `/tdd` 的基础上，强制引入 **Git 检查点**与**可验证的 RED/GREEN 门禁**，面向需要审计证据的严肃开发场景。

## v2 相对 v1 的增量

| 维度 | /tdd (v1) | /tdd-v2 |
|------|-----------|---------|
| TDD 循环 | RED → GREEN → REFACTOR | 同 |
| Git 检查点 | 未约束 | **每阶段强制检查点提交** |
| RED 判定 | 测试失败即可 | 必须是**运行时 RED**或**编译期 RED**，且由预期业务 bug 引起 |
| GREEN 判定 | 测试通过即可 | 必须**重新运行同一相关测试目标**并通过 |
| 改生产代码的前置 | 无硬性门禁 | **未确认 RED 不得改生产代码** |
| 进入 refactor 的前置 | 无硬性门禁 | **未确认 GREEN 不得 refactor** |
| 分支归属 | 无约束 | 只计入**当前活动分支**可达的提交 |

## 何时使用 v2

* 修复生产 bug，且变更需要可审计的提交证据
* 在受约束分支（release/hotfix）上开发
* 多人协作、代码评审要求 RED/GREEN 过程可追溯
* 需要防止"写了测试但从未执行"的反模式

普通新功能开发，`/tdd` 已经足够。

## 工作流（7 步 + 检查点）

### 步骤 1：编写用户旅程

格式：`作为[角色]，我希望[行动]，以便[收益]`。

### 步骤 2：生成测试用例

覆盖正常路径、边缘情况、错误场景、边界条件。

### 步骤 3：运行测试 — RED 门禁（强制）

运行测试，必须通过以下**任一路径**确认有效 RED：

**路径 A — 运行时 RED（Runtime RED）：**

* 相关测试目标能够编译通过
* 新增或修改的测试确实被执行
* 结果为 RED（失败）

**路径 B — 编译期 RED（Compile-time RED）：**

* 新增测试首次实例化、引用或触达了问题代码路径
* 编译失败本身即为预期的 RED 信号

**两种情形都必须满足：**

* 失败由预期的业务逻辑 bug、未定义行为或缺失实现引起
* 失败**不是**由无关的语法错误、损坏的测试环境、缺失依赖或无关回归引起

**关键约束：**

* 仅被编写但未经编译和执行的测试**不算 RED**
* 在确认 RED 状态之前，**禁止编辑生产代码**

**检查点提交（若仓库受 Git 管理）：**

```bash
git add <test files>
git commit -m "test: add reproducer for <feature or bug>"
```

* 若该复现用例已被编译执行并因预期原因失败，此提交可同时作为 RED 验证检查点
* 确认该提交位于当前活动分支上、可从 `HEAD` 到达

### 步骤 4：实现最小化代码

* 只写让测试通过的最少代码
* 暂存改动（`git add`）但**推迟提交**到 GREEN 验证后

### 步骤 5：再次运行测试 — GREEN 门禁（强制）

* **重新运行步骤 3 中的同一相关测试目标**
* 确认之前失败的测试现在已变为 GREEN
* 只有在获得有效 GREEN 之后，才能进入 refactor

**检查点提交：**

```bash
git commit -m "fix: <feature or bug>"
```

* 若该修复提交对应的相关测试目标已被重新运行并通过，此提交可同时作为 GREEN 验证检查点
* 确认该提交位于当前活动分支上

### 步骤 6：重构

改进代码质量（消除重复、改进命名、优化性能、增强可读性），同时保持测试为 green。

**检查点提交（可选）：**

```bash
git commit -m "refactor: clean up after <feature or bug> implementation"
```

* 仅在确实发生了重构时创建
* 若测试提交明确对应 RED、修复提交明确对应 GREEN，且未重构，则此提交可省略

### 步骤 7：验证覆盖率

```bash
npm run test:coverage
# 目标：80%+（关键业务代码 100%）
```

## 检查点提交规范

| 阶段 | 消息前缀 | 用途 |
|------|---------|------|
| Step 3 RED | `test: add reproducer for ...` | 失败测试 + RED 验证证据 |
| Step 5 GREEN | `fix: ...` | 最小修复 + GREEN 验证证据 |
| Step 6 Refactor | `refactor: clean up after ...` | 重构完成（可选） |

**推荐的紧凑工作流**（3 个提交完成一个 TDD 循环）：

1. 一个提交：添加失败测试并完成 RED 验证
2. 一个提交：应用最小改动并完成 GREEN 验证
3. 一个可选提交：完成 refactor

**禁止事项：**

* 不要 squash 或重写这些检查点提交，直到整个工作流完成
* 不要把其他分支、早期无关工作、遥远分支历史的提交当作有效证据
* 不要在未验证 RED 时编辑生产代码
* 不要在未验证 GREEN 时进入 refactor

## 使用示例

（精简版，展示 Git 检查点时序；完整 TDD 代码模板参考 `/tdd`）

```bash
# Step 2-3: 写测试 + 验证 RED
$ npm test lib/liquidity.test.ts
FAIL lib/liquidity.test.ts
  ✕ should return high score for liquid market
  Error: Not implemented

$ git add lib/liquidity.test.ts
$ git commit -m "test: add reproducer for liquidity score calculator"
# → RED 检查点

# Step 4-5: 实现 + 验证 GREEN
$ npm test lib/liquidity.test.ts
PASS lib/liquidity.test.ts (3 tests)

$ git add lib/liquidity.ts
$ git commit -m "fix: implement liquidity score calculator"
# → GREEN 检查点

# Step 6: refactor (可选)
$ npm test lib/liquidity.test.ts
PASS lib/liquidity.test.ts (3 tests)

$ git add lib/liquidity.ts
$ git commit -m "refactor: clean up after liquidity calculator implementation"
# → Refactor 检查点
```

## 与其他命令的集成

* 使用 `/plan` 明确要构建什么
* 使用 `/tdd-v2` 进行带检查点审计的实现（严肃场景）或 `/tdd` 进行常规实现
* 出现构建错误时使用 `/build-fix`
* 使用 `/code-review` 审查实现

## 相关资源

* 底层技能：`all-agents-need/skills/tdd-workflow/SKILL.md`（含完整 Git 检查点规范）
* 轻量替代：`all-agents-need/commands/tdd.md`
