---
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
---

# Go 模式

> 本文档扩展了 [common/patterns.md](../common/patterns.md) 中关于 Go 的特定内容。

## 函数式选项（Functional Options）

```go
type Option func(*Server)

func WithPort(port int) Option {
    return func(s *Server) { s.port = port }
}

func NewServer(opts ...Option) *Server {
    s := &Server{port: 8080}
    for _, opt := range opts {
        opt(s)
    }
    return s
}
```

## 小接口

在接口的使用方定义接口，而不是在实现方定义。

## 依赖注入

通过构造函数注入依赖：

```go
func NewUserService(repo UserRepository, logger Logger) *UserService {
    return &UserService{repo: repo, logger: logger}
}
```

## 参考

有关全面的 Go 模式（并发、错误处理、包组织等），请参阅技能：`golang-patterns`。
