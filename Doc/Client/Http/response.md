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

## 第一步：判断传输错误

DNS、连接、TLS 和读写超时通过 `errCode` 表示：

```php
if ($response->getErrCode() !== 0) {
    throw new RuntimeException(sprintf(
        'transport error [%d]: %s',
        $response->getErrCode(),
        $response->getErrMsg()
    ));
}
```

不能只判断 Response 是否存在，因为发生传输错误时通常仍会返回 Response。

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
