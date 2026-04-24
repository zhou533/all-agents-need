# AAN For Codex 安装提示词

将本文件完整加载到 Codex 会话后，按以下要求执行安装。你的目标不是解释方案，而是作为安装执行器，在**目标 Codex 项目**中完成 AAN 的项目级安装。

## 目标

把已经通过 `git submodule add` 引入到目标项目中的 `aan` 工具包安装到当前 Codex 项目中。

本次安装范围只包含：

- `skills`
- `agents`
- `mcp`
- AAN submodule 的**硬边界**
- 安装报告

本次**不安装**：

- `hooks`
- `rules`
- `commands`

如果在 `manifests.json` 中发现上述未纳入项，只在最终报告里标记为 `not_installed_in_codex_version`，不要尝试兼容或落盘。

## 安装原则

1. 严格使用 Codex 的项目级规范：
   - skills 安装到项目级 `.agents/skills/`
   - agents 安装到项目级 `.codex/agents/`
   - MCP 配置写入项目级 `.codex/config.toml`
   - 硬边界也写入项目级 `.codex/config.toml`

2. 安装必须幂等：
   - 重复执行不能产生重复配置
   - 已存在且内容一致的项直接跳过
   - 只更新 AAN 管理的项，不破坏用户自定义项

3. 所有高确定性的结构化转换优先通过脚本完成：
   - `install-agents.py`
   - `install-mcp-config.py`

4. 不要修改 `install/manifests.json` 的通用语义，除非用户明确要求。

5. 不要安装到用户级 `~/.codex` 或 `~/.agents`，默认只做当前项目级安装。

6. 如果当前项目不是 trusted project，明确告知用户这一点，并继续完成文件落盘；同时在最终报告中提示“项目级 Codex 配置可能不会生效，直到项目被信任”。

## 路径与输入

你必须自动识别以下路径，不要要求用户手填，除非自动识别失败：

- `PROJECT_ROOT`
  - 当前目标项目根目录
- `AAN_ROOT`
  - 已通过 git submodule add 引入的 AAN 根目录
  - 该目录必须包含：
    - `install/manifests.json`
    - `skills/`
    - `agents/`
    - `mcp/mcp-servers.json`
- `CODEX_INSTALL_ROOT`
  - `${AAN_ROOT}/install/codex`

本安装器默认使用：

- manifests: `${AAN_ROOT}/install/manifests.json`
- agents source: `${AAN_ROOT}/agents`
- skills source: `${AAN_ROOT}/skills`
- mcp source: `${AAN_ROOT}/mcp/mcp-servers.json`
- state file: `${PROJECT_ROOT}/.codex/aan-install-state.json`

## 执行顺序

严格按以下顺序执行，除非遇到阻塞错误。

### 1. 前置检查

先检查并报告：

- 当前目录是否位于目标项目内
- `AAN_ROOT` 是否可识别
- `${AAN_ROOT}/install/manifests.json` 是否存在
- `${CODEX_INSTALL_ROOT}` 是否存在
- 后续所需脚本是否存在：
  - `${CODEX_INSTALL_ROOT}/install-agents.py`
  - `${CODEX_INSTALL_ROOT}/install-mcp-config.py`
  - `${CODEX_INSTALL_ROOT}/install-verification.sh`
- 当前项目是否已有 `.codex/`
- 当前项目是否已有 `.agents/`
- 当前项目是否可能未被 Codex 视为 trusted project

如果以下任一条件不满足，停止安装并输出阻塞报告：

- `AAN_ROOT` 无法识别
- `manifests.json` 不存在
- agent 转换脚本不存在
- MCP 转换脚本不存在
- 验证脚本不存在

### 2. 读取安装清单

读取 `${AAN_ROOT}/install/manifests.json`。

规则：

- 强制包含 `required: true` 的模块
- 对用户选中的模块做依赖闭包解析
- 只消费以下字段：
  - `skills`
  - `agents`
- 以下字段只记录，不安装：
  - `commands`
  - `rules`
  - `hooks`

### 3. 展示可安装模块并选择

向用户展示模块列表及说明，并允许以下选择方式之一：

- 安装全部模块
- 按模块名多选
- 仅安装必装底座模块

选择结果中必须自动补入依赖模块。

### 4. 展示 Codex 版安装计划

在真正落盘前，先输出一次清晰的安装计划，至少包括：

- `PROJECT_ROOT`
- `AAN_ROOT`
- 选中的模块
- 自动加入的依赖
- 将要安装的 skills 数量与名称
- 将要转换的 agents 数量与名称
- 是否配置 MCP
- 将被忽略的 `commands / hooks / rules`
- 将写入的目标路径：
  - `.agents/skills/`
  - `.codex/agents/`
  - `.codex/config.toml`
  - `.codex/aan-install-state.json`

### 5. 选择 MCP 安装策略

MCP 的选择独立于模块选择。

先询问用户是否配置 MCP，支持：

- 不配置 MCP
- 从 `mcp-servers.json` 中多选具体 server
- 选择推荐 MCP 集合

如果用户不配置 MCP：

- 仍可安装 `mcp-server-patterns` skill
- 但不要修改 `.codex/config.toml` 中的 `mcp_servers` 段

### 6. 安装 skills

对选中模块解析出的 skill 列表，执行以下规则：

- 目标路径为 `${PROJECT_ROOT}/.agents/skills/<skill-name>/`
- 复制整个 skill 目录，不只复制 `SKILL.md`
- 如果目标 skill 不存在，创建并安装
- 如果目标 skill 已存在且内容一致，跳过并记录为 `unchanged`
- 如果目标 skill 已存在但内容不同：
  - 若属于 AAN 管理资源，可更新覆盖
  - 若不是 AAN 管理资源，标记为冲突并征求用户确认

### 7. 转换并安装 agents

不要手写转换逻辑；调用 `${CODEX_INSTALL_ROOT}/install-agents.py` 完成。

该脚本负责：

- 把 `${AAN_ROOT}/agents/*.md` 中本次选中的 agent 转换到 `${PROJECT_ROOT}/.codex/agents/*.toml`
- 更新 `${PROJECT_ROOT}/.codex/config.toml` 中对应的 `[agents.<id>]`
- 只更新 AAN 管理的 agent 注册项
- 不覆盖用户无关的 agent 配置

调用前，你必须把本次选中的 agent 名单、项目根路径、AAN 根路径、state file 路径传给脚本。

如果脚本返回失败：

- 停止后续安装
- 输出 agent 转换失败报告

### 8. 配置 MCP

不要手写 JSON 到 TOML 的转换；调用 `${CODEX_INSTALL_ROOT}/install-mcp-config.py` 完成。

该脚本负责：

- 从 `${AAN_ROOT}/mcp/mcp-servers.json` 读取所选 MCP server
- 将其合并到 `${PROJECT_ROOT}/.codex/config.toml`
- 仅管理 AAN 负责的 `mcp_servers.*`
- 不删除或破坏用户已有的其他 MCP 配置
- 保留 `YOUR_*_HERE` 占位符

调用前，你必须把以下信息传给脚本：

- 项目根路径
- AAN 根路径
- 选中的 MCP server 名单
- state file 路径

如果用户选择不配置 MCP，则跳过这一步。

### 9. 写入硬边界

必须把 AAN submodule 写成**硬边界**，避免后续会话继续扫描该目录。

要求：

- 主要控制手段是 `${PROJECT_ROOT}/.codex/config.toml`
- 使用当前 Codex 官方支持的项目级 permissions/profile 机制
- 对 `AAN_ROOT` 对应的项目内路径施加 deny-read 边界
- 不要依赖 `AGENTS.md` 作为主控制手段

边界写入规则：

- 只更新与 AAN 边界相关的 profile/config
- 不删除用户现有的其他权限项
- 如果当前 config 中不存在可用的默认 permissions profile，则创建一个 AAN 专用 profile，并把它设为当前项目默认 profile
- 边界路径必须精确指向当前项目中的 AAN submodule 目录

### 10. 写入安装状态

安装完成后，维护 `${PROJECT_ROOT}/.codex/aan-install-state.json`。

至少记录：

- 安装时间
- `AAN_ROOT`
- AAN 在项目中的相对路径
- 选中的模块
- 已安装 skills
- 已安装 agents
- 已配置 MCP servers
- 被忽略的字段类别
- 硬边界所使用的 profile 名称

这个状态文件用于：

- 后续幂等更新
- 冲突判断
- 安装验证

### 11. 执行安装后验证

最后调用：

`$CODEX_INSTALL_ROOT/install-verification.sh`

默认执行整体验证；如果安装中只涉及局部内容，也可以补充分项验证，但整体验证必须执行一次。

如果验证失败：

- 安装流程标记为 `completed_with_errors`
- 不自动回滚
- 在最终报告中明确列出失败项

## 冲突处理规则

遇到以下情况时，必须显式处理，而不是静默覆盖：

1. 同名 skill 已存在，但不在 AAN state file 中
2. 同名 agent 已存在，但不在 AAN state file 中
3. `.codex/config.toml` 中已有同名 agent 注册项，且不是 AAN 管理项
4. `.codex/config.toml` 中已有同名 MCP server，且不是 AAN 管理项

默认策略：

- 先展示冲突
- 给出风险说明
- 征求用户确认后再覆盖

## 报告格式

安装结束后，输出结构化安装报告。

报告必须包含以下小节：

### Context

- `PROJECT_ROOT`
- `AAN_ROOT`
- trusted project 提示
- state file 路径

### Modules

- 用户选择的模块
- 自动加入的依赖模块

### Installed

- skills
- agents
- MCP servers

### Updated

- 被更新覆盖的项

### Skipped

- 已存在且未变化的项
- `commands`
- `rules`
- `hooks`

### Conflicts

- 冲突项
- 用户选择的处理方式

### Boundary

- 是否已写入硬边界
- 边界使用的 profile 名称
- 生效路径

### Verification

- 验证脚本是否执行
- 验证结果摘要

### Follow-up

- 需要用户补全的 MCP 占位符
- 若项目未 trusted，需要提示用户信任项目

## 失败处理

遇到失败时，遵循以下规则：

- 前置检查失败：直接停止，不改文件
- skill 安装失败：停止，不继续 agent 和 MCP
- agent 转换失败：停止，不继续 MCP 和验证
- MCP 配置失败：停止，仍可保留已完成的 skills 和 agents，并明确报告部分完成
- 验证失败：不回滚，只报告

## 输出风格

你的输出应当：

- 简洁
- 结构化
- 明确说明当前阶段
- 在真正改写目标项目文件前，先给用户一个清晰的安装计划
- 在发生冲突时，不替用户做隐式覆盖决策

不要：

- 解释 Claude 的安装逻辑
- 尝试兼容 hooks/rules/commands
- 把 AAN 安装到用户级目录
- 把 AAN submodule 当作业务代码继续扫描
