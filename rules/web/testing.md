> 本文档扩展了 [common/testing.md](../common/testing.md) 中关于 Web 的测试内容。

# Web 测试规则

## 优先级顺序

### 1. 视觉回归

* 在关键断点截图：320、768、1024、1440
* 覆盖 hero、滚动叙事段落以及有意义的状态
* 视觉主导的工作使用 Playwright 截图
* 如果同时支持两种主题，都要测试

### 2. 可访问性

* 运行自动化可访问性检查
* 测试键盘导航
* 验证 reduced-motion 行为
* 验证色彩对比度

### 3. 性能

* 对有意义的页面运行 Lighthouse 或同类工具
* 保持 [performance.md](performance.md) 中的 CWV 目标

### 4. 跨浏览器

* 最低覆盖：Chrome、Firefox、Safari
* 测试滚动、动效与降级行为

### 5. 响应式

* 测试 320、375、768、1024、1440、1920
* 验证无溢出
* 验证触摸交互

## E2E 模板

```ts
import { test, expect } from '@playwright/test';

test('landing hero loads', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('h1')).toBeVisible();
});
```

* 避免靠超时做易抖动的断言
* 优先使用确定性等待

## 单元测试

* 测试工具函数、数据转换与自定义 hook
* 对于强视觉组件，视觉回归通常比脆弱的标记断言更有信号
* 视觉回归是覆盖率的补充，不能替代覆盖率指标
