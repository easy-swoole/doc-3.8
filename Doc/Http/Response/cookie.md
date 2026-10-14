# Cookie

Response Cookie 通过 `Set-Cookie` 发给浏览器；后续请求由浏览器放入 Cookie Header，再通过 Request 读取。

## 登录与退出示例

```php
public function login(): void
{
    $sessionId = bin2hex(random_bytes(32));
    // 实际项目还要把 sessionId 与用户身份写入 Redis 等共享存储。
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
    $this->writeJson(200, null, '登录成功');
}

public function logout(): void
{
    // 应先让服务端 Session 失效，再用相同 Path/Domain 删除 Cookie。
    $this->response()->setCookie(
        'session_id', '', time() - 3600, '/', '', true, true, 'Lax'
    );
    $this->writeJson(200, null, '退出成功');
}
```

参数含义：`expire` 是 Unix 时间戳；`path` 控制发送路径；`domain` 控制域；`secure` 只允许 HTTPS；`httponly` 禁止 JavaScript 读取；`samesite` 常用 `Lax`、`Strict`、`None`。

本地 HTTP 调试时 `secure: true` 的 Cookie 可能不会被客户端回传，开发环境可按配置关闭，生产 HTTPS 必须开启。`SameSite=None` 通常必须配合 `Secure`。

```bash
curl -i -c /tmp/demo-cookie.txt -X POST https://example.com/login
curl -i -b /tmp/demo-cookie.txt https://example.com/profile
```

Cookie 容量有限且每次请求都会携带，只保存随机会话标识等短数据。不要保存密码、权限列表或完整用户资料；签名 Cookie 也只能防篡改，不能防止内容被看到。
