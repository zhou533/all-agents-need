# 测试覆盖率（Test Coverage）

分析测试覆盖率、识别缺口，并生成缺失的测试以达到 80%+ 的覆盖率。

## 第 1 步：检测测试框架

| 指标 | 覆盖率命令 |
|-----------|-----------------|
| `jest.config.*` 或 `package.json` 含 jest | `npx jest --coverage --coverageReporters=json-summary` |
| `vitest.config.*` | `npx vitest run --coverage` |
| `pytest.ini` / `pyproject.toml` 含 pytest | `pytest --cov=src --cov-report=json` |
| `Cargo.toml` | `cargo llvm-cov --json` |
| `pom.xml` 配置了 JaCoCo | `mvn test jacoco:report` |
| `go.mod` | `go test -coverprofile=coverage.out ./...` |

## 第 2 步：分析覆盖率报告

1. 运行覆盖率命令
2. 解析输出（JSON summary 或终端输出）
3. 列出**覆盖率低于 80%** 的文件，按最差优先排序
4. 对每个覆盖率不足的文件，识别出：
   - 未被测试的函数或方法
   - 缺失的分支覆盖（if/else、switch、错误路径）
   - 使分母虚高的死代码

## 第 3 步：生成缺失的测试

对每个覆盖率不足的文件，按以下优先级生成测试：

1. **Happy path** —— 以合法输入覆盖核心功能
2. **错误处理** —— 非法输入、缺失数据、网络故障
3. **边界情况** —— 空数组、null / undefined、边界值（0、-1、MAX_INT）
4. **分支覆盖** —— 每一个 if/else、switch case、三元表达式

### 测试生成规则

- 将测试放在源码旁边：`foo.ts` → `foo.test.ts`（或遵循项目约定）
- 沿用项目既有的测试模式（导入风格、断言库、mock 方式）
- 对外部依赖进行 mock（数据库、API、文件系统）
- 每个测试必须独立 —— 测试之间不共享可变状态
- 用描述性命名：`test_create_user_with_duplicate_email_returns_409`

## 第 4 步：验证

1. 运行完整测试套件 —— 所有测试必须通过
2. 再次运行覆盖率 —— 验证有所提升
3. 若仍低于 80%，对剩余缺口重复第 3 步

## 第 5 步：报告

展示前后对比：

```
Coverage Report
──────────────────────────────
File                   Before  After
src/services/auth.ts   45%     88%
src/utils/validation.ts 32%    82%
──────────────────────────────
Overall:               67%     84%  PASS:
```

## 重点关注

- 分支复杂的函数（圈复杂度高）
- 错误处理器与 catch 块
- 被整个代码库频繁使用的工具函数
- API 端点处理器（request → response 的完整流程）
- 边界情况：null、undefined、空字符串、空数组、零、负数
