---
paths:
  - "**/*.py"
  - "**/*.pyi"
---

# Python Hooks

> 本文档扩展了 [common/hooks.md](../common/hooks.md) 中关于 Python 的特定内容。

## PostToolUse Hooks

在 `~/.claude/settings.json` 中配置：

* **black/ruff**：编辑后自动格式化 `.py` 文件
* **mypy/pyright**：编辑 `.py` 文件后执行类型检查

## 警告

* 对编辑过的文件中的 `print()` 语句发出警告（改用 `logging` 模块）
