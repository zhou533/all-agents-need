---
description: 快速提交，支持自然语言定位文件 —— 用平白的中文/英文描述要提交什么
argument-hint: "[target description]（留空则提交所有改动）"
---

# Smart Commit

> 改编自 Wirasm 的 PRPs-agentic-eng。属于 PRP 工作流系列的一部分。

**输入**：$ARGUMENTS

---

## 阶段 1 —— ASSESS

```bash
git status --short
```

若输出为空 → 停止："没有可提交的改动。"

向用户展示改动概览（新增、修改、删除、未跟踪）。

---

## 阶段 2 —— INTERPRET & STAGE

解释 `$ARGUMENTS` 决定要暂存什么：

| 输入 | 解释 | Git 命令 |
|---|---|---|
| *（空）* | 暂存全部 | `git add -A` |
| `staged` | 使用已经暂存的内容 | *（不执行 git add）* |
| `*.ts` 或 `*.py` 等 | 按 glob 暂存 | `git add '*.ts'` |
| `except tests` | 暂存全部后排除测试 | `git add -A && git reset -- '**/*.test.*' '**/*.spec.*' '**/test_*' 2>/dev/null \|\| true` |
| `only new files` | 仅暂存未跟踪文件 | `git ls-files --others --exclude-standard \| grep . && git ls-files --others --exclude-standard \| xargs git add` |
| `the auth changes` | 根据 status/diff 识别认证相关文件 | `git add <匹配到的文件>` |
| 具体文件名 | 暂存这些文件 | `git add <files>` |

对自然语言输入（如 "the auth changes"），交叉参考 `git status` 输出和 `git diff` 识别相关文件。告知用户你在暂存哪些文件及原因。

```bash
git add <判定的文件>
```

暂存后验证：
```bash
git diff --cached --stat
```

若无文件暂存，停止："没有文件匹配你的描述。"

---

## 阶段 3 —— COMMIT

用祈使语气写一行 commit message：

```
{type}: {description}
```

类型：
- `feat` —— 新功能或能力
- `fix` —— bug 修复
- `refactor` —— 不改行为的重构
- `docs` —— 文档改动
- `test` —— 新增或更新测试
- `chore` —— 构建、配置、依赖
- `perf` —— 性能改进
- `ci` —— CI/CD 改动

规则：
- 祈使语气（"add feature" 而非 "added feature"）
- 类型前缀之后全小写
- 末尾不加句号
- 不超过 72 字符
- 描述**改了什么**，不是**怎么改的**

```bash
git commit -m "{type}: {description}"
```

---

## 阶段 4 —— OUTPUT

向用户汇报：

```
Committed: {hash_short}
Message:   {type}: {description}
Files:     {count} file(s) changed

下一步：
  - git push           → 推到远端
  - /prp-pr            → 创建 pull request
  - /code-review       → 推送前先审查
```

---

## 示例

| 你说 | 发生什么 |
|---|---|
| `/prp-commit` | 暂存全部，自动生成 message |
| `/prp-commit staged` | 只提交已暂存的内容 |
| `/prp-commit *.ts` | 暂存所有 TypeScript 文件并提交 |
| `/prp-commit except tests` | 暂存一切，排除测试文件 |
| `/prp-commit the database migration` | 从 status 中找出 DB 迁移文件暂存提交 |
| `/prp-commit only new files` | 只暂存未跟踪文件 |
