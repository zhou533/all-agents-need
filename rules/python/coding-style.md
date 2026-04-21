---
paths:
  - "**/*.py"
  - "**/*.pyi"
---

# Python 编码风格

> 本文档扩展了 [common/coding-style.md](../common/coding-style.md) 中关于 Python 的特定内容。

## 标准

* 遵循 **PEP 8** 约定
* 所有函数签名都带 **类型注解**（type annotations）

## 不可变性

优先使用不可变数据结构：

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class User:
    name: str
    email: str

from typing import NamedTuple

class Point(NamedTuple):
    x: float
    y: float
```

## 格式化

* **black** 用于代码格式化
* **isort** 用于 import 排序
* **ruff** 用于代码检查

## 参考

有关全面的 Python 惯用法和模式，请参阅技能：`python-patterns`。
