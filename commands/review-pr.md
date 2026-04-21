---
description: 使用多个专门 agent 进行综合 PR 审查
---

对一个 Pull Request 进行跨视角的综合审查。

## 用法

`/review-pr [PR-number-or-URL] [--focus=comments|tests|errors|types|code|simplify]`

未指定 PR 时，默认审查当前分支对应的 PR。未指定 focus 时，运行完整审查栈。

## 步骤

1. 识别 PR：
   - 使用 `gh pr view` 获取 PR 详情、改动文件与 diff
2. 查找项目指引：
   - 查看 `CLAUDE.md`、lint 配置、TypeScript 配置、仓库约定
3. 运行专门的审查 agent：
   - `code-reviewer`
   - `comment-analyzer`
   - `pr-test-analyzer`
   - `silent-failure-hunter`
   - `type-design-analyzer`
   - `code-simplifier`
4. 汇总结果：
   - 合并重复发现
   - 按严重度排序
5. 按严重度分组汇报发现

## 置信度规则

仅汇报置信度 >= 80 的问题：

- Critical：bug、安全、数据丢失
- Important：测试缺失、质量问题、风格违规
- Advisory：仅在显式请求时给建议
