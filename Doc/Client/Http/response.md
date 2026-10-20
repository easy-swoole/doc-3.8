# HTTP Client 处理响应

请求返回 `EasySwoole\HttpClient\Bean\Response`。

## 读取响应

```php
$status = $response->getStatusCode();
$headers = $response->getHeaders();
$body = $response->getBody();
$cookies = $response->getCookies();
$errCode = $response->getErrCode();
$errMsg = $response->getErrMsg();
```

也可以读取本次请求信息：

```php
$response->getRequestMethod();
$response->getRequestHeaders();
$response->getRequestBody();
$response->getHost();
$response->getPort();
```

## 第一步：判断本地超时与其他传输错误

普通请求失败时仍会返回 `Response`。先看负数 `statusCode`，再结合 `errCode`：`-2` 代表请求超时；`-1` 是连接失败，`-4` 是发送失败，二者只有错误码为 `SOCKET_ETIMEDOUT` 时才能进一步归类为超时；`-3` 是连接被重置。完整示例和 408/504 的区别见[超时配置与判定](/Client/Http/timeout.md)。

```php
$status = $response->getStatusCode();
$errCode = $response->getErrCode();

if ($status === -2 || ($status !== null && $status < 0
    && defined('SOCKET_ETIMEDOUT') && $errCode === SOCKET_ETIMEDOUT)) {
    throw new RuntimeException('upstream timed out');
}

if ($status === null || $status < 0 || ($errCode ?? 0) !== 0) {
    throw new RuntimeException(sprintf(
        'transport error: status=%s, errCode=%s, errMsg=%s',
        $status,
        $errCode,
        $response->getErrMsg()
    ));
}
```

`errCode` 的 getter 允许返回 `null`。因此不能只用 `!== 0` 判断；更不能把所有非 2xx 状态都归类为超时。

## 第二步：判断 HTTP 状态

```php
$status = $response->getStatusCode();

if ($status < 200 || $status >= 300) {
    throw new RuntimeException(sprintf(
        'unexpected HTTP status %d: %s',
        $status,
        $response->getBody()
    ));
}
```

404、429、500 不会自动抛异常。

## 第三步：解析 Body 和业务状态

```php
$payload = json_decode(
    $response->getBody(),
    true,
    512,
    JSON_THROW_ON_ERROR
);

if (($payload['code'] ?? null) !== 0) {
    throw new RuntimeException(
        $payload['message'] ?? 'upstream business error'
    );
}
```

某些接口使用 HTTP 200 返回业务错误，因此还要检查业务字段。

## JSON、JSONP 和 XML

```php
$array = $response->json(true);
$object = $response->json();
$jsonp = $response->jsonp(true);
$xml = $response->xml(true);
```

`json()` 不启用 `JSON_THROW_ON_ERROR`。严格校验应直接使用带 `JSON_THROW_ON_ERROR` 的 `json_decode()`。

## URL 异常

无效 URL、Host 为空或协议不受支持时会抛出 `InvalidUrl`：

```php
use EasySwoole\HttpClient\Exception\InvalidUrl;

try {
    $response = (new HttpClient($url))->get();
} catch (InvalidUrl $error) {
    // 配置错误，不是临时网络故障。
}
```

用户能影响 URL 时要限制域名和目标 IP，防止 SSRF。

## 重试原则

只有幂等操作或具备可靠幂等键时才重试，并设置次数、退避和总超时。下单、支付等非幂等 POST 可能已经被服务端执行，不能因客户端超时直接重试。
