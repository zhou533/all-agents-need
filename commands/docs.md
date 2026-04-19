---
description: documentation-lookup 技能的遗留 slash 入口 shim。请优先直接使用该技能。
---

# Docs 命令（遗留 Shim）

仅在你仍然习惯输入 `/docs` 时使用本命令。真正维护的工作流位于 `skills/documentation-lookup/SKILL.md`。

## 权威入口（Canonical Surface）

- 优先直接使用 `documentation-lookup` 技能。
- 本文件仅作为兼容入口保留。

## 参数

`$ARGUMENTS`

## 委派（Delegation）

应用 `documentation-lookup` 技能。
- 如果缺少库名或具体问题，向用户追问缺失的部分。
- 通过 Context7 使用实时文档，而不是依赖训练数据。
- 只返回当前的答案以及所需的最小代码/示例。
