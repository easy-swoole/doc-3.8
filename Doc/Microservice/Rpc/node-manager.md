# 集中式注册与自定义节点管理器

多个独立部署的提供方和网关可以使用同一个 Redis、Etcd 或 Consul 维护节点记录。提供方的 RPC 辅助进程负责上线、续约和下线，调用方按服务名读取节点。集中式模式下，两端都可以保持 UDP 关闭。

## 实现节点管理接口

继承 `EasySwoole\Rpc\AbstractInterface\AbstractNodeManager`：

| 方法 | 注册中心操作 |
| --- | --- |
| `online(ServiceNode $node): bool` | 按服务名和节点 ID 写入节点及其有效期 |
| `heartbeat(ServiceNode $node): bool` | 续约。节点记录已过期时，重新写入可以恢复注册 |
| `offline(ServiceNode $node): bool` | 删除对应节点，重复删除也可以返回成功 |
| `getNodes(string $serviceName): array\|false` | 返回当前有效的节点列表。无节点返回空数组，注册中心暂时不可用返回 `false` |
| `nodeTtlSeconds(): ?int` | 后端有固定 TTL 时返回秒数，供框架检查心跳周期 |

节点管理器会在 Swoole 派生进程前创建。构造时只保存配置，连接应在实际操作所在的进程中建立。复用连接时要按 PID 隔离，并避免让多个并发协程共用一条未经隔离的连接。

## Redis 示例

安装并启用 PHP 的 `redis` 扩展。以下示例使用一台 Redis，适合验证接口和节点生命周期。每次操作独立建连，高调用量的应用可在各进程中通过协程连接池复用连接。示例按服务名前缀用 `SCAN` 查找节点，节点较多时可根据注册中心的规模维护服务索引。

新建 `App/Rpc/RedisNodeManager.php`：

```php
<?php

namespace App\Rpc;

use EasySwoole\Rpc\AbstractInterface\AbstractNodeManager;
use EasySwoole\Rpc\Server\ServiceNode;

final class RedisNodeManager extends AbstractNodeManager
{
    public function __construct(
        private readonly string $host,
        private readonly int $port = 6379,
    ) {}

    public function nodeTtlSeconds(): int
    {
        return 15;
    }

    public function online(ServiceNode $node): bool
    {
        $payload = json_encode($node, JSON_THROW_ON_ERROR);
        return $this->withRedis(
            fn (\Redis $redis) => $redis->setex($this->key($node), $this->nodeTtlSeconds(), $payload)
        );
    }

    public function heartbeat(ServiceNode $node): bool
    {
        return $this->online($node);
    }

    public function offline(ServiceNode $node): bool
    {
        return $this->withRedis(fn (\Redis $redis) => $redis->del($this->key($node)) !== false);
    }

    public function getNodes(string $serviceName): array|false
    {
        return $this->withRedis(function (\Redis $redis) use ($serviceName): array|false {
            $cursor = null;
            $nodes = [];
            $prefix = $this->prefix($serviceName);
            do {
                $keys = $redis->scan($cursor, $prefix . '*', 100);
                if ($keys === false && $redis->getLastError() !== null) {
                    return false;
                }
                foreach ($keys ?: [] as $key) {
                    $payload = $redis->get($key);
                    if ($payload === false) {
                        if ($redis->getLastError() !== null) {
                            return false;
                        }
                        continue; // 节点可能在扫描后过期。
                    }
                    $nodes[$key] = ServiceNode::fromArray(json_decode($payload, true, flags: JSON_THROW_ON_ERROR));
                }
            } while ((int) $cursor !== 0);

            return array_values($nodes);
        });
    }

    private function prefix(string $serviceName): string
    {
        return 'app:rpc:' . bin2hex($serviceName) . ':';
    }

    private function key(ServiceNode $node): string
    {
        return $this->prefix($node->getServiceName()) . bin2hex($node->getNodeId());
    }

    private function withRedis(callable $operation): mixed
    {
        $redis = new \Redis();
        try {
            if (!$redis->connect($this->host, $this->port, 0.3, null, 0, 0.3)) {
                return false;
            }

            return $operation($redis);
        } catch (\RedisException) {
            return false;
        } finally {
            if ($redis->isConnected()) {
                $redis->close();
            }
        }
    }
}
```

每个节点独立设置 15 秒 TTL。服务端实际心跳周期必须短于这个值。各提供方应使用不同的 `nodeId`，同一逻辑实例需要跨重启保持身份时可沿用原 ID。环境间共用 Redis 时，应使用不同键前缀。

## 在提供方和调用方注入

在两端首次创建 `MyRpc` 时传入对应的 `RpcConfig` 和同一注册中心配置。提供方保留[服务注册和进程挂载](/Microservice/Rpc/server.md)，只替换首次初始化这一段。调用方仅使用中心化查询时，可以直接在 Worker 的协程中调用客户端，Redis 节点管理器会在查询时建连。

```php
use App\Rpc\MyRpc;
use App\Rpc\RedisNodeManager;
use EasySwoole\Rpc\Config\RpcConfig;
use EasySwoole\Rpc\Config\RpcDependencies;

MyRpc::getInstance(
    config: $rpcConfig, // 使用本应用的 RpcConfig，双方保持同一个 apiKey。
    dependencies: new RpcDependencies(
        nodeManager: new RedisNodeManager('127.0.0.1'),
    ),
);
```

有自己的 Redis、Etcd 或 Consul 客户端时，可以保留上述接口和注入方式，改用该后端的 TTL 或租约。默认节点选择器会按权重从查询结果中选择节点；有特殊调度要求时，可通过 `RpcDependencies` 注入实现 `NodeSelectorInterface` 的选择器。

- [节点管理器契约（6.0.1）](https://github.com/easy-swoole/rpc/blob/6.0.1/src/AbstractInterface/AbstractNodeManager.php)
- [依赖配置（6.0.1）](https://github.com/easy-swoole/rpc/blob/6.0.1/src/Config/RpcDependencies.php)

## 版本与 GitHub

- [`easyswoole/rpc` 6.0.1 · GitHub](https://github.com/easy-swoole/rpc/tree/6.0.1)
