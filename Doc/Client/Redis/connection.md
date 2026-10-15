# Redis 连接的获取与归还

## invoke：回调结束立即归还

```php
use EasySwoole\RedisPool\RedisPool;

$value = RedisPool::invoke(
    static fn (Redis $redis) => $redis->get('demo:key')
);
```

流程：

```text
获取连接 → PING 探活 → 执行回调 → 清理最后错误 → 归还连接
```

指定池名和等待连接的秒数：

```php
$value = RedisPool::invoke(
    static fn (Redis $redis) => $redis->get('demo:key'),
    'cache',
    0.5
);
```

第三个参数不是 Redis 命令超时；命令超时由 `readTimeout` 控制。

## defer：协程结束归还

```php
$redis = RedisPool::defer('default', 0.5);

if ($redis === null) {
    throw new RuntimeException('redis pool is not registered');
}

$redis->set('user:1001:name', 'Tom');
$name = $redis->get('user:1001:name');
```

同一协程重复 `defer()` 会获得同一连接：

```php
$first = RedisPool::defer();
$second = RedisPool::defer();
assert($first === $second);
```

连接在当前协程退出时归还。不要把它交给另一个协程，也不要让永久运行的循环长期持有。

## 检查连接池是否注册

未注册名称会使 `invoke()` 或 `defer()` 返回 `null`。由于 Redis 的 `get()` 也可能返回空值，调用前最好明确检查：

```php
$pool = RedisPool::getInstance()->getPool('cache');
if ($pool === null) {
    throw new RuntimeException('cache pool is not registered');
}
```

## 连接何时被丢弃

- 借出前和定时检查时执行 `PING`。
- 探活失败会 `close()`，不会放回池。
- 正常归还会调用 `clearLastError()`。
- Pool 会重新创建连接补足容量。

命令执行过程中仍可能断线：

```php
try {
    $value = RedisPool::invoke(
        static fn (Redis $redis) => $redis->get('demo:key')
    );
} catch (RedisException $error) {
    throw new RuntimeException('redis unavailable', 0, $error);
}
```

## 状态与预热

预热不是必选项。下面的 `keepMin()` 只用于提前建立连接；不调用时会在第一次获取连接时懒创建：

```php
$pool = RedisPool::getInstance()->getPool('default');
$created = $pool?->keepMin();
$status = $pool?->status();
```

业务获取连接时优先使用 `invoke()` 或 `defer()`，避免直接 `getObj()` 后忘记归还。

下一章：[数据操作与事务](/Client/Redis/usage.md)。
