---
description: verification-loop skill 的遗留 slash 入口兼容层。推荐直接使用该 skill。
---

# 验证命令（遗留兼容层）

仅当你仍在调用 `/verify` 时才使用本文件。维护中的工作流位于 `skills/verification-loop/SKILL.md`。

## 正式入口（Canonical Surface）

- 优先直接使用 `verification-loop` skill。
- 本文件仅作为兼容入口点保留。

## 参数

`$ARGUMENTS`

## 委派

应用 `verification-loop` skill。
- 根据用户请求的模式选择合适的验证深度。
- 按当前仓库的正确顺序运行构建、类型检查、lint、测试、安全/日志检查以及 diff 审查。
- 只汇报结论和阻塞项，不在此处另行维护一份验证清单。
