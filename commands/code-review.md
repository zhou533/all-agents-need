---
description: 代码审查 —— 本地未提交更改或 GitHub PR（传入 PR 号/URL 启用 PR 模式）
argument-hint: [pr-number | pr-url | blank for local review]
---

# 代码审查

> PR 审查模式改编自 Wirasm 的 PRPs-agentic-eng。属于 PRP 工作流系列的一部分。

**输入**：$ARGUMENTS

---

## 模式选择（Mode Selection）

如果 `$ARGUMENTS` 中包含 PR 编号、PR URL 或 `--pr`：
→ 跳转至下方的 **PR 审查模式**。

否则：
→ 使用 **本地审查模式**。

---

## 本地审查模式（Local Review Mode）

对未提交的更改进行全面的安全性和质量审查。

### 阶段 1 —— GATHER

```bash
git diff --name-only HEAD
```

如果没有更改的文件，停止并输出："没有需要审查的内容。"

### 阶段 2 —— REVIEW

完整阅读每个更改的文件。检查：

**安全问题（CRITICAL）：**
- 硬编码的凭据、API 密钥、令牌
- SQL 注入漏洞
- XSS 漏洞
- 缺少输入验证
- 不安全的依赖项
- 路径遍历风险

**代码质量（HIGH）：**
- 函数长度超过 50 行
- 文件长度超过 800 行
- 嵌套深度超过 4 层
- 缺少错误处理
- `console.log` 语句
- `TODO`/`FIXME` 注释
- 公共 API 缺少 JSDoc

**最佳实践（MEDIUM）：**
- 可变模式（应使用不可变模式）
- 代码/注释中使用表情符号
- 新代码缺少测试
- 无障碍性问题（a11y）

### 阶段 3 —— REPORT

生成报告，包含：
- 严重性：CRITICAL、HIGH、MEDIUM、LOW
- 文件位置和行号
- 问题描述
- 建议的修复方法

如果发现 CRITICAL 或 HIGH 问题，阻止提交。
绝不批准存在安全漏洞的代码。

---

## PR 审查模式（PR Review Mode）

全面的 GitHub PR 审查 —— 拉取 diff、完整阅读文件、运行验证、发布审查。

### 阶段 1 —— FETCH

解析输入以确定 PR：

| 输入 | 操作 |
|---|---|
| 数字（例如 `42`） | 作为 PR 号使用 |
| URL（`github.com/.../pull/42`） | 提取 PR 号 |
| 分支名 | 通过 `gh pr list --head <branch>` 查找 PR |

```bash
gh pr view <NUMBER> --json number,title,body,author,baseRefName,headRefName,changedFiles,additions,deletions
gh pr diff <NUMBER>
```

如果找不到 PR，停止并报错。保存 PR 元数据供后续阶段使用。

### 阶段 2 —— CONTEXT

构建审查上下文：

1. **项目规则** —— 阅读 `CLAUDE.md`、`.claude/docs/` 以及任何贡献指南
2. **PRP 工件** —— 检查 `.claude/PRPs/reports/` 和 `.claude/PRPs/plans/` 中与此 PR 相关的实现上下文
3. **PR 意图** —— 解析 PR 描述，提取目标、关联的 issue、测试计划
4. **更改的文件** —— 列出所有修改的文件并按类型分类（源码、测试、配置、文档）

### 阶段 3 —— REVIEW

**完整阅读**每个更改的文件（不只是 diff hunk —— 你需要周边上下文）。

对于 PR 审查，拉取 PR head 版本下的完整文件内容：
```bash
gh pr diff <NUMBER> --name-only | while IFS= read -r file; do
  gh api "repos/{owner}/{repo}/contents/$file?ref=<head-branch>" --jq '.content' | base64 -d
done
```

应用 7 大类审查清单：

| 类别 | 检查什么 |
|---|---|
| **正确性（Correctness）** | 逻辑错误、off-by-one、空值处理、边界情况、竞态条件 |
| **类型安全（Type Safety）** | 类型不匹配、不安全的强制转换、`any` 的使用、缺失的泛型 |
| **模式合规（Pattern Compliance）** | 是否符合项目约定（命名、文件结构、错误处理、导入） |
| **安全（Security）** | 注入、认证缺口、密钥泄露、SSRF、路径遍历、XSS |
| **性能（Performance）** | N+1 查询、缺失索引、无边界循环、内存泄漏、大负载 |
| **完整性（Completeness）** | 缺失测试、缺失错误处理、不完整的迁移、缺失文档 |
| **可维护性（Maintainability）** | 死代码、魔数、深层嵌套、含糊命名、缺失类型 |

为每条发现分配严重度：

| 严重度 | 含义 | 处理方式 |
|---|---|---|
| **CRITICAL** | 安全漏洞或数据丢失风险 | 合并前必须修复 |
| **HIGH** | 很可能导致问题的 bug 或逻辑错误 | 合并前应当修复 |
| **MEDIUM** | 代码质量问题或缺失最佳实践 | 建议修复 |
| **LOW** | 风格小瑕疵或次要建议 | 可选 |

### 阶段 4 —— VALIDATE

运行可用的验证命令：

从配置文件（`package.json`、`Cargo.toml`、`go.mod`、`pyproject.toml` 等）识别项目类型，然后运行相应命令：

**Node.js / TypeScript**（含 `package.json`）：
```bash
npm run typecheck 2>/dev/null || npx tsc --noEmit 2>/dev/null  # 类型检查
npm run lint                                                    # Lint
npm test                                                        # 测试
npm run build                                                   # 构建
```

**Rust**（含 `Cargo.toml`）：
```bash
cargo clippy -- -D warnings  # Lint
cargo test                   # 测试
cargo build                  # 构建
```

**Go**（含 `go.mod`）：
```bash
go vet ./...    # Lint
go test ./...   # 测试
go build ./...  # 构建
```

**Python**（含 `pyproject.toml` / `setup.py`）：
```bash
pytest  # 测试
```

只运行适用于已识别项目类型的命令。记录每项的 pass/fail。

### 阶段 5 —— DECIDE

基于发现形成推荐：

| 条件 | 决策 |
|---|---|
| 零 CRITICAL/HIGH 问题，验证通过 | **APPROVE** |
| 仅 MEDIUM/LOW 问题，验证通过 | **APPROVE**（附评论） |
| 有任何 HIGH 问题或验证失败 | **REQUEST CHANGES** |
| 有任何 CRITICAL 问题 | **BLOCK** —— 合并前必须修复 |

特殊情况：
- Draft PR → 始终使用 **COMMENT**（不 approve/block）
- 仅文档/配置更改 → 轻量审查，聚焦正确性
- 显式 `--approve` 或 `--request-changes` 标志 → 覆盖决策（但仍报告所有发现）

### 阶段 6 —— REPORT

在 `.claude/PRPs/reviews/pr-<NUMBER>-review.md` 创建审查工件：

```markdown
# PR Review: #<NUMBER> — <TITLE>

**Reviewed**: <date>
**Author**: <author>
**Branch**: <head> → <base>
**Decision**: APPROVE | REQUEST CHANGES | BLOCK

## Summary
<1-2 句整体评估>

## Findings

### CRITICAL
<发现内容或 "None">

### HIGH
<发现内容或 "None">

### MEDIUM
<发现内容或 "None">

### LOW
<发现内容或 "None">

## Validation Results

| Check | Result |
|---|---|
| Type check | Pass / Fail / Skipped |
| Lint | Pass / Fail / Skipped |
| Tests | Pass / Fail / Skipped |
| Build | Pass / Fail / Skipped |

## Files Reviewed
<文件列表，附变更类型：Added/Modified/Deleted>
```

### 阶段 7 —— PUBLISH

将审查发布到 GitHub：

```bash
# 若 APPROVE
gh pr review <NUMBER> --approve --body "<审查摘要>"

# 若 REQUEST CHANGES
gh pr review <NUMBER> --request-changes --body "<附必修项的摘要>"

# 若仅 COMMENT（Draft PR 或信息性）
gh pr review <NUMBER> --comment --body "<摘要>"
```

对特定行的内联评论，使用 GitHub review comments API：
```bash
gh api "repos/{owner}/{repo}/pulls/<NUMBER>/comments" \
  -f body="<comment>" \
  -f path="<file>" \
  -F line=<line-number> \
  -f side="RIGHT" \
  -f commit_id="$(gh pr view <NUMBER> --json headRefOid --jq .headRefOid)"
```

或者，一次性发布一个包含多条内联评论的 review：
```bash
gh api "repos/{owner}/{repo}/pulls/<NUMBER>/reviews" \
  -f event="COMMENT" \
  -f body="<整体摘要>" \
  --input comments.json  # [{"path": "file", "line": N, "body": "comment"}, ...]
```

### 阶段 8 —— OUTPUT

向用户报告：

```
PR #<NUMBER>: <TITLE>
Decision: <APPROVE|REQUEST_CHANGES|BLOCK>

Issues: <critical_count> critical, <high_count> high, <medium_count> medium, <low_count> low
Validation: <pass_count>/<total_count> checks passed

Artifacts:
  Review: .claude/PRPs/reviews/pr-<NUMBER>-review.md
  GitHub: <PR URL>

Next steps:
  - <基于决策的上下文建议>
```

---

## 边界情况（Edge Cases）

- **没有 `gh` CLI**：回退到仅本地审查（阅读 diff，跳过 GitHub 发布）。提示用户。
- **分支已分叉**：建议先执行 `git fetch origin && git rebase origin/<base>` 再审查。
- **大型 PR（>50 文件）**：警告审查范围。优先关注源码变更，然后是测试，最后是配置/文档。
