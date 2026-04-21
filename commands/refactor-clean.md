# Refactor Clean

安全地识别并移除死代码，每一步都用测试验证。

## 第 1 步：检测死代码

按项目类型运行分析工具：

| 工具 | 发现的内容 | 命令 |
|------|-----------|------|
| knip | 未使用的 export / 文件 / 依赖 | `npx knip` |
| depcheck | 未使用的 npm 依赖 | `npx depcheck` |
| ts-prune | 未使用的 TypeScript export | `npx ts-prune` |
| vulture | 未使用的 Python 代码 | `vulture src/` |
| deadcode | 未使用的 Go 代码 | `deadcode ./...` |
| cargo-udeps | 未使用的 Rust 依赖 | `cargo +nightly udeps` |

若无可用工具，使用 Grep 查找零引用的 export：
```
# Find exports, then check if they're imported anywhere
```

## 第 2 步：对发现分类

将发现按安全等级排序：

| 等级 | 示例 | 动作 |
|------|------|------|
| **SAFE** | 未使用的 util、测试 helper、内部函数 | 放心删除 |
| **CAUTION** | 组件、API 路由、中间件 | 确认无动态 import 或外部消费者 |
| **DANGER** | 配置文件、入口点、类型定义 | 动手前先调查 |

## 第 3 步：安全删除循环

对每个 SAFE 项：

1. **运行完整测试套件** —— 建立基线（全绿）
2. **删除死代码** —— 用 Edit 工具外科式移除
3. **重跑测试套件** —— 确认未破坏任何东西
4. **若测试失败** —— 立即用 `git checkout -- <file>` 回滚并跳过此项
5. **若测试通过** —— 处理下一项

## 第 4 步：处理 CAUTION 项

删除 CAUTION 项前：
- 搜索动态 import：`import()`、`require()`、`__import__`
- 搜索字符串引用：配置中的 route 名、组件名
- 检查是否作为公共包 API 对外导出
- 确认无外部消费者（已发布的包需检查 dependents）

## 第 5 步：合并重复

移除死代码后，关注：
- 近乎重复的函数（相似度 > 80%）—— 合并成一个
- 冗余的类型定义 —— 合并
- 无价值的 wrapper 函数 —— 内联
- 无意义的 re-export —— 去掉中间层

## 第 6 步：汇总

汇报结果：

```
Dead Code Cleanup
──────────────────────────────
Deleted:   12 unused functions
           3 unused files
           5 unused dependencies
Skipped:   2 items (tests failed)
Saved:     ~450 lines removed
──────────────────────────────
All tests passing PASS:
```

## 规则

- **动手前必先跑测试**
- **一次只删一项** —— 原子改动让回滚简单
- **不确定就跳过** —— 留着死代码也比弄挂生产强
- **清理时不要重构** —— 关注点分离（先清理，再重构）
