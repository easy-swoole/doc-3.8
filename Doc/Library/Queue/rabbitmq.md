# 可信队列：RabbitMQ 驱动

Queue 5.0.4 的 RabbitMQ 驱动基于 `easyswoole/amqp:^1.0.1`，网络 I/O 使用 Swoole 协程 Socket。发布和消费使用不同连接池，发布池服务并发 `push()`，消费端使用独立的 `1/1` 长连接池和后台消费协程。调用代码应运行在 Swoole 协程中。

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

生产环境可设置非零 `heartbeat`。客户端会发送协商后的心跳，连接池会对闲置连接执行 AMQP 往返探活。`readWriteTimeout` 控制网络读写超时。

## 消费结构

```text
RabbitMQ Broker
      ↓ basic.get（手动确认）
后台消费协程（独占一个 Channel）
      ↓
本地 Swoole Channel 缓冲区
      ↓ pop()
业务消费协程
      ↓ confirm()
后台消费协程统一 ACK
```

普通任务进入本地缓冲区后立即 ACK；可信任务会保留到业务调用 `confirm()`。可信任务的确认期限从 `pop()` 将任务交给业务时开始计算，本地缓冲等待时间不计入确认期限。ACK、确认超时和重新投递都由拥有原 Channel 的后台协程执行，不会为每条可信任务单独占用一个连接。

## 并发相关配置

| 方法 | 默认值 | 说明 |
| --- | ---: | --- |
| `setPrefetchCount()` | `100` | 后台消费协程持有的未确认可信任务上限，包含本地缓冲中的可信任务 |
| `setConsumerBufferSize()` | `1000` | Broker 消息进入 `pop()` 前的本地协程缓冲区容量 |
| `setPopPollInterval()` | `0.05` | 后台消费空闲时的轮询间隔，秒 |
| `setQueuePrefix()` | `easyswoole.queue.` | RabbitMQ 队列名称前缀 |
| `setTls()` | `null` | 接受 `EasySwoole\AMQP\TlsConfig`，配置 TLS |

`prefetchCount` 达到上限时，后台协程暂停领取可信任务，直到已有任务确认或超时。应按单进程业务并发量、处理耗时和本地缓冲容量调整。单个 topic 的消息领取由一个后台协程串行执行 `basic.get`。

## 延迟任务注意事项

RabbitMQ 驱动通过消息 TTL、延迟队列和 Dead Letter Exchange 实现延迟任务。RabbitMQ 只检查队首消息是否过期；同一延迟队列中混用不同延迟时间时，短延迟消息可能被前面的长延迟消息阻塞。

如果业务要求严格的到点执行，可以采用固定 TTL 的分级队列、RabbitMQ 延迟消息插件，或者评估 Redis 驱动。

## 连接中断

可信任务尚未 ACK 时连接中断，RabbitMQ 会重新投递原消息。确认超时后，驱动会先通过 Publisher Confirm 发布带有最新 `runTimes` 的任务，再 ACK 原消息。连接恢复后，旧投递的回执不能用于确认新投递。确认临界点发生网络异常时仍可能重复，因此业务幂等不可省略。

下一章：[生产、消费与延迟任务](/Library/Queue/usage.md)。

## 版本与 GitHub

- [`easyswoole/queue` 5.0.4 · GitHub](https://github.com/easy-swoole/queue/tree/5.0.4)

- [Queue RabbitMQ 驱动（5.0.4）](https://github.com/easy-swoole/queue/blob/5.0.4/src/Driver/RabbitMQ/RabbitMQ.php)
- [AMQP 客户端（1.0.1）](https://github.com/easy-swoole/amqp/tree/1.0.1)
