---
name: skill-create
description: 分析本地 git 历史以抽取编码模式并生成 SKILL.md 文件。Skill Creator GitHub App 的本地版本。
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /skill-create —— 本地 skill 生成

分析你仓库的 git 历史，抽取编码模式，并生成能让 Claude 学习你团队实践的 SKILL.md 文件。

## 用法

```bash
/skill-create                    # 分析当前仓库
/skill-create --commits 100      # 分析最近 100 个 commit
/skill-create --output ./skills  # 自定义输出目录
/skill-create --instincts        # 同时为 continuous-learning-v2 生成 instinct
```

## 作用

1. **解析 Git 历史** —— 分析 commit、文件变更与模式
2. **检测模式** —— 识别反复出现的工作流与约定
3. **生成 SKILL.md** —— 创建合法的 Claude Code skill 文件
4. **可选生成 instinct** —— 供 continuous-learning-v2 系统使用

## 分析步骤

### 第 1 步：采集 Git 数据

```bash
# Get recent commits with file changes
git log --oneline -n ${COMMITS:-200} --name-only --pretty=format:"%H|%s|%ad" --date=short

# Get commit frequency by file
git log --oneline -n 200 --name-only | grep -v "^$" | grep -v "^[a-f0-9]" | sort | uniq -c | sort -rn | head -20

# Get commit message patterns
git log --oneline -n 200 | cut -d' ' -f2- | head -50
```

### 第 2 步：检测模式

关注以下模式类型：

| 模式 | 检测方法 |
|------|----------|
| **Commit 约定** | 对 commit message 做正则（feat:、fix:、chore:） |
| **文件共变** | 总是一起变更的文件 |
| **工作流序列** | 重复出现的文件变更模式 |
| **架构** | 目录结构与命名约定 |
| **测试模式** | 测试文件位置、命名、覆盖 |

### 第 3 步：生成 SKILL.md

输出格式：

```markdown
---
name: {repo-name}-patterns
description: Coding patterns extracted from {repo-name}
version: 1.0.0
source: local-git-analysis
analyzed_commits: {count}
---

# {Repo Name} Patterns

## Commit Conventions
{detected commit message patterns}

## Code Architecture
{detected folder structure and organization}

## Workflows
{detected repeating file change patterns}

## Testing Patterns
{detected test conventions}
```

### 第 4 步：生成 Instinct（使用 `--instincts` 时）

用于 continuous-learning-v2 集成：

```yaml
---
id: {repo}-commit-convention
trigger: "when writing a commit message"
confidence: 0.8
domain: git
source: local-repo-analysis
---

# Use Conventional Commits

## Action
Prefix commits with: feat:, fix:, chore:, docs:, test:, refactor:

## Evidence
- Analyzed {n} commits
- {percentage}% follow conventional commit format
```

## 示例输出

对 TypeScript 项目运行 `/skill-create` 可能产生：

```markdown
---
name: my-app-patterns
description: Coding patterns from my-app repository
version: 1.0.0
source: local-git-analysis
analyzed_commits: 150
---

# My App Patterns

## Commit Conventions

This project uses **conventional commits**:
- `feat:` - New features
- `fix:` - Bug fixes
- `chore:` - Maintenance tasks
- `docs:` - Documentation updates

## Code Architecture

```
src/
├── components/     # React components (PascalCase.tsx)
├── hooks/          # Custom hooks (use*.ts)
├── utils/          # Utility functions
├── types/          # TypeScript type definitions
└── services/       # API and external services
```

## Workflows

### Adding a New Component
1. Create `src/components/ComponentName.tsx`
2. Add tests in `src/components/__tests__/ComponentName.test.tsx`
3. Export from `src/components/index.ts`

### Database Migration
1. Modify `src/db/schema.ts`
2. Run `pnpm db:generate`
3. Run `pnpm db:migrate`

## Testing Patterns

- Test files: `__tests__/` directories or `.test.ts` suffix
- Coverage target: 80%+
- Framework: Vitest
```

## GitHub App 集成

如需更高级能力（10k+ commit、团队共享、自动 PR），可使用上游 [Skill Creator GitHub App](https://github.com/apps/skill-creator)：

- 安装：[github.com/apps/skill-creator](https://github.com/apps/skill-creator)
- 在任何 issue 中评论 `/skill-creator analyze`
- 会收到带生成 skill 的 PR

## 相关命令

- `/instinct-import` —— 导入生成的 instinct
- `/instinct-status` —— 查看已学习 instinct
- `/evolve` —— 将 instinct 聚合为 skill / agent
