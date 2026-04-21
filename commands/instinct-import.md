---
name: instinct-import
description: 从文件或 URL 导入 instinct 到项目/全局作用域
command: true
---

# Instinct Import 命令

## 实现

使用 plugin 根路径调用 instinct CLI：

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/continuous-learning-v2/scripts/instinct-cli.py" import <file-or-url> [--dry-run] [--force] [--min-confidence 0.7] [--scope project|global]
```

或在未设置 `CLAUDE_PLUGIN_ROOT`（手动安装）时：

```bash
python3 ~/.claude/skills/continuous-learning-v2/scripts/instinct-cli.py import <file-or-url>
```

从本地文件路径或 HTTP(S) URL 导入 instinct。

## 用法

```
/instinct-import team-instincts.yaml
/instinct-import https://github.com/org/repo/instincts.yaml
/instinct-import team-instincts.yaml --dry-run
/instinct-import team-instincts.yaml --scope global --force
```

## 执行步骤

1. 获取 instinct 文件（本地路径或 URL）
2. 解析并校验格式
3. 与既有 instinct 进行重复检测
4. 合并或新增 instinct
5. 保存到继承 instinct 目录：
   - 项目作用域：`~/.claude/homunculus/projects/<project-id>/instincts/inherited/`
   - 全局作用域：`~/.claude/homunculus/instincts/inherited/`

## 导入过程

```
 Importing instincts from: team-instincts.yaml
================================================

Found 12 instincts to import.

Analyzing conflicts...

## New Instincts (8)
These will be added:
  ✓ use-zod-validation (confidence: 0.7)
  ✓ prefer-named-exports (confidence: 0.65)
  ✓ test-async-functions (confidence: 0.8)
  ...

## Duplicate Instincts (3)
Already have similar instincts:
  WARNING: prefer-functional-style
     Local: 0.8 confidence, 12 observations
     Import: 0.7 confidence
     → Keep local (higher confidence)

  WARNING: test-first-workflow
     Local: 0.75 confidence
     Import: 0.9 confidence
     → Update to import (higher confidence)

Import 8 new, update 1?
```

## 合并行为

当导入的 instinct 与现有 ID 冲突时：
- 置信度更高的导入项成为更新候选
- 置信度相等或更低的导入项被跳过
- 除非使用 `--force`，否则需要用户确认

## 来源追踪

导入的 instinct 会被标记为：
```yaml
source: inherited
scope: project
imported_from: "team-instincts.yaml"
project_id: "a1b2c3d4e5f6"
project_name: "my-project"
```

## 参数

- `--dry-run`：仅预览，不实际导入
- `--force`：跳过确认提示
- `--min-confidence <n>`：仅导入置信度高于阈值的 instinct
- `--scope <project|global>`：目标作用域（默认 `project`）

## 输出

导入完成后：
```
PASS: Import complete!

Added: 8 instincts
Updated: 1 instinct
Skipped: 3 instincts (equal/higher confidence already exists)

New instincts saved to: ~/.claude/homunculus/instincts/inherited/

Run /instinct-status to see all instincts.
```
