# 可信队列：RabbitMQ 驱动

RabbitMQ 驱动基于 `php-amqplib/php-amqplib`。发布和消费使用不同连接池：发布池服务并发 `push()`，消费端使用一个独立的 `1/1` 长连接池和后台消费协程。

## 启用协程 Hook

`php-amqplib` 内部使用 `stream_select()`，因此必须在协程启动前同时启用 TCP 和 Stream Hook：

```php
use Swoole\Coroutine;

public static function initialize()
{
    Coroutine::set([
        'hook_flags' => SWOOLE_HOOK_TCP | SWOOLE_HOOK_STREAM_FUNCTION,
    ]);
}
```

在提供 `SWOOLE_HOOK_STREAM_SELECT` 的 Swoole 版本中，它与 `SWOOLE_HOOK_STREAM_FUNCTION` 表示相同的 Stream Hook。

## 创建队列

```php
use EasySwoole\Queue\Driver\RabbitMQ\Config;
use EasySwoole\Queue\Driver\RabbitMQ\RabbitMQ;
use EasySwoole\Queue\Queue;

$config = new Config();
$config->setHost('127.0.0.1');
$config->setPort(5672);
$config->setUsername('easyswoole');
$config->setPassword('password');
$config->setVirtualHost('/easyswoole');
$config->setConnectTimeout(3.0);
$config->setReadWriteTimeout(25.0);
$config->setHeartbeat(10);
$config->setMinObjectNum(1);
$config->setMaxObjectNum(20);

$queue = new Queue(new RabbitMQ($config));
```

生产环境建议启用非零 heartbeat，以发现静默断线和 TCP 半开连接。`readWriteTimeout` 至少应为 heartbeat 的两倍，例如 heartbeat 为 10 秒时设置 25 秒。

## 消费结构

```text
RabbitMQ Broker
      ↓ basic_consume
后台消费协程（独占一个 Channel）
      ↓
本地 Swoole Channel 缓冲区
      ↓ pop()
业务消费协程
      ↓ confirm()
后台消费协程统一 ACK
```

普通任务进入本地缓冲区后立即 ACK；可信任务会保留到业务调用 `confirm()`。ACK、确认超时和重新投递都由拥有原 Channel 的后台协程执行，不会为每条可信任务单独占用一个连接。

## 并发相关配置

| 方法 | 默认值 | 说明 |
| --- | ---: | --- |
| `setPrefetchCount()` | `100` | 单个消费 Channel 允许同时处理中、尚未确认的可信任务数 |
| `setConsumerBufferSize()` | `1000` | Broker 消息进入 `pop()` 前的本地协程缓冲区容量 |
| `setPopPollInterval()` | `0.05` | 空队列短轮询间隔，秒 |
| `setQueuePrefix()` | `easyswoole.queue.` | RabbitMQ 队列名称前缀 |
| `setKeepalive()` | `false` | TCP keepalive |

`prefetchCount` 不是越大越好。它过大时，单进程会积压过多未确认任务，并增加 `confirm()` 指令排队时间。应从默认值开始，根据消费进程的实际并发量和单任务耗时调整。

## 延迟任务注意事项

RabbitMQ 驱动通过消息 TTL、延迟队列和 Dead Letter Exchange 实现延迟任务。RabbitMQ 只检查队首消息是否过期；同一延迟队列中混用不同延迟时间时，短延迟消息可能被前面的长延迟消息阻塞。

如果业务要求严格的到点执行，可以采用固定 TTL 的分级队列、RabbitMQ 延迟消息插件，或者评估 Redis 驱动。

## 连接中断

可信任务尚未 ACK 时连接中断，RabbitMQ 会重新投递原消息。确认超时后，驱动会先通过 Publisher Confirm 发布带有最新 `runTimes` 的任务，再 ACK 原消息。即便如此，确认临界点发生网络异常时仍可能重复，因此业务幂等不可省略。

下一章：[生产、消费与延迟任务](/Library/Queue/usage.md)。
