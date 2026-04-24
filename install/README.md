# Install

AAN 的安装入口目录。当前提供 Claude Code 和 Codex 的安装入口。

## 目录

```text
install/
  README.md
  manifests.json        # 模块化安装清单（schema v1）
  claude/
    install.sh          # 单脚本安装器
  codex/
    install-prompt.md   # 在 Codex 会话中加载的安装提示词
    install-agents.py   # agents/*.md -> .codex/agents/*.toml
    install-mcp-config.py
    install-verification.sh
```

## Claude Code 安装

`install/claude/install.sh` 是单脚本安装器，按模块选择把 AAN 资源安装到目标项目的 `.claude/` 目录（及项目根 `.mcp.json`）。

### 前置依赖

```bash
# macOS
brew install jq gum

# Linux
# jq  → https://jqlang.github.io/jq/download/
# gum → https://github.com/charmbracelet/gum#installation
```

缺失 `jq` 或 `gum` 时脚本会提示安装命令并退出，不做降级。

### 快速开始

```bash
# 1. 把 AAN 作为 submodule 加到目标项目根目录
git submodule add <repo-url> aan

# 2. 在目标项目根运行安装器
bash aan/install/claude/install.sh
```

交互流程：

1. 多选要安装的模块（`common` 模块为必装底座，自动加入）
2. 展示将要落盘的资源概览 → 确认
3. 自动落盘 skills / agents / commands / rules / output-styles 到 `.claude/`
4. 合并选中模块的 hooks 到 `.claude/settings.json`
5. 可选：多选要安装的 MCP（空格勾选，回车确认）
6. 输出安装摘要

### 模块说明

模块列表与依赖在 `install/manifests.json` 定义（schema v1）。当前包含：

- `common`：横向底座（api-design、coding-standards、tdd-workflow、code-review、security 等）
- `web` / `typescript` / `rust` / `golang` / `python`：各语言/前端全链路
- `database`：PostgreSQL + 迁移
- `mcp`：MCP server 开发
- `prp`：Plan-Review-Process 流水线
- `harness-ops`：harness 运维与 UX
- `continuous-learning`：持续学习与 instinct 系统

增加新模块只需改 `manifests.json`，`install.sh` 不用改。

### 产物位置

产物布局对齐 [Claude Code 官方 .claude 目录规范](https://code.claude.com/docs/en/claude-directory)：

- `<project>/.claude/skills/`、`agents/`、`commands/`、`rules/`、`output-styles/`：文件型资源
- `<project>/.claude/settings.json`：hooks 段 + `env.CLAUDE_PLUGIN_ROOT`
- `<project>/.claude/scripts/`：hooks 依赖的 node 引导脚本
- `<project>/.mcp.json`：所选 MCP 配置（若选了 MCP）

### 幂等与更新

- **文件型资源**：选中的直接覆盖；未选的保留（孤儿不清理，如需彻底重装请先 `rm -rf .claude/` 再跑）
- **settings.json 的 hooks 段**：以 AAN 的 `hooks/hooks.json` 中所有 id 作为 AAN 所有权边界；每次运行先清除旧 AAN id，再注入本次选中的；用户自己加的 hook id 不动
- **.mcp.json**：同上规则，按 MCP name 管理边界
- **备份**：原 `settings.json` / `.mcp.json` 自动备份为 `*.aan-backup-<时间戳>`

### MCP 占位符

`mcp-servers.json` 中某些 MCP（如 `github`、`jira`）包含 `YOUR_XXX_HERE` 占位符。脚本原样写入 `.mcp.json`，安装末尾会列出需要手填的 MCP 及占位符名。使用前请编辑 `.mcp.json` 填入真实凭据。

## Codex 安装

Codex 版采用“安装 prompt + 转换脚本 + 验证脚本”的方式，面向项目级安装。

### 快速开始

```bash
# 1. 把 AAN 作为 submodule 加到目标项目根目录
git submodule add <repo-url> all-agents-need
```

然后在 Codex 会话中加载：

- `all-agents-need/install/codex/install-prompt.md`

按提示完成模块选择、MCP 选择和安装确认。安装过程中会调用：

- `install/codex/install-agents.py`
- `install/codex/install-mcp-config.py`
- `install/codex/install-verification.sh`

### 安装范围

当前 Codex 版只安装：

- `skills`
- `agents`
- `mcp`
- AAN submodule 的硬边界

当前不安装：

- `hooks`
- `rules`
- `commands`

### 产物位置

- `<project>/.agents/skills/`
- `<project>/.codex/agents/`
- `<project>/.codex/config.toml`
- `<project>/.codex/aan-install-state.json`

### 注意

- 目标项目需要是 trusted project，否则项目级 `.codex/config.toml` 可能不会生效。
- MCP 中保留的 `YOUR_*_HERE` 占位符需要用户后续手工补全。
