---
name: projects
description: 列出已知项目及其 instinct 统计信息
command: true
---

# Projects 命令

列出 continuous-learning-v2 的项目登记表，以及每个项目的 instinct / observation 计数。

## 实现

使用 plugin 根路径调用 instinct CLI：

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/continuous-learning-v2/scripts/instinct-cli.py" projects
```

或在未设置 `CLAUDE_PLUGIN_ROOT`（手动安装）时：

```bash
python3 ~/.claude/skills/continuous-learning-v2/scripts/instinct-cli.py projects
```

## 用法

```bash
/projects
```

## 执行步骤

1. 读取 `~/.claude/homunculus/projects.json`
2. 对每个项目，展示：
   - 项目名称、id、根路径、remote
   - 个人 instinct 与继承 instinct 的数量
   - observation 事件总数
   - 最近一次出现的时间戳
3. 另外展示全局 instinct 汇总
