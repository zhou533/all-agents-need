---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
---

# TypeScript/JavaScript 编码风格

> 本文档扩展了 [common/coding-style.md](../common/coding-style.md) 中关于 TypeScript/JavaScript 的特定内容。

## 类型与接口

用类型让公共 API、共享模型、组件 props 显式、可读、可复用。

### 公共 API

* 为导出的函数、共享工具、公共类方法显式标注参数与返回值类型
* 让 TypeScript 自动推断显而易见的局部变量类型
* 将反复出现的内联对象结构提取为命名类型或接口

```typescript
// WRONG: Exported function without explicit types
export function formatUser(user) {
  return `${user.firstName} ${user.lastName}`
}

// CORRECT: Explicit types on public APIs
interface User {
  firstName: string
  lastName: string
}

export function formatUser(user: User): string {
  return `${user.firstName} ${user.lastName}`
}
```

### Interface vs. Type Alias

* `interface` 用于可能被继承或实现的对象结构
* `type` 用于联合、交叉、元组、映射类型与工具类型
* 优先使用字符串字面量联合，而非 `enum`，除非有互操作性需求

```typescript
interface User {
  id: string
  email: string
}

type UserRole = 'admin' | 'member'
type UserWithRole = User & {
  role: UserRole
}
```

### 避免 `any`

* 应用代码中避免使用 `any`
* 外部或不受信任的输入使用 `unknown`，再安全收窄
* 当值的类型取决于调用方时，使用泛型

```typescript
// WRONG: any removes type safety
function getErrorMessage(error: any) {
  return error.message
}

// CORRECT: unknown forces safe narrowing
function getErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message
  }

  return 'Unexpected error'
}
```

### React Props

* 用命名的 `interface` 或 `type` 定义组件 props
* 显式标注回调 prop 的类型
* 除非有特定理由，不要使用 `React.FC`

```typescript
interface User {
  id: string
  email: string
}

interface UserCardProps {
  user: User
  onSelect: (id: string) => void
}

function UserCard({ user, onSelect }: UserCardProps) {
  return <button onClick={() => onSelect(user.id)}>{user.email}</button>
}
```

### JavaScript 文件

* 在 `.js` 与 `.jsx` 文件中，若类型能提升清晰度、又不便迁移到 TypeScript，可使用 JSDoc
* 保持 JSDoc 与运行时行为同步

```javascript
/**
 * @param {{ firstName: string, lastName: string }} user
 * @returns {string}
 */
export function formatUser(user) {
  return `${user.firstName} ${user.lastName}`
}
```

## 不可变性

使用展开运算符做不可变更新：

```typescript
interface User {
  id: string
  name: string
}

// WRONG: Mutation
function updateUser(user: User, name: string): User {
  user.name = name // MUTATION!
  return user
}

// CORRECT: Immutability
function updateUser(user: Readonly<User>, name: string): User {
  return {
    ...user,
    name
  }
}
```

## 错误处理

使用 async/await 搭配 try-catch，并安全收窄 unknown 类型的错误：

```typescript
interface User {
  id: string
  email: string
}

declare function riskyOperation(userId: string): Promise<User>

function getErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message
  }

  return 'Unexpected error'
}

const logger = {
  error: (message: string, error: unknown) => {
    // Replace with your production logger (for example, pino or winston).
  }
}

async function loadUser(userId: string): Promise<User> {
  try {
    const result = await riskyOperation(userId)
    return result
  } catch (error: unknown) {
    logger.error('Operation failed', error)
    throw new Error(getErrorMessage(error))
  }
}
```

## 输入校验

使用 Zod 做基于 schema 的校验，并从 schema 推导类型：

```typescript
import { z } from 'zod'

const userSchema = z.object({
  email: z.string().email(),
  age: z.number().int().min(0).max(150)
})

type UserInput = z.infer<typeof userSchema>

const validated: UserInput = userSchema.parse(input)
```

## Console.log

* 生产代码中禁止使用 `console.log`
* 使用正式的日志库代替
* 可通过 hook 自动检测
