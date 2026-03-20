# AAN (All Agents Need)

可复用的 Cursor Agent/Command 规格库。通过 git submodule 集成到任意 Cursor 项目中。

`cursor/` 目录存放 Cursor 的安装脚本，未来其他工具（如 Windsurf、Claude Code 等）的安装脚本也会放在各自目录下。

## 快速开始

```bash
cd <你的-cursor-项目>
git submodule add <repo-url> aan
bash aan/cursor/install.sh
```

安装脚本会自动发现仓库中的 spec 目录，并以**符号链接**方式映射到 `.cursor/` 下：

| 源目录 | 目标目录 | 说明 |
|--------|----------|------|
| `agents/` | `.cursor/agents/` | Agent 定义 |
| `commands/` | `.cursor/commands/` | 斜杠命令定义 |
| `rules/` | `.cursor/rules/` | 规则文件（未来扩展） |

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
├── agents/          → .cursor/agents/
│   ├── architect.md
│   └── planner.md
├── commands/        → .cursor/commands/
│   └── plan.md
├── rules/           → .cursor/rules/     (示例，待扩展)
│   └── coding.mdc
└── cursor/
    └── install.sh   # Cursor 安装脚本
```

安装脚本会**自动发现**新目录，无需修改脚本本身。排除目录列表定义在脚本顶部的 `EXCLUDE_DIRS` 变量中。

## 当前包含的 Spec

### Agents

- **architect** — 软件架构专家，专注系统设计、可扩展性与技术决策
- **planner** — 专家级规划专员，面向复杂功能与重构

### Commands

- **/plan** — 在编写代码前先产出完整、可执行的实施计划

## 设计原则

- **符号链接优先**：默认使用 symlink，submodule 更新后自动生效
- **自动发现**：新增 spec 目录无需修改安装脚本
- **安全**：不覆盖已有文件（除非 `--force`），卸载时只移除自己创建的链接
- **幂等**：可反复运行，已有链接自动更新
