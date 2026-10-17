# Consul 客户端：认证、响应与异常

Consul 客户端的方法返回解码后的 PHP 值，不统一包装为一个固定的 Response 类。业务要根据所调用的 API 判断返回类型，并处理连接、鉴权和 Consul 返回的错误。

## 为请求添加 ACL Token

Consul 开启 ACL 后，可以用 `withHeaders()` 给下一次请求添加 Token：

```php
use EasySwoole\Consul\Request\Catalog\Nodes;

$token = getenv('CONSUL_TOKEN');
if (!is_string($token) || $token === '') {
    throw new \RuntimeException('未配置 CONSUL_TOKEN');
}

$nodes = $client->catalog()
    ->withHeaders(['X-Consul-Token' => $token])
    ->nodes(new Nodes());
```

`withHeaders()` 只作用于该端点紧随其后的**一次请求**，发送时会清空；下次调用仍需再次设置。不要把 Token 明文写进仓库或日志。端点对象会由 `ConsulClient` 复用，且待发送 Header 是端点上的临时可变状态；在多个协程共享同一个客户端时，避免在 `withHeaders()` 与实际请求之间做协程切换，或者为不同调用创建独立的客户端对象。

## 返回值怎样解码

默认 Transport 的解码规则如下：

| HTTP 响应 | PHP 结果 |
| --- | --- |
| 合法 JSON | 解码为数组、字符串、布尔值、数值或 `null` |
| 空响应体 | `null` |
| 非 JSON 文本或二进制 | 原始字符串 |
| 网络错误、HTTP 4xx/5xx | 抛出 `ConsulException` |

例如 KV 写入可能返回 `true`，查询普通 KV 返回记录数组，Leader 查询可能返回字符串，服务注册成功后可能返回 `null`。不要对所有方法直接使用 `$result['data']`。

## 捕获异常

```php
use EasySwoole\Consul\Exception\ConsulException;
use EasySwoole\Consul\Request\Status\Leader;

try {
    $leader = $client->status()->leader(new Leader());
} catch (ConsulException $exception) {
    // 网络失败、超时或 Consul 返回 HTTP 错误。
    // 这里可以记录日志，再按业务决定重试或返回错误。
    throw $exception;
}
```

HTTP 错误会优先读取 `X-Consul-Reason` 响应头作为原因，没有该头时使用响应体。缺少 key、服务名、Session ID 等必要参数时，组件还会抛出 `MissingRequiredParameterException`；配置参数错误会抛出 `InvalidArgumentException`。这些属于调用方输入或配置问题，通常不应无条件重试。

## 调用前的检查

- 连接地址指向可用的 Consul Agent；`ClientConfig` 的协议与 Agent 实际配置一致。
- 如果启用了 ACL，当前 Token 对目标 API 有相应权限，并在每次请求前设置 Header。
- KV 的 `Value` 按 Base64 解码，空结果和 HTTP 404 分别处理。
- 服务发现只选择健康实例，连接失败时有重试或降级策略。
- 不复用已经执行过、其路径字段可能被修改的请求对象。

## 源码依据

- [ResponseDecoder](https://github.com/easy-swoole/consul/blob/2.x/src/Http/ResponseDecoder.php)
- [AbstractEndpoint](https://github.com/easy-swoole/consul/blob/2.x/src/AbstractEndpoint.php)
- [请求序列化](https://github.com/easy-swoole/consul/blob/2.x/src/Request/RequestSerializer.php)
