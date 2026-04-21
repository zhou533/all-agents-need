---
description: 创建完备的功能实施计划，包含代码库分析与模式提取
argument-hint: <feature description | path/to/prd.md>
---

> 改编自 Wirasm 的 PRPs-agentic-eng。属于 PRP 工作流系列的一部分。

# PRP Plan

生成一份详尽、自洽的实施计划，捕获实现某功能所需的全部代码库模式、约定与上下文，目标是一次性跑完整个实施。

**核心理念**：好的 plan 包含实施阶段无需再问的一切。每一种模式、每一条约定、每一个陷阱 —— 都被记录一次，贯穿始终。

**黄金法则**：如果实施时还需要去代码库搜索，那条知识**现在**就写进 plan。

---

## 阶段 0 —— DETECT

根据 `$ARGUMENTS` 判断输入类型：

| 输入模式 | 识别 | 动作 |
|---|---|---|
| 以 `.prd.md` 结尾的路径 | PRD 文件 | 解析 PRD，定位下一个 pending phase |
| 含 "Implementation Phases" 的 `.md` 路径 | 类 PRD 文档 | 解析 phases，找到下一个 pending |
| 其它文件路径 | 引用文件 | 读文件当上下文，按自由文本处理 |
| 自由文本 | 功能描述 | 直接进入阶段 1 |
| 空 / 空白 | 无输入 | 询问用户要规划什么功能 |

### PRD 解析（当输入是 PRD 时）

1. 使用 `cat "$PRD_PATH"` 读取 PRD 文件
2. 解析 **Implementation Phases** 段
3. 按状态查找 phase：
   - 寻找 `pending` 状态的 phase
   - 检查依赖链（某个 phase 可能依赖前置 phase 为 `complete`）
   - 选中**下一个可执行的 pending phase**
4. 从选中 phase 抽取：
   - Phase 名称与描述
   - 验收标准
   - 对前置 phase 的依赖
   - 范围说明或约束
5. 用该 phase 描述作为要规划的功能

如果没有剩余 pending phase，报告所有 phase 已完成。

---

## 阶段 1 —— PARSE

抽取并澄清功能需求。

### 功能理解

从输入（PRD phase 或自由描述）中识别：

- **What**：要构建什么（具体交付物）
- **Why**：为什么重要（用户价值）
- **Who**：谁使用（目标用户/系统）
- **Where**：落在代码库哪里

### 用户故事

格式：
```
As a [type of user],
I want [capability],
So that [benefit].
```

### 复杂度评估

| 级别 | 指标 | 典型范围 |
|---|---|---|
| **Small** | 单文件、隔离改动、无新依赖 | 1-3 文件，<100 行 |
| **Medium** | 多文件、沿用现有模式、新概念较少 | 3-10 文件，100-500 行 |
| **Large** | 跨切面关注点、新模式、外部集成 | 10+ 文件，500+ 行 |
| **XL** | 架构变更、新子系统、需要迁移 | 20+ 文件，考虑拆分 |

### 歧义闸门

若以下任一不明确，**停下并询问用户**再继续：

- 核心交付物含糊
- 成功标准未定义
- 存在多种合理解读
- 技术方案有重大未知

不要猜。问。基于假设的 plan 会在实施阶段崩溃。

---

## 阶段 2 —— EXPLORE

获取深度代码库情报。按下列类别直接在代码库搜索。

### 代码库搜索（8 个类别）

对每个类别，使用 grep、find、文件阅读搜索：

1. **相似实现** —— 查找与待规划功能相像的既有功能。留意类似的模式、端点、组件或模块。

2. **命名约定** —— 识别相关区域里文件、函数、变量、类、导出的命名风格。

3. **错误处理** —— 查找相似路径里错误如何捕获、传播、日志化、返回给用户。

4. **日志模式** —— 识别什么被记录、级别、格式。

5. **类型定义** —— 找相关的类型、接口、schema 及其组织方式。

6. **测试模式** —— 找相似功能如何测试：测试文件位置、命名、setup/teardown 模式、断言风格。

7. **配置** —— 找相关的配置文件、环境变量、特性开关。

8. **依赖** —— 识别相似功能使用的包、导入、内部模块。

### 代码库剖析（5 条轨迹）

阅读相关文件以追踪：

1. **入口点** —— 请求/动作如何进入系统并到达待修改区域？
2. **数据流** —— 数据如何在相关代码路径中流动？
3. **状态变更** —— 什么状态被修改，在哪里？
4. **契约** —— 必须遵守哪些接口、API、协议？
5. **模式** —— 使用了哪些架构模式（repository、service、controller 等）？

### 统一发现表

把发现合成一份参考：

| 类别 | 文件:行 | 模式 | 关键片段 |
|---|---|---|---|
| 命名 | `src/services/userService.ts:1-5` | camelCase services，PascalCase types | `export class UserService` |
| 错误 | `src/middleware/errorHandler.ts:10-25` | 自定义 AppError 类 | `throw new AppError(...)` |
| ... | ... | ... | ... |

---

## 阶段 3 —— RESEARCH

若功能涉及外部库、API 或不熟悉的技术：

1. 搜索官方文档
2. 找使用示例与最佳实践
3. 识别版本相关陷阱

每条发现按此格式：

```
KEY_INSIGHT: [你学到了什么]
APPLIES_TO: [影响 plan 的哪一部分]
GOTCHA: [任何警告或版本相关的坑]
```

若功能只涉及已掌握的内部模式，跳过本阶段并注明："No external research needed — feature uses established internal patterns."

---

## 阶段 4 —— DESIGN

### UX 变换（若适用）

记录前后用户体验：

**Before:**
```
┌─────────────────────────────┐
│  [当前用户体验]              │
│  展示现在的流程，            │
│  用户看到/做的事             │
└─────────────────────────────┘
```

**After:**
```
┌─────────────────────────────┐
│  [新的用户体验]              │
│  展示改进后的流程，          │
│  用户的变化                  │
└─────────────────────────────┘
```

### 交互变更

| 接触点 | Before | After | 备注 |
|---|---|---|---|
| ... | ... | ... | ... |

若是纯后端/内部变更无 UX 影响，注明："Internal change — no user-facing UX transformation."

---

## 阶段 5 —— ARCHITECT

### 策略设计

定义实施路径：

- **Approach**：高层策略（如"在现有 repository 模式基础上加新的 service 层"）
- **Alternatives Considered**：考虑过的其它方案及为何被拒
- **Scope**：明确边界 —— **会**构建什么
- **NOT Building**：明确列出范围外内容（防止实施时范围蔓延）

---

## 阶段 6 —— GENERATE

按下方模板生成完整 plan 文档，保存到 `.claude/PRPs/plans/{kebab-case-feature-name}.plan.md`。

若目录不存在则创建：
```bash
mkdir -p .claude/PRPs/plans
```

### Plan 模板

````markdown
# Plan: [Feature Name]

## Summary
[2-3 句概述]

## User Story
As a [user], I want [capability], so that [benefit].

## Problem → Solution
[当前状态] → [期望状态]

## Metadata
- **Complexity**: [Small | Medium | Large | XL]
- **Source PRD**: [路径 或 "N/A"]
- **PRD Phase**: [phase 名 或 "N/A"]
- **Estimated Files**: [数量]

---

## UX Design

### Before
[ASCII 图 或 "N/A — internal change"]

### After
[ASCII 图 或 "N/A — internal change"]

### Interaction Changes
| 接触点 | Before | After | 备注 |
|---|---|---|---|

---

## Mandatory Reading

实施前**必须**阅读的文件：

| 优先级 | 文件 | 行 | 原因 |
|---|---|---|---|
| P0（关键） | `path/to/file` | 1-50 | 要遵循的核心模式 |
| P1（重要） | `path/to/file` | 10-30 | 相关类型 |
| P2（参考） | `path/to/file` | 全部 | 相似实现 |

## External Documentation

| 主题 | 来源 | 要点 |
|---|---|---|
| ... | ... | ... |

---

## Patterns to Mirror

在代码库中发现的模式。严格照搬。

### NAMING_CONVENTION
// SOURCE: [file:lines]
[展示命名模式的实际代码片段]

### ERROR_HANDLING
// SOURCE: [file:lines]
[展示错误处理的实际代码片段]

### LOGGING_PATTERN
// SOURCE: [file:lines]
[展示日志的实际代码片段]

### REPOSITORY_PATTERN
// SOURCE: [file:lines]
[展示数据访问的实际代码片段]

### SERVICE_PATTERN
// SOURCE: [file:lines]
[展示服务层的实际代码片段]

### TEST_STRUCTURE
// SOURCE: [file:lines]
[展示测试结构的实际代码片段]

---

## Files to Change

| 文件 | 动作 | 理由 |
|---|---|---|
| `path/to/file.ts` | CREATE | 新功能的新 service |
| `path/to/existing.ts` | UPDATE | 增加一个方法 |

## NOT Building

- [明确范围外项 1]
- [明确范围外项 2]

---

## Step-by-Step Tasks

### Task 1: [Name]
- **ACTION**：[要做什么]
- **IMPLEMENT**：[要写的具体代码/逻辑]
- **MIRROR**：[要照搬 Patterns to Mirror 里的哪个模式]
- **IMPORTS**：[需要的 import]
- **GOTCHA**：[已知要避开的坑]
- **VALIDATE**：[如何验证此 task 正确]

### Task 2: [Name]
- **ACTION**：...
- **IMPLEMENT**：...
- **MIRROR**：...
- **IMPORTS**：...
- **GOTCHA**：...
- **VALIDATE**：...

[对所有任务继续……]

---

## Testing Strategy

### 单元测试

| 测试 | 输入 | 期望输出 | 边界情况? |
|---|---|---|---|
| ... | ... | ... | ... |

### 边界情况清单
- [ ] 空输入
- [ ] 最大尺寸输入
- [ ] 非法类型
- [ ] 并发访问
- [ ] 网络故障（若适用）
- [ ] 权限拒绝

---

## Validation Commands

### 静态分析
```bash
# 运行类型检查
[项目的 type-check 命令]
```
EXPECT：零类型错误

### 单元测试
```bash
# 运行受影响区域的测试
[项目的 test 命令]
```
EXPECT：全部通过

### 完整测试套件
```bash
# 运行全部测试
[项目的完整 test 命令]
```
EXPECT：无回归

### 数据库校验（若适用）
```bash
# 校验 schema/迁移
[项目的 db 命令]
```
EXPECT：schema 是最新

### 浏览器校验（若适用）
```bash
# 启动 dev 服务器并验证
[项目的 dev server 命令]
```
EXPECT：功能按设计运行

### 手动校验
- [ ] [逐步手动验证清单]

---

## Acceptance Criteria
- [ ] 所有任务完成
- [ ] 所有验证命令通过
- [ ] 测试已写并通过
- [ ] 无类型错误
- [ ] 无 lint 错误
- [ ] 匹配 UX 设计（若适用）

## Completion Checklist
- [ ] 代码遵循发现的模式
- [ ] 错误处理匹配代码库风格
- [ ] 日志遵循代码库约定
- [ ] 测试遵循测试模式
- [ ] 无硬编码值
- [ ] 文档已更新（若需要）
- [ ] 无不必要的范围扩张
- [ ] 自洽 —— 实施期间无需追问

## Risks
| 风险 | 可能性 | 影响 | 缓解 |
|---|---|---|---|
| ... | ... | ... | ... |

## Notes
[额外上下文、决策或观察]
````

---

## 输出

### 保存 plan

将生成的 plan 写入：
```
.claude/PRPs/plans/{kebab-case-feature-name}.plan.md
```

### 更新 PRD（若输入是 PRD）

若本 plan 来自某 PRD 的 phase：
1. 把该 phase 状态由 `pending` 改为 `in-progress`
2. 在该 phase 中加入 plan 文件路径作为引用

### 向用户汇报

```
## Plan Created

- **File**: .claude/PRPs/plans/{kebab-case-feature-name}.plan.md
- **Source PRD**: [路径 或 "N/A"]
- **Phase**: [phase 名 或 "standalone"]
- **Complexity**: [级别]
- **Scope**: [N files, M tasks]
- **Key Patterns**: [前 3 个发现的模式]
- **External Research**: [研究过的主题，或 "none needed"]
- **Risks**: [头号风险 或 "none identified"]
- **Confidence Score**: [1-10] —— 一次性实施成功的可能性

> 下一步：运行 `/prp-implement .claude/PRPs/plans/{name}.plan.md` 执行此 plan。
```

---

## 验证

定稿前，对照以下清单核验 plan：

### 上下文完备性
- [ ] 所有相关文件已发现并记录
- [ ] 命名约定已附示例
- [ ] 错误处理模式已记录
- [ ] 测试模式已识别
- [ ] 依赖已列出

### 实施就绪
- [ ] 每个任务都有 ACTION、IMPLEMENT、MIRROR 与 VALIDATE
- [ ] 没有任务需要额外代码库搜索
- [ ] Import 路径已指定
- [ ] 适用处已记录 GOTCHA

### 模式忠实度
- [ ] 代码片段是代码库真实例子（非虚构）
- [ ] SOURCE 引用指向真实文件与行号
- [ ] 模式覆盖命名、错误、日志、数据访问与测试
- [ ] 新代码将与既有代码难以区分

### 验证覆盖
- [ ] 已指定静态分析命令
- [ ] 已指定测试命令
- [ ] 已包含构建验证

### UX 清晰度
- [ ] 前/后状态已记录（或标注 N/A）
- [ ] 交互变更已列出
- [ ] 已识别 UX 边界情况

### "零先验知识"测试
一名不熟悉本代码库的开发者应能**仅凭**此 plan 完成实施，不必搜索代码库或追问。若不行，补上缺失的上下文。

---

## 下一步

- 运行 `/prp-implement <plan-path>` 执行此 plan
- 运行 `/plan` 进行不产出工件的快速对话式规划
- 若范围不清，运行 `/prp-prd` 先建立 PRD
