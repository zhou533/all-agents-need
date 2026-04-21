---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
---

# TypeScript/JavaScript 安全

> 本文档扩展了 [common/security.md](../common/security.md) 中关于 TypeScript/JavaScript 的特定内容。

## 密钥管理

```typescript
// NEVER: Hardcoded secrets
const apiKey = "sk-proj-xxxxx"

// ALWAYS: Environment variables
const apiKey = process.env.OPENAI_API_KEY

if (!apiKey) {
  throw new Error('OPENAI_API_KEY not configured')
}
```

## Agent 支持

* 使用 **security-reviewer** agent 做全面安全审计
