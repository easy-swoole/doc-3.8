# Header 与 Cookie

Header 描述请求元信息，Cookie 保存浏览器随请求携带的小型状态。二者都由客户端提供，必须视为不可信输入。

## 完整控制器

新建 `App/HttpController/RequestMeta.php`：

```php
<?php
namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\Controller;

class RequestMeta extends Controller
{
    public function index(): void
    {
        $request = $this->request();
        $authorization = $request->getHeaderLine('authorization');
        $requestId = $request->getHeaderLine('x-request-id');
        $sessionId = $request->getCookieParams('session_id');

        $this->writeJson(200, [
            'hasAuthorization' => $authorization !== '',
            'requestId' => $requestId,
            'sessionId' => $sessionId,
        ]);
    }
}
```

路由与测试：

```php
$routeCollector->get('/request/meta', '/RequestMeta/index');
```

```bash
curl http://127.0.0.1:9501/request/meta \
  -H 'Authorization: Bearer demo-token' \
  -H 'X-Request-Id: req-1001' \
  --cookie 'session_id=sess-abc; language=zh-CN'
```

## Header API

```php
$all = $request->getHeaders();              // array<string,array>
$values = $request->getHeader('accept');    // array
$line = $request->getHeaderLine('accept');  // 合并后的字符串
$exists = $request->hasHeader('accept');
```

Swoole 初始化的请求头名称会被转成小写，读取时建议使用小写。多值 Header 用 `getHeader()` 保留数组；`getHeaderLine()` 会用分隔符拼接，适合 Authorization 等单值 Header。

## Cookie API

```php
$allCookies = $request->getCookieParams();
$sessionId = $request->getCookieParams('session_id');
```

读取不到时单个 Cookie 返回 `null`。请求 Cookie 和响应 `Set-Cookie` 是两件事：读取用 Request，写入用 `$this->response()->setCookie()`。

认证信息不要写入日志。Cookie 不应保存密码或完整用户资料；认证 Cookie 要在响应端启用 `Secure`、`HttpOnly` 和合理的 `SameSite`。Header 与 Cookie 的格式验证通过，也不代表身份真实，仍需向 Session/Token 服务验证。
