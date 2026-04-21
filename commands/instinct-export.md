---
name: instinct-export
description: 将项目/全局作用域的 instinct 导出到文件
command: /instinct-export
---

# Instinct Export 命令

将 instinct 导出为可分享的格式。适用于：
- 与团队成员共享
- 迁移到新机器
- 贡献到项目约定

## 用法

```
/instinct-export                           # 导出全部个人 instinct
/instinct-export --domain testing          # 仅导出 testing 领域的 instinct
/instinct-export --min-confidence 0.7      # 仅导出高置信度 instinct
/instinct-export --output team-instincts.yaml
/instinct-export --scope project --output project-instincts.yaml
```

## 执行步骤

1. 检测当前项目上下文
2. 按选定作用域加载 instinct：
   - `project`：仅当前项目
   - `global`：仅全局
   - `all`：项目 + 全局合并（默认）
3. 应用筛选条件（`--domain`、`--min-confidence`）
4. 将 YAML 风格的导出写入文件（若未提供输出路径，则打印到 stdout）

## 输出格式

生成一份 YAML 文件：

```yaml
# Instincts Export
# Generated: 2025-01-22
# Source: personal
# Count: 12 instincts

---
id: prefer-functional-style
trigger: "when writing new functions"
confidence: 0.8
domain: code-style
source: session-observation
scope: project
project_id: a1b2c3d4e5f6
project_name: my-app
---

# Prefer Functional Style

## Action
Use functional patterns over classes.
```

## 参数

- `--domain <name>`：仅导出指定 domain
- `--min-confidence <n>`：置信度下限
- `--output <file>`：输出文件路径（省略时打印到 stdout）
- `--scope <project|global|all>`：导出作用域（默认 `all`）
