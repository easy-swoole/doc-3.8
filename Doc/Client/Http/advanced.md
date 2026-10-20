# HTTP Client 高级用法与错误处理

## 响应对象

请求返回 `EasySwoole\HttpClient\Bean\Response`：

```php
$statusCode = $response->getStatusCode();
$headers = $response->getHeaders();
$body = $response->getBody();
$cookies = $response->getCookies();
$errorCode = $response->getErrCode();
$errorMessage = $response->getErrMsg();
```

推荐按三层判断：

```php
if (($response->getStatusCode() ?? -1) < 0 || ($response->getErrCode() ?? 0) !== 0) {
    throw new RuntimeException(sprintf(
        'transport error [%s]: %s',
        $response->getErrCode(),
        $response->getErrMsg()
    ));
}

if ($response->getStatusCode() < 200 || $response->getStatusCode() >= 300) {
    throw new RuntimeException(
        'HTTP error: ' . $response->getStatusCode()
    );
}

$payload = json_decode(
    $response->getBody(),
    true,
    512,
    JSON_THROW_ON_ERROR
);

if (($payload['code'] ?? null) !== 0) {
    throw new RuntimeException($payload['message'] ?? 'business error');
}
```

`$response->json(true)` 可以快速返回数组，但不会开启 `JSON_THROW_ON_ERROR`；严格校验时应直接使用 `json_decode()`。

## 重定向

默认最多跟随 3 次 `301`、`302`、`303`、`307` 或 `308`：

```php
$client->setFollowLocation(5);
```

禁止自动跟随：

```php
$client->setFollowLocation(0);
```

当前实现中，`301/302` 会把 POST 转成 GET；`303` 会把除 HEAD 外的方法转成 GET；`307/308` 则保留方法与请求体。跨 origin 跳转会移除 Authorization、Proxy-Authorization 和 Cookie。若业务要求严格控制跳转目标或整条重定向链的耗时，可关闭自动跳转并自行处理 `Location`。每次自动跳转都会再次请求，因此[单次连接/读写超时](/Client/Http/timeout.md)不等于整条链的截止时间。

## HTTPS 与代理

```php
$client->setSslVerifyPeer(true)
    ->setSslHostName('api.example.com')
    ->setSslCafile('/etc/ssl/certs/ca-bundle.crt');
```

HTTP 和 SOCKS5 代理：

```php
$client->setProxyHttp('127.0.0.1', 8080, 'user', 'password');
$client->setProxySocks5('127.0.0.1', 1080, 'user', 'password');
```

生产环境不要为了绕过错误关闭 TLS 校验，应修复域名、证书链或 CA 配置。

## 上传文件

```php
$client = new HttpClient('https://api.example.com/upload');

$response = $client->post([
    'category' => 'avatar',
    'file' => new \CURLFile(
        '/data/avatar.png',
        'image/png',
        'avatar.png'
    ),
]);
```

上传前应校验路径、大小、MIME 类型和文件名，不要直接接受用户传入的任意服务器路径。

## 下载大文件

`download()` 直接写磁盘，不在内存中拼接整个 Body：

```php
$client = new HttpClient('https://cdn.example.com/archive.zip');
$client->setReadTimeout(60.0);

$response = $client->download('/data/downloads/archive.zip');
if ($response === false) {
    throw new RuntimeException('download failed');
}

if (($response->getStatusCode() ?? -1) < 0
    || ($response->getErrCode() ?? 0) !== 0
    || $response->getStatusCode() !== 200) {
    throw new RuntimeException('download response error');
}
```

第二个参数是偏移量，可配合支持 Range 的服务端续传：

```php
$offset = is_file($filename) ? filesize($filename) : 0;
$response = $client->download($filename, $offset);
```

建议先下载到临时文件，校验状态、大小和哈希后再移动到正式路径。

## WebSocket 客户端

```php
$client = new HttpClient('wss://socket.example.com/ws');
$client->setHeader('Authorization', 'Bearer AbCdEf123', false);

if (!$client->upgrade()) {
    throw new RuntimeException('websocket upgrade failed');
}

$client->push(json_encode(['action' => 'ping'], JSON_THROW_ON_ERROR));
$frame = $client->recv(5.0);

if ($frame === false || $frame === '') {
    throw new RuntimeException('websocket receive failed');
}

echo $frame->data;
```

WebSocket 是长连接，应在同一协程中维护读取循环、心跳和关闭逻辑，不要让多个协程同时读取同一个客户端。

## 重试与安全

只有幂等操作或具备可靠幂等键时才自动重试，并设置最大次数、退避和总超时。下单、支付等非幂等 POST 不能因网络异常盲目重试。

URL 包含用户输入时，应使用域名白名单并禁止访问环回、内网和云元数据地址，避免 SSRF。
