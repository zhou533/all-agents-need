---
name: continuous-learning-v2
description: 基于本能（instinct）的学习系统，通过钩子观测会话，创建带置信度的原子本能，并将其演化为 skill / command / agent。v2.1 新增项目级本能作用域，避免跨项目污染。
origin: AAN
version: 2.1.0
---

# 持续学习 v2.1 —— 基于本能的架构

一套进阶的学习系统，通过原子化的"本能"（带置信度的细颗粒学习行为），把你的 Claude Code 会话沉淀为可复用的知识。

**v2.1** 引入了**项目级本能作用域** —— React 模式留在你的 React 项目里，Python 约定留在你的 Python 项目里，而通用模式（例如"始终校验输入"）则在全局共享。

## 何时启用

- 配置 Claude Code 会话的自动学习
- 通过钩子配置基于本能的行为抽取
- 调整学习行为的置信度阈值
- 复查、导出或导入本能库
- 将本能演化为完整的 skill、command 或 agent
- 管理项目级与全局本能
- 把本能从项目级提升到全局级

## v2.1 新增内容

| 特性 | v2.0 | v2.1 |
|------|------|------|
| 存储位置 | 全局（~/.claude/homunculus/） | 项目级（projects/<hash>/） |
| 作用域 | 所有本能全局生效 | 项目级 + 全局 |
| 项目识别 | 无 | git remote URL / 仓库路径 |
| 提升机制 | 无 | 在 2 个及以上项目中出现时，从项目级提升到全局 |
| 命令 | 4 个（status / evolve / export / import） | 6 个（新增 promote / projects） |
| 跨项目 | 存在污染风险 | 默认隔离 |

## v2 相对 v1 的改动

| 特性 | v1 | v2 |
|------|----|----|
| 观测方式 | Stop 钩子（会话结束时） | PreToolUse / PostToolUse（100% 可靠） |
| 分析时机 | 主上下文中分析 | 后台 agent（Haiku） |
| 颗粒度 | 完整 skill | 原子化"本能" |
| 置信度 | 无 | 0.3 - 0.9 加权 |
| 演化路径 | 直接生成 skill | 本能 → 聚类 → skill / command / agent |
| 共享 | 无 | 本能可导出 / 导入 |

## 本能模型

一个本能就是一段细小的学习行为：

```yaml
---
id: prefer-functional-style
trigger: "when writing new functions"
confidence: 0.7
domain: "code-style"
source: "session-observation"
scope: project
project_id: "a1b2c3d4e5f6"
project_name: "my-react-app"
---

# Prefer Functional Style

## Action
Use functional patterns over classes when appropriate.

## Evidence
- Observed 5 instances of functional pattern preference
- User corrected class-based approach to functional on 2025-01-15
```

**关键属性：**
- **原子化** —— 一个触发器对应一个动作
- **置信度加权** —— 0.3 表示尝试性，0.9 表示几乎确定
- **领域标签** —— code-style、testing、git、debugging、workflow 等
- **证据支撑** —— 记录创建该本能的观测来源
- **作用域感知** —— `project`（默认）或 `global`

## 工作原理

```
会话活动（位于 git 仓库中）
      |
      | 钩子捕获 prompt + 工具调用（100% 可靠）
      | + 探测项目上下文（git remote / 仓库路径）
      v
+---------------------------------------------+
|  projects/<project-hash>/observations.jsonl  |
|   （prompts、工具调用、结果、所属项目）       |
+---------------------------------------------+
      |
      | 观测 agent 读取（后台、Haiku）
      v
+---------------------------------------------+
|              模式识别                         |
|   * 用户纠正 -> 本能                          |
|   * 错误处置 -> 本能                          |
|   * 重复工作流 -> 本能                        |
|   * 作用域判断：项目级 还是 全局？            |
+---------------------------------------------+
      |
      | 创建 / 更新
      v
+---------------------------------------------+
|  projects/<project-hash>/instincts/personal/ |
|   * prefer-functional.yaml (0.7) [project]   |
|   * use-react-hooks.yaml (0.9) [project]     |
+---------------------------------------------+
|  instincts/personal/  （全局）                |
|   * always-validate-input.yaml (0.85) [global]|
|   * grep-before-edit.yaml (0.6) [global]     |
+---------------------------------------------+
      |
      | /evolve 聚类 + /promote 提升
      v
+---------------------------------------------+
|  projects/<hash>/evolved/ （项目级）          |
|  evolved/ （全局）                            |
|   * commands/new-feature.md                  |
|   * skills/testing-workflow.md               |
|   * agents/refactor-specialist.md            |
+---------------------------------------------+
```

## 项目识别

系统会自动识别你当前所处的项目：

1. **`CLAUDE_PROJECT_DIR` 环境变量**（最高优先级）
2. **`git remote get-url origin`** —— 经过哈希后生成可移植的项目 ID（同一仓库在不同机器上得到的 ID 相同）
3. **`git rev-parse --show-toplevel`** —— 回退方案，使用仓库路径（与机器相关）
4. **全局回退** —— 若无法识别项目，本能进入全局作用域

每个项目会得到一个 12 位字符的哈希 ID（例如 `a1b2c3d4e5f6`）。`~/.claude/homunculus/projects.json` 注册表负责把 ID 映射回可读的项目名称。

## 快速上手

### 1. 启用观测钩子

将以下配置加入 `~/.claude/settings.json`。

**作为插件安装时**（推荐方式）：

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/skills/continuous-learning-v2/hooks/observe.sh"
      }]
    }],
    "PostToolUse": [{
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/skills/continuous-learning-v2/hooks/observe.sh"
      }]
    }]
  }
}
```

**手动安装到 `~/.claude/skills` 时**：

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": "~/.claude/skills/continuous-learning-v2/hooks/observe.sh"
      }]
    }],
    "PostToolUse": [{
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": "~/.claude/skills/continuous-learning-v2/hooks/observe.sh"
      }]
    }]
  }
}
```

### 2. 初始化目录结构

系统会在首次使用时自动创建目录，你也可以手动创建：

```bash
# 全局目录
mkdir -p ~/.claude/homunculus/{instincts/{personal,inherited},evolved/{agents,skills,commands},projects}

# 项目级目录会在钩子首次在 git 仓库中运行时自动创建
```

### 3. 使用本能命令

```bash
/instinct-status     # 显示已学习的本能（项目级 + 全局）
/evolve              # 将相关本能聚类为 skill / command
/instinct-export     # 将本能导出到文件
/instinct-import     # 导入他人分享的本能
/promote             # 将项目级本能提升为全局
/projects            # 列出所有已知项目及其本能数量
```

## 命令一览

| 命令 | 说明 |
|------|------|
| `/instinct-status` | 展示所有本能（项目级 + 全局）及其置信度 |
| `/evolve` | 将相关本能聚类为 skill / command，并给出提升建议 |
| `/instinct-export` | 导出本能（支持按作用域 / 领域过滤） |
| `/instinct-import <file>` | 导入本能并控制作用域 |
| `/promote [id]` | 将项目级本能提升为全局 |
| `/projects` | 列出所有已知项目及其本能数量 |

## 配置项

编辑 `config.json` 以控制后台观测器：

```json
{
  "version": "2.1",
  "observer": {
    "enabled": false,
    "run_interval_minutes": 5,
    "min_observations_to_analyze": 20
  }
}
```

| 键 | 默认值 | 说明 |
|----|--------|------|
| `observer.enabled` | `false` | 是否启用后台观测 agent |
| `observer.run_interval_minutes` | `5` | 观测器分析观测数据的频率 |
| `observer.min_observations_to_analyze` | `20` | 触发分析所需的最小观测数 |

其它行为（观测捕获、本能阈值、项目作用域、提升标准等）通过 `instinct-cli.py` 与 `observe.sh` 中的代码默认值进行配置。

## 文件结构

```
~/.claude/homunculus/
+-- identity.json           # 你的画像与技术等级
+-- projects.json           # 注册表：项目哈希 -> 名称 / 路径 / remote
+-- observations.jsonl      # 全局观测（兜底）
+-- instincts/
|   +-- personal/           # 全局自学本能
|   +-- inherited/          # 全局导入本能
+-- evolved/
|   +-- agents/             # 全局生成的 agent
|   +-- skills/             # 全局生成的 skill
|   +-- commands/           # 全局生成的 command
+-- projects/
    +-- a1b2c3d4e5f6/       # 项目哈希（基于 git remote URL）
    |   +-- project.json    # 项目级元数据镜像（id / 名称 / 根路径 / remote）
    |   +-- observations.jsonl
    |   +-- observations.archive/
    |   +-- instincts/
    |   |   +-- personal/   # 项目级自学本能
    |   |   +-- inherited/  # 项目级导入本能
    |   +-- evolved/
    |       +-- skills/
    |       +-- commands/
    |       +-- agents/
    +-- f6e5d4c3b2a1/       # 另一个项目
        +-- ...
```

## 作用域决策指南

| 模式类型 | 作用域 | 示例 |
|----------|--------|------|
| 语言 / 框架约定 | **项目级** | "使用 React Hooks"、"遵循 Django REST 模式" |
| 文件结构偏好 | **项目级** | "测试放在 `__tests__/`"、"组件放在 `src/components/`" |
| 代码风格 | **项目级** | "使用函数式风格"、"优先使用 dataclass" |
| 错误处理策略 | **项目级** | "用 Result 类型表达错误" |
| 安全实践 | **全局** | "校验用户输入"、"清理 SQL" |
| 通用最佳实践 | **全局** | "先写测试"、"始终处理错误" |
| 工具工作流偏好 | **全局** | "Edit 前先 Grep"、"Write 前先 Read" |
| Git 习惯 | **全局** | "Conventional Commits"、"小而聚焦的提交" |

## 本能提升（项目级 -> 全局）

当同一个本能在多个项目中以高置信度反复出现时，它就成为提升到全局的候选。

**自动提升标准：**
- 同一本能 ID 出现在 2 个及以上项目中
- 平均置信度 >= 0.8

**提升方式：**

```bash
# 提升指定本能
python3 instinct-cli.py promote prefer-explicit-errors

# 自动提升所有符合条件的本能
python3 instinct-cli.py promote

# 仅预览，不实际改动
python3 instinct-cli.py promote --dry-run
```

`/evolve` 命令也会给出提升候选建议。

## 置信度评分

置信度会随时间演变：

| 分值 | 含义 | 行为表现 |
|------|------|----------|
| 0.3 | 尝试性 | 仅作建议，不强制执行 |
| 0.5 | 中等 | 在相关场景下应用 |
| 0.7 | 强 | 自动批准应用 |
| 0.9 | 几乎确定 | 视为核心行为 |

**置信度上升**的情形：
- 同一模式被反复观察到
- 用户没有纠正所建议的行为
- 来自其它来源的相似本能相互印证

**置信度下降**的情形：
- 用户明确纠正了该行为
- 长时间未再观察到该模式
- 出现了相反的证据

## 为什么观测用钩子而不是 skill？

> "v1 relied on skills to observe. Skills are probabilistic -- they fire ~50-80% of the time based on Claude's judgment."
>
> （译文："v1 依赖 skill 进行观测。skill 是概率性的 —— 它们大约只有 50-80% 的概率被 Claude 自行判断触发。"）

钩子则是**100% 触发**的，确定性执行。这意味着：
- 每一次工具调用都会被观测到
- 不会漏掉任何模式
- 学习更加完整全面

## 向后兼容

v2.1 完全兼容 v2.0 与 v1：
- 已有的全局本能（`~/.claude/homunculus/instincts/`）继续作为全局本能生效
- v1 中已有的 `~/.claude/skills/learned/` skill 仍然可用
- Stop 钩子仍会运行（同时也会向 v2 输入数据）
- 支持渐进迁移：两套体系可并行运行

## 隐私

- 观测数据**仅保存在本机**
- 项目级本能在各项目之间是隔离的
- 只有**本能**（即模式）可以导出，原始观测不会外发
- 不会共享任何实际代码或对话内容
- 由你自行掌控导出与提升的内容

## 相关链接

- [ECC-Tools GitHub App](https://github.com/apps/ecc-tools) —— 从仓库历史生成本能
- Homunculus —— 启发了 v2 基于本能的架构（原子化观测、置信度评分、本能演化流水线）的社区项目
- [The Longform Guide](https://x.com/affaanmustafa/status/2014040193557471352) —— 持续学习相关章节

---

*基于本能的学习：以一个项目为单位，把你的模式教给 Claude。*
