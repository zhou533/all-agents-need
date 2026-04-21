> 本文档扩展了 [common/coding-style.md](../common/coding-style.md) 中关于 Web 前端的特定内容。

# Web 编码风格

## 文件组织

按功能或界面区域组织，而非按文件类型：

```text
src/
├── components/
│   ├── hero/
│   │   ├── Hero.tsx
│   │   ├── HeroVisual.tsx
│   │   └── hero.css
│   ├── scrolly-section/
│   │   ├── ScrollySection.tsx
│   │   ├── StickyVisual.tsx
│   │   └── scrolly.css
│   └── ui/
│       ├── Button.tsx
│       ├── SurfaceCard.tsx
│       └── AnimatedText.tsx
├── hooks/
│   ├── useReducedMotion.ts
│   └── useScrollProgress.ts
├── lib/
│   ├── animation.ts
│   └── color.ts
└── styles/
    ├── tokens.css
    ├── typography.css
    └── global.css
```

## CSS 自定义属性

将设计 token 定义为变量，不要在多处硬编码调色板、字体、间距：

```css
:root {
  --color-surface: oklch(98% 0 0);
  --color-text: oklch(18% 0 0);
  --color-accent: oklch(68% 0.21 250);

  --text-base: clamp(1rem, 0.92rem + 0.4vw, 1.125rem);
  --text-hero: clamp(3rem, 1rem + 7vw, 8rem);

  --space-section: clamp(4rem, 3rem + 5vw, 10rem);

  --duration-fast: 150ms;
  --duration-normal: 300ms;
  --ease-out-expo: cubic-bezier(0.16, 1, 0.3, 1);
}
```

## 仅动画这些属性

优先使用合成器友好（compositor-friendly）的动画属性：

* `transform`
* `opacity`
* `clip-path`
* `filter`（慎用）

避免动画受布局影响的属性：

* `width`
* `height`
* `top`
* `left`
* `margin`
* `padding`
* `border`
* `font-size`

## 语义 HTML 优先

```html
<header>
  <nav aria-label="Main navigation">...</nav>
</header>
<main>
  <section aria-labelledby="hero-heading">
    <h1 id="hero-heading">...</h1>
  </section>
</main>
<footer>...</footer>
```

当语义元素已经存在时，不要用通用的 `div` 堆叠层层包裹。

## 命名

* 组件：PascalCase（`ScrollySection`、`SurfaceCard`）
* Hook：`use` 前缀（`useReducedMotion`）
* CSS 类：kebab-case 或工具类
* 动画时间线：按意图使用 camelCase（`heroRevealTl`）
