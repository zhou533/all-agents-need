---
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
---

# Go 编码风格

> 本文档扩展了 [common/coding-style.md](../common/coding-style.md) 中关于 Go 的特定内容。

## 格式化

* **gofmt** 与 **goimports** 是强制的 — 无风格之争

## 设计原则

* 接受接口，返回结构体
* 保持接口小（1-3 个方法）

## 错误处理

始终为错误附加上下文：

```go
if err != nil {
    return fmt.Errorf("failed to create user: %w", err)
}
```

## 参考

有关全面的 Go 惯用法和模式，请参阅技能：`golang-patterns`。
