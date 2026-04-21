> 本文档扩展了 [common/patterns.md](../common/patterns.md) 中关于 Web 的特定模式。

# Web 模式

## 组件组合

### 复合组件（Compound Components）

当相关联的 UI 共享状态与交互语义时，使用复合组件：

```tsx
<Tabs defaultValue="overview">
  <Tabs.List>
    <Tabs.Trigger value="overview">Overview</Tabs.Trigger>
    <Tabs.Trigger value="settings">Settings</Tabs.Trigger>
  </Tabs.List>
  <Tabs.Content value="overview">...</Tabs.Content>
  <Tabs.Content value="settings">...</Tabs.Content>
</Tabs>
```

* 父组件持有状态
* 子组件通过 context 消费
* 对于复杂组件，优先于 prop drilling

### Render Props / Slots

* 当行为可复用但标记必须不同时，使用 render props 或 slot 模式
* 把键盘处理、ARIA、焦点逻辑留在 headless 层

### 容器/展示拆分

* 容器组件负责数据加载与副作用
* 展示组件接收 props 并渲染 UI
* 展示组件应当保持纯净

## 状态管理

将以下四类分开处理：

| 关注点 | 工具 |
|--------|------|
| 服务器状态 | TanStack Query、SWR、tRPC |
| 客户端状态 | Zustand、Jotai、signals |
| URL 状态 | search params、route segments |
| 表单状态 | React Hook Form 或同类库 |

* 不要把服务器状态复制进客户端 store
* 派生值，而非另存一份冗余的计算状态

## URL 即状态

把可分享的状态持久化到 URL：

* 过滤器
* 排序
* 分页
* 当前 tab
* 搜索查询

## 数据获取

### Stale-While-Revalidate

* 立即返回缓存数据
* 后台重新校验
* 优先使用已有库，而非自己实现

### 乐观更新

* 快照当前状态
* 应用乐观更新
* 失败时回滚
* 回滚时向用户呈现可见的错误反馈

### 并行加载

* 并行获取相互独立的数据
* 避免父子请求瀑布流
* 在有充分理由时，预取下一个可能的路由或状态
