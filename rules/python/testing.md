---
paths:
  - "**/*.py"
  - "**/*.pyi"
---

# Python 测试

> 本文档扩展了 [common/testing.md](../common/testing.md) 中关于 Python 的特定内容。

## 框架

使用 **pytest** 作为测试框架。

## 覆盖率

```bash
pytest --cov=src --cov-report=term-missing
```

## 测试组织

使用 `pytest.mark` 对测试分类：

```python
import pytest

@pytest.mark.unit
def test_calculate_total():
    ...

@pytest.mark.integration
def test_database_connection():
    ...
```

## 参考

有关 pytest 的详细模式与 fixture，请参阅技能：`python-testing`。
