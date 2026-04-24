# AAN 模块 Manifest — Schema 与校验规格

本文档说明 `manifests.json` 的结构、字段语义、不变式，以及后续校验脚本的规格。

## 1. 目的

`manifests.json` 是 AAN 模块归属的**单一真源**：声明 11 个模块分别包含哪些 skill / agent / command / rule / hook。它的设计对应《模块归属草案》§12 **阶段 1（零破坏）**——不移动任何源文件，仅以路径或 id 白名单形式做虚拟归集。

## 2. 顶层结构

```json
{
  "$schema_version": "1",
  "modules": {
    "<module_name>": { ... }
  }
}
```

- `$schema_version`：schema 版本号。当前为 `"1"`。
- `modules`：模块字典，键为模块名，值为模块对象。

## 3. 字段定义

每个模块对象包含以下字段：

| 字段 | 类型 | 必填 | 说明 |
|------|------|:----:|------|
| `description` | string | 是 | 一句话模块定义 |
| `required` | boolean | 是 | `true` 表示任何安装都必须包含；`false` 表示用户可选。当前仅 `common` 为 `true` |
| `depends_on` | string[] | 是 | 依赖的模块名列表；`common` 为 `[]`，其余模块至少包含 `"common"` |
| `skills` | string[] | 是 | `skills/` 下的子目录名（每个子目录含一个 SKILL.md） |
| `agents` | string[] | 是 | `agents/` 下的文件名，含 `.md` |
| `commands` | string[] | 是 | `commands/` 下的文件名，含 `.md` |
| `rules` | string[] | 是 | 相对 `rules/` 的路径，如 `common/security.md` |
| `hooks` | string[] | 是 | `hooks/hooks.json` 的 hook id 白名单 |
| `mcp_servers` | string[] | 否 | 可选，`mcp/mcp-servers.json` 的 server 名 |
| `notes` | string | 否 | 可选备忘（如候选归属标注） |

空字段一律用 `[]`，不得省略。

## 4. 不变式（校验规则）

后续校验脚本必须保证以下五条：

### 4.1 完备性
`modules.*.{skills, agents, commands, rules}` 的并集 **等于** `all-agents-need/{skills, agents, commands, rules}/` 实际文件全集：

| 类型 | 实测数量（v3.2） |
|------|:---:|
| skills | 20 个子目录 |
| agents | 27 个 `.md` |
| commands | 29 个 `.md` |
| rules | 37 个 `.md` |

`modules.*.hooks` 并集 **等于** `hooks/hooks.json` 中 26 个 hook id。

### 4.2 唯一性
每个 skill / agent / command / rule / hook id **恰好**出现在一个模块的对应字段中。禁止重复归属。

### 4.3 Hook id 对齐
`modules.*.hooks` 并集 ⊆ `hooks/hooks.json` 的 id 集合，且并集大小 = 26。

### 4.4 依赖方向
- `common.depends_on == []`
- 非 common 模块的 `depends_on` 至少包含 `"common"`
- 依赖图无环
- 禁止 common 以外的横向依赖（未来 `ml` 模块例外，允许依赖 `"python"`）

### 4.5 Required 语义
- 至少一个模块 `required: true`（当前仅 `common`）
- 安装集计算：`selected = userChoice ∪ { m | modules[m].required == true }`，再沿 `depends_on` 做传递闭包

## 5. 安装集计算（供后续 install 脚本参考）

给定用户选择的模块集合 `U`：

```
selected    = U ∪ { m ∈ modules | modules[m].required == true }
install_set = transitive_closure(selected, depends_on)
```

流程：
1. 合并用户选择与 `required: true` 模块。
2. 对并集按 `depends_on` 做传递闭包。
3. 按 `install_set` 过滤 `skills / agents / commands / rules` 文件，并按 `hooks` id 过滤 `hooks.json`。

## 6. 校验脚本规格（**本次不实现**）

脚本路径（计划）：`scripts/validate-manifests.js` 或 `.sh`。

**输入**：
- `install/manifests.json`
- `all-agents-need/{skills, agents, commands, rules}/**` 实际文件树
- `hooks/hooks.json`

**行为**：
1. 解析 manifest，提取所有声明的 id。
2. 扫描实际文件树，提取所有实际存在的 id。
3. 对比两个集合，输出三类差异：
   - **缺失**（实际存在、manifest 未声明）
   - **孤儿**（manifest 声明、实际不存在）
   - **重复**（多个模块声明同一项）
4. 依赖图校验：无环 + 方向符合 §4.4。
5. Required 字段校验：至少一个 `true`。

**退出码**：
- `0` 全部通过
- 非 `0` 任一检查失败，并打印结构化报告

## 7. 本次阶段说明

- 本 manifest 对应草案 §12 **阶段 1（零破坏）**：目录保持 type-based，不移动源文件。
- 阶段 2（feature-based 物理迁移）尚未执行；届时 manifest 的路径值需相应调整（例如 `rules` 字段可剥离模块前缀）。
- **未创建 `ml` 模块**：当前 ML 资源仅 1 项（`pytorch-build-resolver`），按草案 §2 规则"达到 ≥3 项后再独立"暂入 `python`。

## 8. 更新策略

新增 / 删除 / 重命名产出物时，须同步更新 `manifests.json`：

| 变更 | 需要同步的位置 |
|------|---------------|
| 新增 skill / agent / command / rule | 加入对应模块的字段数组 |
| 新增 hook | 在 `hooks/hooks.json` 加 id，同步加入对应模块的 `hooks` 数组 |
| 重命名 | 同时修改实际文件与 manifest |
| 删除 | 从实际文件与 manifest 同时移除 |

每次更新后手工（或脚本）跑一次 §4 不变式。

## 9. 历史

| 版本 | 说明 |
|------|------|
| `$schema_version: "1"` | 首个版本，对应草案 v3.2。11 个模块、139 项产出物。`ml` 未建模。 |
