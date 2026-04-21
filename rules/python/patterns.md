---
paths:
  - "**/*.py"
  - "**/*.pyi"
---

# Python 模式

> 本文档扩展了 [common/patterns.md](../common/patterns.md) 中关于 Python 的特定内容。

## Protocol（鸭子类型）

```python
from typing import Protocol

class Repository(Protocol):
    def find_by_id(self, id: str) -> dict | None: ...
    def save(self, entity: dict) -> dict: ...
```

## Dataclass 作为 DTO

```python
from dataclasses import dataclass

@dataclass
class CreateUserRequest:
    name: str
    email: str
    age: int | None = None
```

## 上下文管理器与生成器

* 使用上下文管理器（`with` 语句）管理资源
* 使用生成器（generator）进行惰性求值与内存高效迭代

## 参考

有关全面的 Python 模式（装饰器、并发、包组织等），请参阅技能：`python-patterns`。
