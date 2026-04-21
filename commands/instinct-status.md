---
name: instinct-status
description: 展示已学习到的 instinct（项目 + 全局）及其置信度
command: true
---

# Instinct Status 命令

展示当前项目已学习的 instinct，外加全局 instinct，按领域（domain）分组。

## 实现

使用 plugin 根路径调用 instinct CLI：

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/continuous-learning-v2/scripts/instinct-cli.py" status
```

或在未设置 `CLAUDE_PLUGIN_ROOT`（手动安装）时：

```bash
python3 ~/.claude/skills/continuous-learning-v2/scripts/instinct-cli.py status
```

## 用法

```
/instinct-status
```

## 执行步骤

1. 检测当前项目上下文（基于 git remote 或路径 hash）
2. 从 `~/.claude/homunculus/projects/<project-id>/instincts/` 读取项目级 instinct
3. 从 `~/.claude/homunculus/instincts/` 读取全局 instinct
4. 按优先级合并（当 ID 冲突时，项目级覆盖全局级）
5. 按 domain 分组展示，附置信度条和观测数统计

## 输出格式

```
============================================================
  INSTINCT STATUS - 12 total
============================================================

  Project: my-app (a1b2c3d4e5f6)
  Project instincts: 8
  Global instincts:  4

## PROJECT-SCOPED (my-app)
  ### WORKFLOW (3)
    ███████░░░  70%  grep-before-edit [project]
              trigger: when modifying code

## GLOBAL (apply to all projects)
  ### SECURITY (2)
    █████████░  85%  validate-user-input [global]
              trigger: when handling user input
```
