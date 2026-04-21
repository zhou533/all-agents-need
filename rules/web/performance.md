> 本文档扩展了 [common/performance.md](../common/performance.md) 中关于 Web 的性能内容。

# Web 性能规则

## Core Web Vitals 目标

| 指标 | 目标 |
|------|------|
| LCP  | < 2.5s |
| INP  | < 200ms |
| CLS  | < 0.1 |
| FCP  | < 1.5s |
| TBT  | < 200ms |

## 打包体积预算

| 页面类型 | JS 预算（gzipped） | CSS 预算 |
|----------|-------------------|----------|
| Landing page | < 150kb | < 30kb |
| App page | < 300kb | < 50kb |
| Microsite | < 80kb | < 15kb |

## 加载策略

1. 在合理的场景下内联首屏关键 CSS
2. 仅预加载 hero 图片与主字体
3. 延迟加载非关键的 CSS 或 JS
4. 动态 import 重型库

```js
const gsapModule = await import('gsap');
const { ScrollTrigger } = await import('gsap/ScrollTrigger');
```

## 图像优化

* 显式 `width` 与 `height`
* 仅对 hero 媒体使用 `loading="eager"` + `fetchpriority="high"`
* 首屏以下资产使用 `loading="lazy"`
* 优先选择 AVIF 或 WebP，并提供回退
* 绝不发布远大于实际渲染尺寸的源图

## 字体加载

* 最多两种字体家族，除非有明确例外
* `font-display: swap`
* 能做子集就做子集
* 仅预加载真正关键的字重/字样

## 动画性能

* 仅动画合成器友好的属性
* 谨慎使用 `will-change`，完成后及时移除
* 简单过渡优先使用 CSS
* 复杂的 JS 动效使用 `requestAnimationFrame` 或成熟动画库
* 避免滚动事件的抖动；使用 IntersectionObserver 或表现可控的库

## 性能检查清单

* [ ] 所有图片都有显式尺寸
* [ ] 没有意外的 render-blocking 资源
* [ ] 没有因动态内容导致的布局抖动
* [ ] 动效只作用于合成器友好属性
* [ ] 第三方脚本异步/延迟加载，且按需加载
