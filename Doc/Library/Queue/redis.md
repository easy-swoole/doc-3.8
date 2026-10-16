# 可信队列：Redis 驱动

Redis 驱动基于 `phpredis`，支持单机和 Redis Cluster。连接由组件内部的 `easyswoole/pool` 管理，不需要再把 Redis Client 手工放入另一个连接池。

## 启用协程 Hook

`phpredis` 是阻塞客户端，必须在创建协程前启用 TCP Hook。EasySwoole 项目应在根目录 `EasySwooleEvent.php` 的 `initialize()` 中设置：

```php
use Swoole\Coroutine;

public static function initialize()
{
    date_default_timezone_set('Asia/Shanghai');
    Coroutine::set(['hook_flags' => SWOOLE_HOOK_TCP]);
}
```

## Redis 单机

```php
use EasySwoole\Queue\Driver\Redis\Config;
use EasySwoole\Queue\Driver\Redis\Redis as RedisDriver;
use EasySwoole\Queue\Queue;

$config = new Config();
$config->setHost('127.0.0.1');
$config->setPort(6379);
$config->setUsername(null);       // 没有启用 ACL 时保持 null
$config->setPassword('password');
$config->setDatabase(0);
$config->setConnectTimeout(3.0);
$config->setReadTimeout(3.0);
$config->setMinObjectNum(1);
$config->setMaxObjectNum(20);

$queue = new Queue(new RedisDriver($config));
```

`setMinObjectNum()` 应先于比默认值更小的 `setMaxObjectNum()` 调用，否则中间状态可能不满足连接池的数量约束。最小连接数不是业务正确性的必要条件，可按实际并发设置为 0；最大连接数应结合 Redis 上限和每个 Worker/消费进程的数量计算。

## Redis Cluster

```php
use EasySwoole\Queue\Driver\Redis\Config;
use EasySwoole\Queue\Driver\Redis\Redis as RedisDriver;
use EasySwoole\Queue\Queue;

$config = new Config();
$config->setMode(Config::MODE_CLUSTER);
$config->setSeeds([
    '127.0.0.1:7001',
    '127.0.0.1:7002',
    '127.0.0.1:7003',
]);
$config->setUsername(null);
$config->setPassword('password');
$config->setConnectTimeout(3.0);
$config->setReadTimeout(3.0);
$config->setMinObjectNum(1);
$config->setMaxObjectNum(20);

$queue = new Queue(new RedisDriver($config));
```

Cluster 只支持数据库 0，不要调用 `setDatabase()` 选择其他数据库。组件会让同一 topic 的相关 Key 使用相同 hash tag，确保 Lua 脚本涉及的 Key 落在同一个 slot。

## 常用配置

| 方法 | 默认值 | 说明 |
| --- | ---: | --- |
| `setConnectTimeout()` | `3.0` | 建立连接超时，秒 |
| `setReadTimeout()` | `3.0` | 读取超时，秒 |
| `setRetryInterval()` | `0` | 单机连接重试间隔，毫秒 |
| `setPersistent()` | `false` | 是否使用持久连接 |
| `setPersistentId()` | `null` | 持久连接标识；Cluster 中作为集群名称 |
| `setReservationTimeout()` | `30` | 可信任务刚领取时的兜底可见性超时，秒 |
| `setMigrationBatchSize()` | `100` | 单次迁移到期或超时任务的最大数量 |
| `setPopPollInterval()` | `0.05` | 空队列短轮询间隔，秒 |
| `setGetObjectTimeout()` | 继承连接池配置 | 等待连接池对象的超时 |

`pop($timeout)` 在空队列时采用协程短轮询，每轮结束都会归还 Redis 连接，不会在整个等待期间独占一条池连接。

## 数据结构与可靠性

Redis 驱动使用 List 保存待消费任务，用 Sorted Set 保存延迟时间和确认截止时间，用 Hash 保存处理中任务。可信任务的领取、到期迁移和超时恢复通过 Lua 脚本完成，避免多个消费者领取同一份队列状态时产生竞态。

Redis 自身的持久化方式仍会影响数据安全。需要降低 Redis 重启后的消息丢失风险时，应根据业务设置 AOF/RDB、主从和 Cluster，而不是只依赖客户端的 `retryTimes`。

下一章：[RabbitMQ 驱动](/Library/Queue/rabbitmq.md)。
