# AAN (All Agents Need)

可复用的 Cursor Agent/Command 规格库。通过 git submodule 集成到任意 Cursor 项目中。

`cursor/` 目录存放 Cursor 的安装脚本，未来其他工具（如 Windsurf、Claude Code 等）的安装脚本也会放在各自目录下。

## 快速开始

```bash
cd <你的-cursor-项目>
git submodule add <repo-url> aan
bash aan/cursor/install.sh
```

安装脚本会自动发现仓库中的 spec 目录，并以**符号链接**方式映射到 `.cursor/` 下。

### 配置 MCP Servers

交互式选择项目所需的 MCP Server，生成 `.cursor/mcp.json`：

```bash
brew install jq gum   # 首次需要安装依赖
bash aan/cursor/init-mcp.sh
```

脚本会列出 `mcp/mcp-servers.json` 中所有可用的 MCP Server，需要 API Key 的会标注。用空格选择、回车确认。选择后可输入对应的 API Key，留空则保留占位符。

> **安全提示**：API Key 会明文写入 `.cursor/mcp.json`，脚本会自动将该文件加入 `.gitignore`。**请勿提交此文件**，每位开发者应在本地独立运行脚本配置。

### 安装 Agents & Commands

安装脚本会自动发现仓库中的 spec 目录，并以**符号链接**方式映射到 `.cursor/` 下：

| 源目录 | 目标目录 | 链接方式 | 说明 |
|--------|----------|----------|------|
| `agents/` | `.cursor/agents/` | 逐文件 | Agent 定义 |
| `commands/` | `.cursor/commands/` | 逐文件 | 斜杠命令定义 |
| `skills/` | `.cursor/skills/` | 逐子目录 | Agent Skills |
| `rules/` | `.cursor/rules/` | 逐文件 | 规则文件（未来扩展） |

> **Skills 说明**：Skills 采用嵌套目录结构（如 `skills/brainstorming/SKILL.md`），安装脚本会自动识别并以**子目录为单位**创建符号链接，保留 Cursor Skills 要求的目录结构。

## 更新

拉取 submodule 新版本后重新运行安装脚本即可：

```bash
cd aan && git pull origin main && cd ..
bash aan/cursor/install.sh
```

已有的符号链接会自动更新，无需手动操作。

## 安装选项

```bash
bash aan/cursor/install.sh --help
```

| 选项 | 说明 |
|------|------|
| `--project-root PATH` | 手动指定 Cursor 项目根目录（默认自动检测） |
| `--force` | 覆盖已存在的非链接文件 |
| `--copy` | 复制文件而非创建符号链接 |
| `--uninstall` | 移除已安装的符号链接 |
| `--dry-run` | 预览变更，不实际执行 |

## 卸载

```bash
bash aan/cursor/install.sh --uninstall
git submodule deinit -f aan
git rm -f aan
rm -rf .git/modules/aan
```

## 扩展 Spec

新增 spec 只需在仓库根目录下创建对应目录并放入 `.md` 或 `.mdc` 文件：

```
all-agents-need/
├── agents/          → .cursor/agents/       (逐文件链接)
│   ├── architect.md
│   └── planner.md
├── commands/        → .cursor/commands/     (逐文件链接)
│   └── plan.md
├── skills/          → .cursor/skills/       (逐子目录链接)
│   └── brainstorming/
│       └── SKILL.md
├── rules/           → .cursor/rules/        (示例，待扩展)
│   └── coding.mdc
├── mcp/
│   └── mcp-servers.json  # MCP Server 目录
└── cursor/
    ├── install.sh         # 安装脚本
    └── init-mcp.sh        # MCP 配置脚本
```

安装脚本会**自动发现**新目录，无需修改脚本本身。排除目录列表定义在脚本顶部的 `EXCLUDE_DIRS` 变量中。

## 当前包含的 Spec

### Agents

- **architect** — 软件架构专家，专注系统设计、可扩展性与技术决策
- **planner** — 专家级规划专员，面向复杂功能与重构

### Commands

- **/plan** — 在编写代码前先产出完整、可执行的实施计划

### Skills

- **brainstorming** — 在实施前进行协作式头脑风暴与设计探索

## 设计原则

- **符号链接优先**：默认使用 symlink，submodule 更新后自动生效
- **自动发现**：新增 spec 目录无需修改安装脚本
- **安全**：不覆盖已有文件（除非 `--force`），卸载时只移除自己创建的链接
- **幂等**：可反复运行，已有链接自动更新
