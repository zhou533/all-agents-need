---
name: postgres-patterns
description: PostgreSQL 数据库模式，涵盖查询优化、schema 设计、索引与安全。基于 Supabase 最佳实践。
origin: AAN
---

# PostgreSQL 模式

PostgreSQL 最佳实践速查。如需完整指引，请使用 `database-reviewer` agent。

## 何时激活

- 编写 SQL 查询或迁移
- 设计数据库 schema
- 排查慢查询
- 实施行级安全（Row Level Security）
- 配置连接池

## 速查手册

### 索引速查

| 查询模式 | 索引类型 | 示例 |
|----------|---------|------|
| `WHERE col = value` | B-tree（默认） | `CREATE INDEX idx ON t (col)` |
| `WHERE col > value` | B-tree | `CREATE INDEX idx ON t (col)` |
| `WHERE a = x AND b > y` | 复合索引 | `CREATE INDEX idx ON t (a, b)` |
| `WHERE jsonb @> '{}'` | GIN | `CREATE INDEX idx ON t USING gin (col)` |
| `WHERE tsv @@ query` | GIN | `CREATE INDEX idx ON t USING gin (col)` |
| 时间序列范围查询 | BRIN | `CREATE INDEX idx ON t USING brin (col)` |

### 数据类型速查

| 用途 | 推荐类型 | 避免使用 |
|------|---------|---------|
| ID | `bigint` | `int`、随机 UUID |
| 字符串 | `text` | `varchar(255)` |
| 时间戳 | `timestamptz` | `timestamp` |
| 金额 | `numeric(10,2)` | `float` |
| 标志位 | `boolean` | `varchar`、`int` |

### 常见模式

**复合索引顺序：**
```sql
-- 先放等值列，再放范围列
CREATE INDEX idx ON orders (status, created_at);
-- 适用于：WHERE status = 'pending' AND created_at > '2024-01-01'
```

**覆盖索引（Covering Index）：**
```sql
CREATE INDEX idx ON users (email) INCLUDE (name, created_at);
-- 对 SELECT email, name, created_at 无需回表
```

**部分索引（Partial Index）：**
```sql
CREATE INDEX idx ON users (email) WHERE deleted_at IS NULL;
-- 更小的索引，只包含活跃用户
```

**RLS 策略（优化版）：**
```sql
CREATE POLICY policy ON orders
  USING ((SELECT auth.uid()) = user_id);  -- 务必用 SELECT 包一层！
```

**UPSERT：**
```sql
INSERT INTO settings (user_id, key, value)
VALUES (123, 'theme', 'dark')
ON CONFLICT (user_id, key)
DO UPDATE SET value = EXCLUDED.value;
```

**游标分页：**
```sql
SELECT * FROM products WHERE id > $last_id ORDER BY id LIMIT 20;
-- O(1)；OFFSET 是 O(n)
```

**队列消费：**
```sql
UPDATE jobs SET status = 'processing'
WHERE id = (
  SELECT id FROM jobs WHERE status = 'pending'
  ORDER BY created_at LIMIT 1
  FOR UPDATE SKIP LOCKED
) RETURNING *;
```

### 反模式检测

```sql
-- 查找缺失索引的外键
SELECT conrelid::regclass, a.attname
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
WHERE c.contype = 'f'
  AND NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indrelid = c.conrelid AND a.attnum = ANY(i.indkey)
  );

-- 查找慢查询
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
WHERE mean_exec_time > 100
ORDER BY mean_exec_time DESC;

-- 检查表膨胀
SELECT relname, n_dead_tup, last_vacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```

### 配置模板

```sql
-- 连接数限制（依 RAM 调整）
ALTER SYSTEM SET max_connections = 100;
ALTER SYSTEM SET work_mem = '8MB';

-- 超时设置
ALTER SYSTEM SET idle_in_transaction_session_timeout = '30s';
ALTER SYSTEM SET statement_timeout = '30s';

-- 监控扩展
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- 安全默认值
REVOKE ALL ON SCHEMA public FROM public;

SELECT pg_reload_conf();
```

## 相关

- Agent：`database-reviewer` —— 完整的数据库审查工作流
- Skill：`database-migrations` —— 数据库迁移最佳实践
- Skill：`backend-patterns` —— API 与后端模式

---

*基于 Supabase Agent Skills（致谢 Supabase 团队，MIT 许可证）*
