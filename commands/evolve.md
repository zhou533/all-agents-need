---
name: evolve
description: 分析 instinct，建议或生成演化出的更高层结构
command: true
---

# Evolve 命令

## 实现

使用 plugin 根路径调用 instinct CLI：

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/continuous-learning-v2/scripts/instinct-cli.py" evolve [--generate]
```

或在未设置 `CLAUDE_PLUGIN_ROOT`（手动安装）时：

```bash
python3 ~/.claude/skills/continuous-learning-v2/scripts/instinct-cli.py evolve [--generate]
```

分析 instinct 并将相关项聚合为更高层结构：
- **命令（Commands）**：当 instinct 描述用户显式触发的动作时
- **技能（Skills）**：当 instinct 描述自动触发的行为时
- **代理（Agents）**：当 instinct 描述复杂、多步流程时

## 用法

```
/evolve                    # 分析全部 instinct，给出演化建议
/evolve --generate         # 同时在 evolved/{skills,commands,agents} 下生成文件
```

## 演化规则

### → Command（用户触发）
当 instinct 描述用户会显式请求的动作时：
- 多个 instinct 都以"when user asks to…"形式出现
- 触发器形如"when creating a new X"
- instinct 串联成可重复的流程

示例：
- `new-table-step1`："when adding a database table, create migration"
- `new-table-step2`："when adding a database table, update schema"
- `new-table-step3`："when adding a database table, regenerate types"

→ 生成：**new-table** 命令

### → Skill（自动触发）
当 instinct 描述应自动发生的行为时：
- 基于模式匹配的触发器
- 错误处理响应
- 代码风格强制

示例：
- `prefer-functional`："when writing functions, prefer functional style"
- `use-immutable`："when modifying state, use immutable patterns"
- `avoid-classes`："when designing modules, avoid class-based design"

→ 生成：`functional-patterns` 技能

### → Agent（需要深度/隔离）
当 instinct 描述受益于隔离执行的复杂多步流程时：
- 调试工作流
- 重构序列
- 研究任务

示例：
- `debug-step1`："when debugging, first check logs"
- `debug-step2`："when debugging, isolate the failing component"
- `debug-step3`："when debugging, create minimal reproduction"
- `debug-step4`："when debugging, verify fix with test"

→ 生成：**debugger** agent

## 执行步骤

1. 检测当前项目上下文
2. 读取项目 + 全局 instinct（ID 冲突时项目级优先）
3. 按触发器/领域模式分组 instinct
4. 识别：
   - 技能候选（2 个以上 instinct 的触发器聚类）
   - 命令候选（高置信度的工作流 instinct）
   - 代理候选（更大的、高置信度的聚类）
5. 适用时展示晋升候选（project → global）
6. 若传入 `--generate`，将文件写入：
   - 项目作用域：`~/.claude/homunculus/projects/<project-id>/evolved/`
   - 全局回退：`~/.claude/homunculus/evolved/`

## 输出格式

```
============================================================
  EVOLVE ANALYSIS - 12 instincts
  Project: my-app (a1b2c3d4e5f6)
  Project-scoped: 8 | Global: 4
============================================================

High confidence instincts (>=80%): 5

## SKILL CANDIDATES
1. Cluster: "adding tests"
   Instincts: 3
   Avg confidence: 82%
   Domains: testing
   Scopes: project

## COMMAND CANDIDATES (2)
  /adding-tests
    From: test-first-workflow [project]
    Confidence: 84%

## AGENT CANDIDATES (1)
  adding-tests-agent
    Covers 3 instincts
    Avg confidence: 82%
```

## 参数

- `--generate`：除分析输出外，另外生成 evolved 文件

## 生成文件格式

### Command
```markdown
---
name: new-table
description: Create a new database table with migration, schema update, and type generation
command: /new-table
evolved_from:
  - new-table-migration
  - update-schema
  - regenerate-types
---

# New Table Command

[Generated content based on clustered instincts]

## Steps
1. ...
2. ...
```

### Skill
```markdown
---
name: functional-patterns
description: Enforce functional programming patterns
evolved_from:
  - prefer-functional
  - use-immutable
  - avoid-classes
---

# Functional Patterns Skill

[Generated content based on clustered instincts]
```

### Agent
```markdown
---
name: debugger
description: Systematic debugging agent
model: sonnet
evolved_from:
  - debug-check-logs
  - debug-isolate
  - debug-reproduce
---

# Debugger Agent

[Generated content based on clustered instincts]
```
