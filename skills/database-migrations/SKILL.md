---
name: database-migrations
description: 数据库迁移最佳实践，涵盖 schema 变更、数据迁移、回滚与零停机部署，跨 PostgreSQL、MySQL 及常见 ORM（Prisma、Drizzle、Kysely、Django、TypeORM、golang-migrate）。
origin: AAN
---

# 数据库迁移模式

为生产系统提供安全、可回滚的数据库 schema 变更。

## 何时激活

- 创建或修改数据库表
- 增删列或索引
- 执行数据迁移（回填、转换）
- 规划零停机 schema 变更
- 为新项目搭建迁移工具

## 核心原则

1. **每一次变更都是一个迁移** —— 绝不手工改生产库
2. **生产环境的迁移只向前** —— 回滚用新的向前迁移实现
3. **Schema 迁移与数据迁移分离** —— 绝不在同一个迁移里混合 DDL 与 DML
4. **用生产规模的数据测试迁移** —— 在 100 行上能跑的迁移，到 1000 万行可能直接锁表
5. **已上线的迁移不可变** —— 绝不修改已在生产运行过的迁移

## 迁移安全清单

在应用任何迁移前：

- [ ] 迁移同时具备 UP 和 DOWN（或显式标记为不可逆）
- [ ] 大表上没有全表锁（使用 concurrent 操作）
- [ ] 新列有默认值或可为 NULL（绝不在无默认值的情况下直接加 NOT NULL）
- [ ] 索引使用并发创建（existing 表上不要内联写进 CREATE TABLE）
- [ ] 数据回填作为独立迁移，与 schema 变更分开
- [ ] 已用生产数据副本测试过
- [ ] 回滚预案已记录

## PostgreSQL 模式

### 安全地添加列

```sql
-- 好：可空列，不加锁
ALTER TABLE users ADD COLUMN avatar_url TEXT;

-- 好：带默认值的列（Postgres 11+ 瞬时生效，无需重写）
ALTER TABLE users ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT true;

-- 差：对存量表加 NOT NULL 且无默认值（会触发全表重写）
ALTER TABLE users ADD COLUMN role TEXT NOT NULL;
-- 这会锁表并重写每一行
```

### 无停机加索引

```sql
-- 差：大表上阻塞写
CREATE INDEX idx_users_email ON users (email);

-- 好：非阻塞，允许并发写
CREATE INDEX CONCURRENTLY idx_users_email ON users (email);

-- 注意：CONCURRENTLY 不能运行在事务块内
-- 大多数迁移工具都需要对此做特殊处理
```

### 重命名列（零停机）

绝不在生产环境直接重命名。使用 expand-contract 模式：

```sql
-- 步骤 1：添加新列（迁移 001）
ALTER TABLE users ADD COLUMN display_name TEXT;

-- 步骤 2：回填数据（迁移 002，数据迁移）
UPDATE users SET display_name = username WHERE display_name IS NULL;

-- 步骤 3：更新应用代码，同时读写两列
-- 部署应用变更

-- 步骤 4：停止写入旧列，删除它（迁移 003）
ALTER TABLE users DROP COLUMN username;
```

### 安全地删除列

```sql
-- 步骤 1：移除应用对该列的所有引用
-- 步骤 2：部署不含该列引用的应用版本
-- 步骤 3：在下一个迁移中删除列
ALTER TABLE orders DROP COLUMN legacy_status;

-- Django：用 SeparateDatabaseAndState 先把字段从模型移除
-- 而不生成 DROP COLUMN（再在下一次迁移里真正删列）
```

### 大规模数据迁移

```sql
-- 差：一个事务内更新所有行（锁表）
UPDATE users SET normalized_email = LOWER(email);

-- 好：分批更新带进度
DO $$
DECLARE
  batch_size INT := 10000;
  rows_updated INT;
BEGIN
  LOOP
    UPDATE users
    SET normalized_email = LOWER(email)
    WHERE id IN (
      SELECT id FROM users
      WHERE normalized_email IS NULL
      LIMIT batch_size
      FOR UPDATE SKIP LOCKED
    );
    GET DIAGNOSTICS rows_updated = ROW_COUNT;
    RAISE NOTICE 'Updated % rows', rows_updated;
    EXIT WHEN rows_updated = 0;
    COMMIT;
  END LOOP;
END $$;
```

## Prisma（TypeScript / Node.js）

### 工作流

```bash
# 从 schema 变更生成迁移
npx prisma migrate dev --name add_user_avatar

# 在生产环境应用待执行迁移
npx prisma migrate deploy

# 重置数据库（仅限开发环境）
npx prisma migrate reset

# Schema 变更后重新生成客户端
npx prisma generate
```

### Schema 示例

```prisma
model User {
  id        String   @id @default(cuid())
  email     String   @unique
  name      String?
  avatarUrl String?  @map("avatar_url")
  createdAt DateTime @default(now()) @map("created_at")
  updatedAt DateTime @updatedAt @map("updated_at")
  orders    Order[]

  @@map("users")
  @@index([email])
}
```

### 自定义 SQL 迁移

当 Prisma 无法表达的操作（并发索引、数据回填）：

```bash
# 创建空迁移，再手工编辑 SQL
npx prisma migrate dev --create-only --name add_email_index
```

```sql
-- migrations/20240115_add_email_index/migration.sql
-- Prisma 无法生成 CONCURRENTLY，手动写
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_email ON users (email);
```

## Drizzle（TypeScript / Node.js）

### 工作流

```bash
# 从 schema 变更生成迁移
npx drizzle-kit generate

# 应用迁移
npx drizzle-kit migrate

# 直接推送 schema（仅开发环境，不产生迁移文件）
npx drizzle-kit push
```

### Schema 示例

```typescript
import { pgTable, text, timestamp, uuid, boolean } from "drizzle-orm/pg-core";

export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  email: text("email").notNull().unique(),
  name: text("name"),
  isActive: boolean("is_active").notNull().default(true),
  createdAt: timestamp("created_at").notNull().defaultNow(),
  updatedAt: timestamp("updated_at").notNull().defaultNow(),
});
```

## Kysely（TypeScript / Node.js）

### 工作流（kysely-ctl）

```bash
# 初始化配置文件（kysely.config.ts）
kysely init

# 创建新迁移文件
kysely migrate make add_user_avatar

# 应用所有待执行迁移
kysely migrate latest

# 回滚上一个迁移
kysely migrate down

# 查看迁移状态
kysely migrate list
```

### 迁移文件

```typescript
// migrations/2024_01_15_001_create_user_profile.ts
import { type Kysely, sql } from 'kysely'

// 重要：始终使用 Kysely<any>，而不是你的带类型 DB 接口。
// 迁移是时间冻结的快照，不能依赖当前 schema 的类型。
export async function up(db: Kysely<any>): Promise<void> {
  await db.schema
    .createTable('user_profile')
    .addColumn('id', 'serial', (col) => col.primaryKey())
    .addColumn('email', 'varchar(255)', (col) => col.notNull().unique())
    .addColumn('avatar_url', 'text')
    .addColumn('created_at', 'timestamp', (col) =>
      col.defaultTo(sql`now()`).notNull()
    )
    .execute()

  await db.schema
    .createIndex('idx_user_profile_avatar')
    .on('user_profile')
    .column('avatar_url')
    .execute()
}

export async function down(db: Kysely<any>): Promise<void> {
  await db.schema.dropTable('user_profile').execute()
}
```

### 编程式 Migrator

```typescript
import { Migrator, FileMigrationProvider } from 'kysely'
import { promises as fs } from 'fs'
import * as path from 'path'
// 仅 ESM 需要 —— CJS 可直接用 __dirname
import { fileURLToPath } from 'url'
const migrationFolder = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  './migrations',
)

// `db` 是你的 Kysely<any> 数据库实例
const migrator = new Migrator({
  db,
  provider: new FileMigrationProvider({
    fs,
    path,
    migrationFolder,
  }),
  // 警告：仅在开发环境启用。关闭时间戳顺序校验，
  // 可能导致不同环境间的 schema 漂移。
  // allowUnorderedMigrations: true,
})

const { error, results } = await migrator.migrateToLatest()

results?.forEach((it) => {
  if (it.status === 'Success') {
    console.log(`migration "${it.migrationName}" executed successfully`)
  } else if (it.status === 'Error') {
    console.error(`failed to execute migration "${it.migrationName}"`)
  }
})

if (error) {
  console.error('migration failed', error)
  process.exit(1)
}
```

## Django（Python）

### 工作流

```bash
# 从 model 变更生成迁移
python manage.py makemigrations

# 应用迁移
python manage.py migrate

# 查看迁移状态
python manage.py showmigrations

# 生成空迁移，用于自定义 SQL
python manage.py makemigrations --empty app_name -n description
```

### 数据迁移

```python
from django.db import migrations

def backfill_display_names(apps, schema_editor):
    User = apps.get_model("accounts", "User")
    batch_size = 5000
    users = User.objects.filter(display_name="")
    while users.exists():
        batch = list(users[:batch_size])
        for user in batch:
            user.display_name = user.username
        User.objects.bulk_update(batch, ["display_name"], batch_size=batch_size)

def reverse_backfill(apps, schema_editor):
    pass  # 数据迁移，无需反向

class Migration(migrations.Migration):
    dependencies = [("accounts", "0015_add_display_name")]

    operations = [
        migrations.RunPython(backfill_display_names, reverse_backfill),
    ]
```

### SeparateDatabaseAndState

从 Django model 移除字段，但暂不真正删除数据库列：

```python
class Migration(migrations.Migration):
    operations = [
        migrations.SeparateDatabaseAndState(
            state_operations=[
                migrations.RemoveField(model_name="user", name="legacy_field"),
            ],
            database_operations=[],  # 暂不动数据库
        ),
    ]
```

## golang-migrate（Go）

### 工作流

```bash
# 创建迁移对（up + down）
migrate create -ext sql -dir migrations -seq add_user_avatar

# 应用所有待执行迁移
migrate -path migrations -database "$DATABASE_URL" up

# 回滚上一个迁移
migrate -path migrations -database "$DATABASE_URL" down 1

# 强制指定版本（修复 dirty 状态）
migrate -path migrations -database "$DATABASE_URL" force VERSION
```

### 迁移文件

```sql
-- migrations/000003_add_user_avatar.up.sql
ALTER TABLE users ADD COLUMN avatar_url TEXT;
CREATE INDEX CONCURRENTLY idx_users_avatar ON users (avatar_url) WHERE avatar_url IS NOT NULL;

-- migrations/000003_add_user_avatar.down.sql
DROP INDEX IF EXISTS idx_users_avatar;
ALTER TABLE users DROP COLUMN IF EXISTS avatar_url;
```

## 零停机迁移策略

关键生产变更遵循 expand-contract 模式：

```
阶段 1：EXPAND（扩展）
  - 添加新列 / 表（可空或带默认值）
  - 部署：应用同时写入新旧两边
  - 回填存量数据

阶段 2：MIGRATE（迁移）
  - 部署：应用从新列读，同时写入新旧两边
  - 验证数据一致性

阶段 3：CONTRACT（收缩）
  - 部署：应用只使用新列
  - 在独立迁移中删除旧列 / 表
```

### 时间线示例

```
第 1 天：迁移添加 new_status 列（可空）
第 1 天：部署应用 v2 —— 同时写入 status 和 new_status
第 2 天：运行回填迁移处理存量行
第 3 天：部署应用 v3 —— 只从 new_status 读
第 7 天：迁移删除旧的 status 列
```

## 反模式

| 反模式 | 失败原因 | 更好的做法 |
|--------|---------|-----------|
| 在生产环境手工跑 SQL | 无审计、不可复现 | 始终用迁移文件 |
| 编辑已部署的迁移 | 导致环境间漂移 | 改为创建新的迁移 |
| NOT NULL 无默认值 | 锁表、重写所有行 | 先加可空列、回填、再加约束 |
| 大表内联索引 | 构建期间阻塞写 | CREATE INDEX CONCURRENTLY |
| Schema + 数据同一迁移 | 回滚困难、事务过长 | 拆成多个迁移 |
| 先删列再改代码 | 应用访问缺失列报错 | 先改代码，下次部署再删列 |
