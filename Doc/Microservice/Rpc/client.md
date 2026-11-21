# 发起 RPC 调用

## 用固定节点验证

按[服务端示例](/Microservice/Rpc/server.md)启动服务后，在同一个项目根目录创建 `rpc-client.php`。这个 CLI 进程独立初始化 `MyRpc`，并为 `User` 服务指定本机节点。

```php
<?php

use App\Rpc\MyRpc;
use EasySwoole\Rpc\Config\RpcConfig;
use EasySwoole\Rpc\Config\SecurityConfig;
use EasySwoole\Rpc\Server\ServiceNode;

require __DIR__ . '/vendor/autoload.php';

MyRpc::getInstance(new RpcConfig(
    security: new SecurityConfig(apiKey: 'local-demo-key'),
));

MyRpc::getInstance()->getNodeManager()->online(new ServiceNode(
    serviceName: 'User',
    nodeId: 'user-rpc-1',
    nodeName: 'user-rpc-1',
    nodeWeight: 10,
    host: '127.0.0.1',
    port: 9601,
));

\Swoole\Coroutine\run(static function (): void {
    $batch = MyRpc::getInstance()->client()->buildRequest();
    $batch->addCall('User.Profile.detail')->setArg(['id' => 1001]);
    $response = $batch->exec(timeout: 1.0)['User.Profile.detail'];

    if (!$response->isSuccess()) {
        throw new RuntimeException(sprintf(
            '%s: %s',
            $response->getStatus()->name,
            $response->getMsg(),
        ));
    }

    echo $response->toJson(), PHP_EOL;
});
```

运行 `php rpc-client.php`。响应的 `status` 为 `0`，`result` 包含 `id`、`name` 和 `requestUUID`。业务只需要 Action 返回值时，使用 `$response->getResult()`。

## 在 HTTP Worker 中使用

在启用了协程的控制器或业务服务中，从 `MyRpc::getInstance()->client()->buildRequest()` 开始创建每次请求自己的批次，直接执行上面的调用代码。节点应已由应用配置或[服务发现](/Microservice/Rpc/discovery.md)提供。

同一批次可用 `addCall()` 加入多个不同路径，`exec()` 并发执行，按完整路径返回 `Response`。每个路径在同一批次中只能加入一次。`timeout` 是单个调用的总预算，单位为秒，连接、收发和重试共用该预算。

| 响应状态 | 排查方向 |
| --- | --- |
| `NOT_AVAILABLE_NODE` | 检查服务名、节点登记和节点有效期 |
| `NODE_LOOKUP_FAILED` | 检查注册中心或自定义节点管理器 |
| `TRANSPORT_ERROR` | 检查通告的 TCP 地址、端口和网络连通性 |
| `RESPONSE_DECODE_ERROR` | 检查 API key、时钟、响应内容和请求 UUID |

## 单次调用的回调

在协程内为每个调用分别设置回调。下面的查询是只读操作，允许在节点故障策略许可且还有时间预算时重试一次。

```php
use App\Rpc\MyRpc;
use EasySwoole\Rpc\Protocol\Response;

$batch = MyRpc::getInstance()->client()->buildRequest();
$batch->addCall('User.Profile.detail')
    ->setArg(['id' => 1001])
    ->setClientArg(['traceId' => 'trace-001'])
    ->enableRetry(1)
    ->setOnSuccess(static function (Response $response): void {
        // 这里可以记录成功指标，结果仍可从 exec() 读取。
        error_log('[RPC OK] ' . $response->getRequestUUID());
    })
    ->setOnFail(static function (Response $response): void {
        error_log('[RPC failed] ' . $response->getStatus()->name);
    });

$responses = $batch->exec(timeout: 3.0);
$response = $responses['User.Profile.detail'] ?? null;
```

`setArg()` 传业务参数，`setClientArg()` 传链路 ID 等附加信息，服务端通过 `Request::getClientArg()` 读取。成功和失败回调接收最终的 `Response`。想在框架选节点之外指定目标时，可以对调用设置 `setServiceNode($node)`，节点所属服务须与路径第一段一致。

每个批次只执行一次，后续调用重新执行 `buildRequest()`。默认关闭重试。默认故障策略根据节点健康标记与连续失败次数决定是否保留、换节点尝试或下线。网络超时后 Action 可能已执行，写操作需有业务幂等保障才能重试。

## 客户端全局异常回调

在调用方初始化 `MyRpc` 后注册一次：

```php
use App\Rpc\MyRpc;

MyRpc::getInstance()->client()->setOnException(static function (\Throwable $error): void {
    error_log('[RPC client exception] ' . $error->getMessage());
});
```

常见网络失败和无可用节点通过失败 `Response` 返回。未预期的节点查询、选择策略或调用回调异常进入客户端全局回调。未配置回调时，异常会从调用协程抛出。配置回调接管异常后，若异常发生在取得响应之前，`exec()` 的结果会缺少对应路径。若已取得响应，调用回调抛出的异常仍会上报，但响应会保留。批次创建、非法路径和调用环境等同步错误应在对应调用处捕获 `RpcException`。

- [客户端与批次实现（6.0.1）](https://github.com/easy-swoole/rpc/tree/6.0.1/src/Client)

## 版本与 GitHub

- [`easyswoole/rpc` 6.0.1 · GitHub](https://github.com/easy-swoole/rpc/tree/6.0.1)
