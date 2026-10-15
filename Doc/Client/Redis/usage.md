# Redis 数据操作与事务

## 常用操作

```php
use EasySwoole\RedisPool\RedisPool;

$result = RedisPool::invoke(function (Redis $redis): array {
    $redis->setEx('demo:prod:user:1001:token', 3600, 'token-value');

    $redis->hMSet('demo:prod:user:1001', [
        'name' => 'Tom',
        'status' => 'active',
    ]);

    return [
        'token' => $redis->get('demo:prod:user:1001:token'),
        'user' => $redis->hGetAll('demo:prod:user:1001'),
    ];
});
```

指定命名池和等待连接超时：

```php
$value = RedisPool::invoke(
    static fn (Redis $redis) => $redis->get('demo:key'),
    'cache',
    0.5
);
```

第三个参数只限制从池中等待连接的时间。Redis 命令超时由 `readTimeout` 控制。

## 事务

`multi()`、所有命令和 `exec()` 必须在同一次借用中完成：

```php
$result = RedisPool::invoke(function (Redis $redis): array {
    $redis->multi();

    try {
        $redis->incrBy('account:1001:balance', -100);
        $redis->incrBy('account:1002:balance', 100);

        $result = $redis->exec();
        if ($result === false) {
            throw new RuntimeException('redis transaction failed');
        }

        return $result;
    } catch (Throwable $error) {
        try {
            $redis->discard();
        } catch (Throwable) {
        }

        throw $error;
    }
});
```

不要分两次 `invoke()` 调用 `multi()` 和 `exec()`，两次可能借到不同连接。组件归还连接时只清除 phpredis 的最后错误，不会自动结束未完成事务，所以异常路径必须 `discard()`。

## Pipeline

```php
$results = RedisPool::invoke(function (Redis $redis): array {
    $pipeline = $redis->multi(Redis::PIPELINE);

    for ($i = 1; $i <= 100; $i++) {
        $pipeline->get("product:{$i}");
    }

    $results = $pipeline->exec();
    if ($results === false) {
        throw new RuntimeException('redis pipeline failed');
    }

    return $results;
});
```

Pipeline 减少网络往返，但批次过大会增加内存和连接占用时间，应分批处理。

## Cluster

```php
$value = RedisPool::invoke(
    static fn (RedisCluster $redis) => $redis->get('user:{1001}:profile'),
    'cluster'
);
```

Cluster 的多键命令、事务和 Lua 脚本通常要求 Key 位于同一 Slot。使用相同 Hash Tag：

```text
user:{1001}:profile
user:{1001}:settings
```

## 异常处理

借出前连接池会执行 `PING`，但命令执行期间仍可能断线：

```php
try {
    $value = RedisPool::invoke(
        static fn (Redis $redis) => $redis->get('demo:key')
    );
} catch (RedisException $error) {
    throw new RuntimeException('redis unavailable', 0, $error);
}
```

写命令连接异常时，客户端无法确定服务端是否已执行。除非操作天然幂等或有幂等键，否则不要盲目重试。

## 不适合普通连接池的操作

以下操作会长期独占连接或改变连接状态：

- `SUBSCRIBE`、`PSUBSCRIBE`。
- 无限期执行的 `BLPOP`、`BRPOP`。
- 长时间运行的消费循环。

应在专用自定义进程中创建专用 Redis 连接并自行处理重连和退出，不要占用普通请求连接池。
