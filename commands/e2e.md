---
description: e2e-testing skill 的遗留 slash 入口兼容层。推荐直接使用该 skill。
---

# E2E 命令（遗留兼容层）

仅当你仍在调用 `/e2e` 时才使用本文件。维护中的工作流位于 `skills/e2e-testing/SKILL.md`。

## 正式入口（Canonical Surface）

- 优先直接使用 `e2e-testing` skill。
- 本文件仅作为兼容入口点保留。

## 参数

`$ARGUMENTS`

## 委派

应用 `e2e-testing` skill。
- 为用户请求的流程生成或更新 Playwright 覆盖。
- 仅运行相关测试，除非用户显式要求运行整套测试。
- 正常采集产物（screenshots / videos / traces / 报告），并汇报失败项、flake 风险、下一步修复建议，无需在此处重复 skill 正文内容。
