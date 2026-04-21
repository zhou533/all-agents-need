---
name: promote
description: 将项目作用域的 instinct 晋升到全局作用域
command: true
---

# Promote 命令

在 continuous-learning-v2 中，将 instinct 从项目作用域晋升到全局作用域。

## 实现

使用 plugin 根路径调用 instinct CLI：

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/continuous-learning-v2/scripts/instinct-cli.py" promote [instinct-id] [--force] [--dry-run]
```

或在未设置 `CLAUDE_PLUGIN_ROOT`（手动安装）时：

```bash
python3 ~/.claude/skills/continuous-learning-v2/scripts/instinct-cli.py promote [instinct-id] [--force] [--dry-run]
```

## 用法

```bash
/promote                      # 自动识别可晋升的候选 instinct
/promote --dry-run            # 预览自动晋升的候选，但不写入
/promote --force              # 无需确认，直接晋升所有合格候选
/promote grep-before-edit     # 从当前项目中挑出指定 instinct 晋升
```

## 执行步骤

1. 检测当前项目
2. 如果传入了 `instinct-id`，仅晋升该 instinct（前提是它存在于当前项目）
3. 否则，查找满足以下条件的跨项目候选：
   - 至少出现在 2 个项目中
   - 达到置信度阈值
4. 将晋升后的 instinct 写入 `~/.claude/homunculus/instincts/personal/`，并将 `scope` 字段置为 `global`
