> 本文档扩展了 [common/security.md](../common/security.md) 中关于 Web 的安全内容。

# Web 安全规则

## 内容安全策略（CSP）

生产环境始终配置 CSP。

### 基于 Nonce 的 CSP

对脚本使用每请求的 nonce，而不是 `'unsafe-inline'`。

```text
Content-Security-Policy:
  default-src 'self';
  script-src 'self' 'nonce-{RANDOM}' https://cdn.jsdelivr.net;
  style-src 'self' 'unsafe-inline' https://fonts.googleapis.com;
  img-src 'self' data: https:;
  font-src 'self' https://fonts.gstatic.com;
  connect-src 'self' https://*.example.com;
  frame-src 'none';
  object-src 'none';
  base-uri 'self';
```

按项目实际情况调整来源。不要原样搬运。

## XSS 防御

* 绝不注入未经清洗的 HTML
* 除非先行清洗，避免使用 `innerHTML` / `dangerouslySetInnerHTML`
* 对动态模板值做转义
* 必要时使用经过审查的本地清洗库处理用户输入的 HTML

## 第三方脚本

* 异步加载
* 从 CDN 引入时使用 SRI
* 每季度审计
* 在可行时，对关键依赖优先自托管

## HTTPS 与响应头

```text
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: camera=(), microphone=(), geolocation=()
```

## 表单

* 状态变更型表单启用 CSRF 保护
* 提交端点施加限流
* 客户端与服务端双重校验
* 优先蜜罐或轻量反滥用手段，而非一刀切的 CAPTCHA
