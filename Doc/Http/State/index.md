# 会话与状态

HTTP 本身是无状态协议：服务器处理完一次请求后，下一次请求不会天然知道它来自哪个用户。应用通常使用 Cookie、Session 或 Token 保存登录状态。

本章把这些概念放在一起说明，因为它们不是互相独立的功能，而是同一条登录链路中的不同部分。

## 先理解四个概念

| 概念 | 保存位置 | 主要用途 |
| --- | --- | --- |
| Cookie | 浏览器 | 随请求自动携带少量数据，常用于保存 Session ID |
| Session | Redis、数据库等服务端存储 | 保存 Session ID 对应的用户身份和状态 |
| Token | 客户端 | 客户端主动放入 Authorization Header |
| JWT | 客户端 | 一种带签名和声明的 Token 格式 |

典型的 Session 登录流程：

```text
用户提交账号和密码
    ↓
服务端验证密码
    ↓
生成随机 sessionId
    ↓
Redis 保存 sessionId → 用户信息
    ↓
通过 Set-Cookie 把 sessionId 发给浏览器
    ↓
浏览器后续请求自动携带 Cookie
    ↓
服务端读取 sessionId 并从 Redis 恢复身份
```

典型的 Token 登录流程：

```text
用户提交账号和密码
    ↓
服务端验证密码
    ↓
签发 Access Token
    ↓
客户端自行保存 Token
    ↓
请求时发送 Authorization: Bearer ...
    ↓
服务端验证 Token 并恢复身份
```

## 应该选择 Session 还是 Token

| 场景 | 推荐方式 |
| --- | --- |
| 同域后台管理系统 | Cookie + Session |
| 普通服务端渲染网站 | Cookie + Session |
| 移动端或第三方 API | Access Token |
| 多个服务共享身份声明 | 短期 JWT，可配合撤销状态 |
| 需要立即强制退出 | 服务端 Session，或 Token + 服务端撤销表 |

Session 容易主动失效，但每次请求需要查询共享存储。JWT 可以本地验证，但并不天然支持即时注销。不要因为 JWT 看起来“无状态”就默认所有项目都使用它。

## Cookie 如何参与登录

登录成功后，服务端生成不可预测的随机 Session ID，并通过 Response Cookie 返回：

```php
$sessionId = bin2hex(random_bytes(32));

$this->response()->setCookie(
    name: 'session_id',
    value: $sessionId,
    expire: time() + 3600,
    path: '/',
    domain: '',
    secure: true,
    httponly: true,
    samesite: 'Lax'
);
```

后续请求读取：

```php
$sessionId = $this->request()->getCookieParams('session_id');
```

安全属性：

- `Secure`：只通过 HTTPS 发送。
- `HttpOnly`：JavaScript 无法读取，降低 Token 被 XSS 窃取的风险。
- `SameSite=Lax/Strict`：降低跨站请求伪造风险。
- `Path` 和 `Domain`：限制 Cookie 的发送范围。
- `Expire`：控制浏览器保存期限。

Cookie 只能保存短小标识，不能保存密码、完整用户资料或可信权限。用户能够查看和修改自己的 Cookie，服务端必须验证其中的值。

## Session 为什么要放在共享存储

EasySwoole Worker 是多个常驻进程，线上还可能部署多个实例。如果把 Session 保存在某个 Worker 的普通数组中：

```php
// 错误示例
private static array $sessions = [];
```

下一次请求可能进入另一个 Worker 或另一台服务器，无法读取原来的状态；静态数组也会持续占用内存。因此 Session 应放进 Redis 等所有实例都能访问的存储。

建议保存的数据结构：

```php
[
    'userId' => 1001,
    'sessionVersion' => 3,
    'createdAt' => 1791940000,
    'lastActiveAt' => 1791940300,
]
```

不要把完整 ORM 对象、大量权限数据或敏感密码哈希序列化进 Session。Session 应少而稳定，详细用户信息需要时重新读取或使用短期缓存。

## 一个完整的 Session 登录控制器

下面使用 `SessionStore` 表示项目封装的 Redis 存储。它不是框架内置类，需要根据所使用的 Redis 组件实现。

`App/HttpController/Admin/Auth.php`：

```php
<?php

namespace App\HttpController\Admin;

class Auth extends Base
{
    protected array $ignoreAction = ['login'];

    public function login(): void
    {
        $data = $this->json();
        $account = trim((string) ($data['account'] ?? ''));
        $password = (string) ($data['password'] ?? '');

        $admin = AdminService::getInstance()->findByAccount($account);
        if ($admin === null || !password_verify($password, $admin->passwordHash)) {
            $this->writeJson(422, null, '账号或密码错误');
            return;
        }

        // 登录成功后生成全新 ID，防止会话固定攻击。
        $sessionId = bin2hex(random_bytes(32));
        SessionStore::getInstance()->put(
            'admin_session:' . $sessionId,
            ['adminId' => $admin->id],
            3600
        );

        $this->response()->setCookie(
            'admin_session', $sessionId, time() + 3600,
            '/', '', true, true, 'Lax'
        );
        $this->writeJson(200, null, '登录成功');
    }

    public function logout(): void
    {
        $sessionId = $this->request()->getCookieParams('admin_session');
        if (is_string($sessionId) && $sessionId !== '') {
            SessionStore::getInstance()->delete('admin_session:' . $sessionId);
        }

        $this->response()->setCookie(
            'admin_session', '', time() - 3600,
            '/', '', true, true, 'Lax'
        );
        $this->writeJson(200, null, '退出成功');
    }
}
```

Base 控制器在 `onRequest()` 中恢复身份：

```php
protected ?int $adminId = null;

protected function onRequest(?string $action): ?bool
{
    if (in_array($action, $this->ignoreAction, true)) {
        return true;
    }

    $sessionId = $this->request()->getCookieParams('admin_session');
    $session = is_string($sessionId)
        ? SessionStore::getInstance()->get('admin_session:' . $sessionId)
        : null;

    if (!is_array($session) || empty($session['adminId'])) {
        $this->writeJson(401, null, '请先登录');
        return false;
    }

    $this->adminId = (int) $session['adminId'];
    return true;
}
```

Base 控制器、`ignoreAction` 和拦截流程详见“鉴权与拦截”。

## Token 的基本使用

客户端拿到 Token 后主动发送：

```text
Authorization: Bearer eyJ...
```

控制器读取并拆分：

```php
$authorization = $this->request()->getHeaderLine('authorization');

if (!preg_match('/^Bearer\s+(.+)$/i', $authorization, $matches)) {
    $this->writeJson(401, null, '缺少访问令牌');
    return false;
}

$token = $matches[1];
```

不要通过 Query 传 Token，例如 `?token=...`，因为 URL 可能进入代理日志、浏览器历史和 Referer。

Access Token 应短期有效。需要长期登录时使用独立的 Refresh Token 换取新 Access Token，并在服务端保存 Refresh Token 的哈希、设备信息、过期时间和撤销状态。

## JWT 必须验证什么

JWT 不是简单地 Base64 解码后读取用户 ID。服务端至少要验证：

- 签名是否正确。
- 算法是否在服务端固定允许列表中。
- `exp` 是否过期。
- `nbf` 是否已经生效。
- `iss` 是否为可信签发方。
- `aud` 是否包含当前服务。
- 必要时验证 `jti`、用户状态和 Token 版本。

不能相信 Token Header 自己声明的算法，也不要自行实现 JWT 加密和验签，应使用维护良好的库。

JWT 载荷通常只是编码，不是加密。不要放密码、身份证号或其他秘密。

## 登录、续期和退出

完整状态变化建议如下：

```text
登录
  验证频率限制 → 查询用户 → password_verify
  → 生成新 Session/Token → 记录安全日志

访问
  读取凭据 → 验证有效期和用户状态
  → 恢复当前身份 → 权限判断

续期
  接近过期且用户仍活跃 → 延长 Session
  或用 Refresh Token 换取新 Access Token

退出
  服务端删除 Session/撤销 Refresh Token
  → 删除客户端 Cookie/Token
```

修改密码、封禁账号、角色提权和发现风险设备时，应使旧状态失效。可以维护 `sessionVersion` 或 `tokenVersion`，版本变化后拒绝旧凭据。

## 常驻进程注意事项

不要把当前用户写进静态属性或全局单例：

```php
// 错误：其他请求可能读到这个用户。
CurrentUser::$id = $userId;
```

身份数据应保存到 Controller 实例属性、Request Attribute 或能够正确清理的协程上下文。共享的 SessionStore 可以是单例，但“当前请求是谁”不能成为它的可变实例属性。

## 常见安全问题

- 密码必须使用 `password_hash()` 和 `password_verify()`，不能明文保存或自行设计哈希。
- 登录接口要限制账号、IP 和设备维度的失败频率。
- 登录成功、权限提升后轮换 Session ID，防止会话固定。
- Cookie 认证的状态修改接口仍需考虑 CSRF。
- JWT 过期时间不宜过长，Refresh Token 必须支持撤销和轮换。
- 退出不能只删除浏览器 Cookie，还要让服务端 Session 或 Refresh Token 失效。
- 错误信息不要区分“账号不存在”和“密码错误”，避免枚举账号。
- 全站使用 HTTPS，避免凭据在传输过程中泄露。
