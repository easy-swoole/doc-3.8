# HTTP Client 超时配置与判定

`easyswoole/http-client` 的超时方法只是把配置写入底层 `Swoole\Coroutine\Http\Client::set()`；`get()`、`post()` 等调用并不会因超时自动抛出异常。普通 HTTP 请求仍返回 `Response`，应同时检查其**状态码和错误码**。先看[发送请求](/Client/Http/request.md)了解请求写法。

## 四个超时各管什么

```php
use EasySwoole\HttpClient\HttpClient;

$client = new HttpClient('https://api.example.com/orders');
$client->setTimeout(5.0)
    ->setConnectTimeout(1.0)
    ->setWriteTimeout(2.0)
    ->setReadTimeout(3.0);

$response = $client->get();
```

| 方法 | 传给 Swoole 的键 | 作用 |
| --- | --- | --- |
| `setTimeout(5.0)` | `timeout` | 未单独指定阶段超时时的基础值 |
| `setConnectTimeout(1.0)` | `connect_timeout` | 建立连接阶段，覆盖该阶段的基础值 |
| `setWriteTimeout(2.0)` | `write_timeout` | 写入请求阶段，覆盖该阶段的基础值 |
| `setReadTimeout(3.0)` | `read_timeout` | 等待/读取响应阶段，覆盖该阶段的基础值 |

单位是**秒**，支持浮点数，例如 `0.5` 为 500 毫秒。Swoole 文档把 `timeout` 称为总超时设置，但单独配置的阶段超时会覆盖它在对应阶段的值。**不要把上例的 5 秒理解为 `get()` 无论如何都会在 5 秒内结束**：连接、发送、读取分别受各自设置控制；本组件还可能跟随多次重定向，每次都会再次执行请求。业务要限制包含重定向、重试及处理代码在内的整段耗时，需要额外设计整体截止时间，而不只是调用 `setTimeout()`。

没有提供这些值时，使用当前 Swoole 运行环境的默认超时；生产环境应按上游服务的实际延迟明确设置，不建议无限等待。Keep-Alive 复用已有连接时不会再经历一次新建连接，排查时也要看连接是否复用。

## 超时不是 HTTP 408 或 504

`getStatusCode()` 返回 `408`、`504` 等**正数**，代表收到了服务器或网关的 HTTP 响应，不是客户端本地超时。底层 Swoole 的**负数**状态才表示请求没有得到正常 HTTP 响应：

| `getStatusCode()` | 含义 | 是不是超时 |
| --- | --- | --- |
| `-2` | 请求等待响应超时 | 是，直接判定 |
| `-1` | 连接失败 | 不一定；结合 `getErrCode()` 判断是否连接超时 |
| `-4` | 发送失败 | 不一定；结合 `getErrCode()` 判断是否发送超时 |
| `-3` | 服务端重置连接 | 通常不是超时 |
| `408` / `504` | 上游返回的 HTTP 状态 | 不是客户端本地超时，按 HTTP 错误处理 |

`getErrCode()` 是底层 Socket/Swoole 错误码，`getErrMsg()` 是错误说明。连接或发送阶段的超时通常会有 `SOCKET_ETIMEDOUT`；但不能只检查错误码，因为 `-2` 本身就代表请求超时，而错误码在不同阶段和版本可能不同。也不能把**所有**负数状态都叫超时，例如拒绝连接、DNS 错误和连接重置都需要单独处理。

## 可复制的判定顺序

下面的代码放在协程环境中，例如控制器 Action、Task 或 `Swoole\Coroutine\run()` 内：

```php
use EasySwoole\HttpClient\HttpClient;

$client = new HttpClient('https://api.example.com/orders');
$client->setTimeout(5.0)
    ->setConnectTimeout(1.0)
    ->setReadTimeout(3.0)
    ->setWriteTimeout(2.0);

$response = $client->get();
$status = $response->getStatusCode();
$errCode = $response->getErrCode();
$timedOut = $status === -2
    || ($status !== null && $status < 0
        && defined('SOCKET_ETIMEDOUT')
        && $errCode === SOCKET_ETIMEDOUT);

if ($timedOut) {
    throw new RuntimeException(sprintf(
        'upstream timeout: status=%s, errCode=%s, errMsg=%s',
        $status,
        $errCode,
        $response->getErrMsg()
    ));
}

if ($status === null || $status < 0 || ($errCode ?? 0) !== 0) {
    throw new RuntimeException(sprintf(
        'upstream transport error: status=%s, errCode=%s, errMsg=%s',
        $status,
        $errCode,
        $response->getErrMsg()
    ));
}

if ($status < 200 || $status >= 300) {
    throw new RuntimeException('upstream HTTP error: ' . $status);
}

$body = $response->getBody();
```

`SOCKET_ETIMEDOUT` 由 PHP sockets 扩展提供；通过 `defined()` 检查，可避免未启用该扩展时引用未定义常量。这里把 `null` 错误码当作“没有已报告的 Socket 错误”，**但仍先检查状态码**；直接写 `$response->getErrCode() !== 0` 可能把 `null` 误判为失败。错误码和负数状态都应记录，便于区分 DNS、连接、发送和读取问题。

## 失败后能否重试

客户端超时并不证明上游没有处理请求。尤其是 POST 下单、支付等操作，可能是请求已经到达，上游响应却未及时返回。只对幂等请求或具有可靠幂等键的业务做有限次数的重试，并控制**整段业务耗时**。发生超时后不要让多个协程并发复用同一个 `HttpClient` 实例。

`download()` 与普通请求不同：底层下载失败时直接返回 `false`，没有 `Response` 可读；必须先判断 `=== false`，再检查成功返回的响应状态。WebSocket 的 `recv($timeout)` 是另一个独立的等待超时参数，不等于上述 HTTP 请求超时。

下一章：[处理响应](/Client/Http/response.md)。

## 源码依据

- [HTTP Client 最新 README：超时与长连接](https://github.com/easy-swoole/http-client/blob/master/README.md)
- [Request.php：四个超时设置](https://github.com/easy-swoole/http-client/blob/master/src/Traits/Request.php)
- [HttpClient.php：请求、响应与下载](https://github.com/easy-swoole/http-client/blob/master/src/HttpClient.php)
- [Swoole 协程客户端超时设置](https://openswoole.com/docs/modules/swoole-coroutine-client-timeouts)
- [Swoole HTTP 客户端负数状态码](https://openswoole.com/docs/modules/swoole-coroutine-http-client-getstatuscode)
