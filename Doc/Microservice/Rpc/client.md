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
