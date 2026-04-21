---
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
---

# Go 测试

> 本文档扩展了 [common/testing.md](../common/testing.md) 中关于 Go 的特定内容。

## 框架

使用标准 `go test`，配合**表驱动测试**（table-driven tests）。

## 竞态检测

始终带 `-race` 标志运行：

```bash
go test -race ./...
```

## 覆盖率

```bash
go test -cover ./...
```

## 参考

有关 Go 测试的详细模式与辅助工具，请参阅技能：`golang-testing`。
