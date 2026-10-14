# HTTP 事件

处理 HTTP 请求时，最常用的前置入口有两层：

1. 框架级全局 `onRequest`：路由匹配前执行，影响所有 HTTP 请求。
2. 控制器级 `onRequest`：控制器创建后、Action 执行前调用，只影响当前控制器及其子类。

框架还提供全局 `afterRequest`，用于请求完成后的统一收尾。本章只讲 HTTP 请求相关钩子；Worker、Task、Finish 等属于 Swoole 服务事件，不放在本章讨论。

## 执行顺序

```text
Swoole 收到 HTTP 请求
    ↓
创建 EasySwoole Request / Response
    ↓
HTTP_GLOBAL_ON_REQUEST
    ├── 返回 false：跳过路由和控制器
    └── 返回其他值：继续
            ↓
路由匹配与控制器创建
    ↓
Controller::onRequest($action)
    ├── 返回 false：跳过当前 Action
    └── 返回其他值：执行 Action
            ↓
Controller Action
    ↓
Controller::afterAction($action)
    ↓
HTTP_GLOBAL_AFTER_REQUEST
    ↓
发送 Response
```

## 全局 `onRequest`

全局 `onRequest` 在路由匹配之前执行。此时还不知道最终会进入哪个控制器，适合处理真正作用于所有 HTTP 请求的逻辑：

- 生成 Request ID。
- 检查 Host 是否允许。
- 服务维护期间统一返回 503。
- 设置所有响应都需要的 Header。
- 统一处理跨域 CORS 和 OPTIONS 预检。
- 记录请求开始信息。

### 在哪里定义

在项目根目录的 `EasySwooleEvent.php` 中，通过 DI 设置 `SysConst::HTTP_GLOBAL_ON_REQUEST`。

项目目录：

```text
项目根目录/
├── App/
├── Config/
├── EasySwooleEvent.php      ← 在 initialize() 中设置
├── composer.json
└── easyswoole
```

完整示例：

```php
<?php

namespace EasySwoole\EasySwoole;

use EasySwoole\Component\Di;
use EasySwoole\EasySwoole\AbstractInterface\Event;
use EasySwoole\EasySwoole\Swoole\EventRegister;
use EasySwoole\EasySwoole\SysConst;
use EasySwoole\Http\Request;
use EasySwoole\Http\Response;

class EasySwooleEvent implements Event
{
    public static function initialize(): void
    {
        Di::getInstance()->set(
            SysConst::HTTP_GLOBAL_ON_REQUEST,
            function (Request $request, Response $response): bool {
                $requestId = bin2hex(random_bytes(8));
                $response->withHeader('X-Request-Id', $requestId);

                // 示例：只允许指定 Host。
                $host = $request->getHeaderLine('host');
                $allowedHosts = [
                    '127.0.0.1:9501',
                    'localhost:9501',
                    'api.example.com',
                ];

                if (!in_array($host, $allowedHosts, true)) {
                    $response->withStatus(400);
                    $response->withHeader(
                        'Content-Type',
                        'application/json; charset=utf-8'
                    );
                    $response->write(json_encode([
                        'code' => 400,
                        'message' => '非法 Host',
                    ], JSON_UNESCAPED_UNICODE));

                    // 跳过 Router 和 Controller。
                    return false;
                }

                // CORS：只允许明确配置的前端站点跨域访问。
                $origin = $request->getHeaderLine('origin');
                $allowedOrigins = [
                    'https://admin.example.com',
                    'https://www.example.com',
                ];

                if ($origin !== '') {
                    if (!in_array($origin, $allowedOrigins, true)) {
                        $response->withStatus(403);
                        $response->write('CORS origin denied');
                        return false;
                    }

                    $response->withHeader('Access-Control-Allow-Origin', $origin);
                    $response->withHeader('Access-Control-Allow-Credentials', 'true');
                    $response->withHeader(
                        'Access-Control-Allow-Methods',
                        'GET, POST, PUT, PATCH, DELETE, OPTIONS'
                    );
                    $response->withHeader(
                        'Access-Control-Allow-Headers',
                        'Authorization, Content-Type, X-Request-Id'
                    );
                    $response->withHeader(
                        'Vary',
                        'Origin, Access-Control-Request-Method, Access-Control-Request-Headers'
                    );

                    // OPTIONS 是浏览器的预检请求，不需要进入业务路由。
                    if (strtoupper($request->getMethod()) === 'OPTIONS') {
                        $response->withStatus(204);
                        return false;
                    }
                }

                return true;
            }
        );
    }

    public static function mainServerCreate(EventRegister $register): void
    {
    }
}
```

修改 `EasySwooleEvent.php` 后需要完整重启服务：

```bash
php easyswoole server stop
php easyswoole server start
```

测试允许的 Host：

```bash
curl -i http://127.0.0.1:9501/
```

响应中应包含：

```text
X-Request-Id: ...
```

测试不允许的 Host：

```bash
curl -i http://127.0.0.1:9501/ \
  -H 'Host: invalid.example.com'
```

预期返回 400，且不会进入 Router 或 Controller。

### 在全局 `onRequest` 处理 CORS

浏览器发现网页域名与 API 域名不同时，会执行跨域检查。某些请求会先发送 OPTIONS 预检：

```text
OPTIONS /api/users
Origin: https://admin.example.com
Access-Control-Request-Method: POST
Access-Control-Request-Headers: authorization, content-type
```

上面的完整示例会在路由之前处理它：

```text
读取 Origin
    ↓
检查是否位于 allowedOrigins
    ├── 否：返回 403，并跳过 Router
    └── 是：写入 CORS 响应 Header
            ↓
是否为 OPTIONS
    ├── 是：返回 204，并跳过 Router
    └── 否：继续进入业务路由
```

使用 curl 验证预检：

```bash
curl -i -X OPTIONS http://127.0.0.1:9501/api/users \
  -H 'Origin: https://admin.example.com' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: authorization, content-type'
```

预期状态码为 204，并包含：

```text
Access-Control-Allow-Origin: https://admin.example.com
Access-Control-Allow-Credentials: true
Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS
Access-Control-Allow-Headers: Authorization, Content-Type, X-Request-Id
Vary: Origin, Access-Control-Request-Method, Access-Control-Request-Headers
```

再用不允许的来源测试：

```bash
curl -i -X OPTIONS http://127.0.0.1:9501/api/users \
  -H 'Origin: https://evil.example.com' \
  -H 'Access-Control-Request-Method: POST'
```

预期返回 403。

#### 为什么不能直接允许 `*`

如果接口允许浏览器携带 Cookie，服务端必须返回具体 Origin 和：

```text
Access-Control-Allow-Credentials: true
```

此时 `Access-Control-Allow-Origin` 不能是 `*`。应维护可信来源列表，并将请求中的 Origin 原样回写；`Vary: Origin` 告诉代理缓存不同 Origin 可能得到不同响应。

如果只允许 `https://example.com`，不要用简单的字符串包含或后缀判断，否则 `https://example.com.evil.test` 可能被错误放行。应解析并精确匹配 Scheme、Host 和 Port，或直接使用完整 Origin 白名单。

CORS 不是鉴权机制。它主要限制浏览器 JavaScript，curl、服务端程序和恶意客户端不受 CORS 保护；业务接口仍然必须验证 Token、Session 和操作权限。

### 返回值的意义

```php
return true;
```

表示继续进行路由分发。实际上只要返回值不严格等于 `false`，框架都会继续。

```php
$response->withStatus(403);
$response->write('Forbidden');
return false;
```

表示当前钩子已经处理响应，跳过后面的 Router 和 Controller。

返回 `false` 前必须写入状态码和响应内容，否则客户端可能收到没有说明的空响应。即便返回 `false`，全局 `afterRequest` 仍会执行。

## 控制器 `onRequest`

控制器 `onRequest()` 在路由已经匹配、控制器已经创建之后执行。它知道当前 Action 名称，更适合处理某个业务模块的公共逻辑：

- 管理员登录鉴权。
- 商户权限检查。
- 当前控制器下的 Action 白名单。
- 把当前用户写入 Controller 实例属性。

基本形式：

```php
protected function onRequest(?string $action): ?bool
{
    $token = $this->request()->getHeaderLine('Authorization');

    if ($token === '') {
        $this->writeJson(401, null, '请先登录');
        return false;
    }

    return true;
}
```

建议为管理员模块建立 `Admin\\Base`，让管理员控制器继承 Base，并在 Base 的 `onRequest()` 中统一鉴权。登录 Action 还可以通过 `ignoreAction` 放行。

完整目录、Base 控制器、登录白名单、路由和测试方法请阅读：[鉴权与拦截](/Http/Middleware/global.md)。

## 两种 `onRequest` 怎么选择

| 对比项 | 全局 `HTTP_GLOBAL_ON_REQUEST` | 控制器 `onRequest()` |
| --- | --- | --- |
| 定义位置 | 根目录 `EasySwooleEvent.php` | Controller 或公共 Base Controller |
| 执行时机 | 路由匹配之前 | 路由匹配并创建控制器之后 |
| 作用范围 | 所有 HTTP 请求 | 当前控制器及继承关系 |
| 是否知道 Action | 不知道 | 通过 `$action` 获取 |
| 返回 `false` | 跳过 Router 和 Controller | 跳过当前 Action |
| 典型用途 | Request ID、Host、维护模式 | 登录、权限、Action 白名单 |

不要把管理员鉴权直接放进全局 `onRequest`，否则登录接口、公开接口、健康检查和静态资源都会进入管理员鉴权逻辑，需要维护大量 URL 排除项。按模块建立 Base Controller 通常更清晰。

## 全局 `afterRequest`

`HTTP_GLOBAL_AFTER_REQUEST` 在路由和控制器处理结束后、Response 真正发送前执行。它适合记录最终状态码、请求日志和耗时。

仍然在根目录 `EasySwooleEvent.php` 的 `initialize()` 中设置：

```php
Di::getInstance()->set(
    SysConst::HTTP_GLOBAL_AFTER_REQUEST,
    function (Request $request, Response $response): void {
        error_log(sprintf(
            '[HTTP] %s %s -> %d',
            $request->getMethod(),
            $request->getUri()->getPath(),
            $response->getStatusCode()
        ));
    }
);
```

如果同时注册前置和后置钩子，应把两个 `Di::set()` 都放进同一个 `initialize()`：

```php
public static function initialize(): void
{
    Di::getInstance()->set(
        SysConst::HTTP_GLOBAL_ON_REQUEST,
        function (Request $request, Response $response): bool {
            $response->withHeader(
                'X-Request-Id',
                bin2hex(random_bytes(8))
            );
            return true;
        }
    );

    Di::getInstance()->set(
        SysConst::HTTP_GLOBAL_AFTER_REQUEST,
        function (Request $request, Response $response): void {
            error_log(sprintf(
                '[HTTP] %s %s -> %d',
                $request->getMethod(),
                $request->getUri()->getPath(),
                $response->getStatusCode()
            ));
        }
    );
}
```

`afterRequest` 位于 `finally` 中，所以前置钩子返回 `false`、路由回调提前结束或业务处理抛出异常时，框架仍会尝试调用它。

如果 `afterRequest` 自己抛出异常，框架会交给 HTTP 全局异常处理器。因此日志回调也应避免耗时阻塞和未经处理的异常。

## 常见错误

- 把 HTTP 全局钩子写进 `mainServerCreate()` 的 Swoole `EventRegister::onRequest`，与框架默认 HTTP 分发发生冲突。
- 在全局钩子返回 `false`，却没有设置任何响应内容。
- 在全局钩子里编写只属于管理员模块的复杂鉴权。
- 携带 Cookie 时同时返回 `Access-Control-Allow-Origin: *`。
- 只处理 OPTIONS，却忘记给实际 GET/POST 响应写 CORS Header。
- 把 CORS 当成身份认证，未在业务接口验证 Token 或权限。
- 修改 `EasySwooleEvent.php` 后只刷新浏览器，没有重启常驻服务。
- 在事件回调中执行阻塞时间很长的日志、网络请求或文件操作，阻塞 Worker。
- 使用静态属性保存当前用户、Token 等请求态数据，导致不同请求串数据。
