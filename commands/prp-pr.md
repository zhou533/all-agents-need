---
description: 从当前分支（含未推送的提交）创建一个 GitHub PR —— 自动发现模板、分析改动、推送分支
argument-hint: "[base-branch]（默认：main）"
---

# 创建 Pull Request

> 改编自 Wirasm 的 PRPs-agentic-eng。属于 PRP 工作流系列的一部分。

**输入**：`$ARGUMENTS` —— 可选，可能包含基准分支名和/或标志位（例如 `--draft`）。

**解析 `$ARGUMENTS`**：
- 提取可识别的标志位（`--draft`）
- 剩余非标志位文本视为基准分支名
- 未指定时，基准分支默认为 `main`

---

## 阶段 1 —— VALIDATE

检查前置条件：

```bash
git branch --show-current
git status --short
git log origin/<base>..HEAD --oneline
```

| 检查项 | 条件 | 失败时动作 |
|---|---|---|
| 不在基准分支 | 当前分支 ≠ base | 停止："请先切到 feature 分支。" |
| 工作区干净 | 无未提交改动 | 警告："你有未提交改动。请先 commit 或 stash。可用 `/prp-commit` 提交。" |
| 领先 base 若干提交 | `git log origin/<base>..HEAD` 非空 | 停止："没有领先 `<base>` 的提交，没什么可 PR 的。" |
| 不存在 PR | `gh pr list --head <branch> --json number` 为空 | 停止："PR 已存在：#<number>。用 `gh pr view <number> --web` 打开。" |

全部通过后继续。

---

## 阶段 2 —— DISCOVER

### PR 模板

按顺序搜索 PR 模板：

1. `.github/PULL_REQUEST_TEMPLATE/` 目录 —— 若存在，列出其中文件让用户选择（或默认用 `default.md`）
2. `.github/PULL_REQUEST_TEMPLATE.md`
3. `.github/pull_request_template.md`
4. `docs/pull_request_template.md`

找到即读取，其结构作为 PR 正文结构。

### 提交分析

```bash
git log origin/<base>..HEAD --format="%h %s" --reverse
```

分析提交以确定：
- **PR 标题**：使用 conventional commit 格式的类型前缀 —— `feat: ...`、`fix: ...` 等
  - 若含多种类型，用出现最多的那个
  - 若只有一个提交，直接用其消息
- **改动摘要**：按类型/区域聚合

### 文件分析

```bash
git diff origin/<base>..HEAD --stat
git diff origin/<base>..HEAD --name-only
```

把改动文件归类：源码、测试、文档、配置、迁移。

### PRP 工件

检查是否有相关 PRP 工件：
- `.claude/PRPs/reports/` —— 实施报告
- `.claude/PRPs/plans/` —— 已执行的计划
- `.claude/PRPs/prds/` —— 相关 PRD

存在则在 PR 正文中引用。

---

## 阶段 3 —— PUSH

```bash
git push -u origin HEAD
```

若因分支分叉推送失败：
```bash
git fetch origin
git rebase origin/<base>
git push -u origin HEAD
```

若 rebase 出现冲突，停止并告知用户。

---

## 阶段 4 —— CREATE

### 有模板时

若阶段 2 找到 PR 模板，用提交和文件分析填充每个段落。保留模板所有段落 —— 不适用的写 "N/A" 而不是删除。

### 无模板时

使用下述默认格式：

```markdown
## Summary

<用 1-2 句话描述本 PR 做了什么、为什么做>

## Changes

<按区域聚合的改动列表>

## Files Changed

<改动文件清单，标注类型：Added/Modified/Deleted>

## Testing

<改动是如何测试的，或写 "Needs testing">

## Related Issues

<相关 issue 用 Closes/Fixes/Relates to #N 关联，或 "None">
```

### 创建 PR

```bash
gh pr create \
  --title "<PR title>" \
  --base <base-branch> \
  --body "<PR body>"
  # 若 $ARGUMENTS 解析出 --draft 标志位，则追加 --draft
```

---

## 阶段 5 —— VERIFY

```bash
gh pr view --json number,url,title,state,baseRefName,headRefName,additions,deletions,changedFiles
gh pr checks --json name,status,conclusion 2>/dev/null || true
```

---

## 阶段 6 —— OUTPUT

向用户汇报：

```
PR #<number>: <title>
URL: <url>
Branch: <head> → <base>
Changes: +<additions> -<deletions> 覆盖 <changedFiles> 个文件

CI Checks: <状态摘要，或 "pending"，或 "none configured">

已引用工件：
  - <PR 正文中链接的 PRP reports/plans>

下一步：
  - gh pr view <number> --web   → 在浏览器中打开
  - /code-review <number>       → 审查该 PR
  - gh pr merge <number>        → 准备好后合并
```

---

## 边界情况

- **无 `gh` CLI**：停止并提示："需要 GitHub CLI (`gh`)。安装：<https://cli.github.com/>"
- **未认证**：停止并提示："请先运行 `gh auth login`。"
- **需要强推**：若远端已分叉且已完成 rebase，使用 `git push --force-with-lease`（绝不使用 `--force`）。
- **多个 PR 模板**：若 `.github/PULL_REQUEST_TEMPLATE/` 下有多个文件，列出让用户选择。
- **大 PR（>20 文件）**：给出 PR 体量过大的警告。若改动逻辑上可拆分，建议拆 PR。
