---
paths:
  - "**/*.py"
  - "**/*.pyi"
---

# Python 安全

> 本文档扩展了 [common/security.md](../common/security.md) 中关于 Python 的特定内容。

## 密钥管理

```python
import os
from dotenv import load_dotenv

load_dotenv()

api_key = os.environ["OPENAI_API_KEY"]  # Raises KeyError if missing
```

## 安全扫描

* 使用 **bandit** 执行静态安全分析：

  ```bash
  bandit -r src/
  ```

## 参考

如使用 Django，请参阅技能：`django-security`，获取 Django 专属的安全指南。
