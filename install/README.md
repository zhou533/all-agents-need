# Install

`install/` 是 AAN 的安装入口目录，用来承载不同 AI Agent 或开发工具的安装脚本与初始化说明。

当前已支持：

- `cursor/`：用于 Cursor 项目的规则、命令、skills 与 MCP 配置安装

后续可以继续扩展：

- `claude/`
- `codex/`
- 其他 agent 或 IDE 集成目录

## 目录设计

为了便于扩展，建议每个 agent 在自己的子目录下维护独立安装逻辑，例如：

```text
install/
  README.md
  cursor/
    install.sh
    init-mcp.sh
  claude/
    install.sh
  codex/
    install.sh
```

推荐约定：

- 每个 agent 使用独立子目录，避免不同平台脚本互相耦合
- 每个子目录优先提供统一命名的 `install.sh`
- 如果需要额外初始化步骤，可以增加 `init-*.sh`
- 每个脚本都应尽量支持 `--help`，并允许显式指定目标项目路径

## 当前可用：Cursor

`install/cursor/` 目前包含两类脚本：

- `install/cursor/install.sh`：将本仓库中的规范目录安装到目标项目的 `.cursor/` 下
- `install/cursor/init-mcp.sh`：交互式生成目标项目的 `.cursor/mcp.json`

### 1. 安装 Cursor 规范文件

在你的 Cursor 项目根目录执行：

```bash
bash aan/install/cursor/install.sh
```

脚本会自动发现本仓库中的规范目录，并将其安装到目标项目的 `.cursor/` 中。默认使用符号链接，便于后续更新。

常用参数：

```bash
# 指定目标项目目录
bash aan/install/cursor/install.sh --project-root /path/to/project

# 预览将要执行的变更，不实际写入
bash aan/install/cursor/install.sh --dry-run

# 遇到冲突时直接覆盖，不再询问
bash aan/install/cursor/install.sh --force

# 复制文件而不是创建符号链接
bash aan/install/cursor/install.sh --copy

# 卸载此前安装到 .cursor/ 的内容
bash aan/install/cursor/install.sh --uninstall
```

适用场景：

- 初始化 AAN 到新的 Cursor 项目
- 拉取 AAN 更新后重新执行，刷新 `.cursor/` 下的规范内容
- 使用 `--dry-run` 先检查影响范围

### 2. 初始化 Cursor MCP 配置

在目标 Cursor 项目根目录执行：

```bash
bash aan/install/cursor/init-mcp.sh
```

这个脚本会读取仓库中的 `mcp/mcp-servers.json`，让你交互式选择要启用的 MCP 服务，并生成本地 `.cursor/mcp.json`。

可选参数：

```bash
# 指定目标项目目录
bash aan/install/cursor/init-mcp.sh --project-root /path/to/project
```

依赖：

```bash
brew install jq gum
```

注意事项：

- `.cursor/mcp.json` 可能包含 API Key，只应保留在本地
- 脚本会尽量把 `.cursor/mcp.json` 加入目标项目的 `.gitignore`
- 生成后通常需要重启 Cursor 或 reload window 才会生效

## 推荐使用流程

如果你是把本仓库作为子模块放在目标项目的 `aan/` 目录下，当前针对 Cursor 的常见流程如下：

```bash
git submodule add <repo-url> aan
bash aan/install/cursor/install.sh
bash aan/install/cursor/init-mcp.sh
```

后续更新 AAN 后，重新执行以下命令即可：

```bash
bash aan/install/cursor/install.sh
```

当未来新增 `claude/`、`codex/` 等目录时，可以沿用相同入口模式：

```bash
bash aan/install/<agent>/install.sh
```
