---
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
---

# Go Hooks

> 本文档扩展了 [common/hooks.md](../common/hooks.md) 中关于 Go 的特定内容。

## PostToolUse Hooks

在 `~/.claude/settings.json` 中配置：

* **gofmt/goimports**：编辑后自动格式化 `.go` 文件
* **go vet**：编辑 `.go` 文件后执行静态分析
* **staticcheck**：对修改过的包执行扩展静态检查
