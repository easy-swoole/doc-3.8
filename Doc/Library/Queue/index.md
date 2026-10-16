# 可信队列：安装与基本概念

`easyswoole/queue` 用于在协程环境中生产和消费队列任务。当前 `5.x` 版本提供 Redis 与 RabbitMQ 驱动，并内置连接池，支持普通任务、延迟任务和需要确认的可信任务。

## 安装

在项目根目录执行：

```bash
composer require easyswoole/queue="^5.0"
```

运行环境要求：

- PHP 8.0 或更高版本。
- Swoole 5.1 或更高版本。
- `phpredis` 扩展。
- 协程运行环境。

组件的 Composer 依赖同时包含 Redis、连接池和 RabbitMQ 客户端。即使只使用 RabbitMQ，当前版本仍要求安装 `ext-redis`。

检查环境：

```bash
php -v
php --ri swoole
php --ri redis
composer show easyswoole/queue
```

## 三种任务

| 类型 | 配置方式 | 消费成功后 | 适合场景 |
| --- | --- | --- | --- |
| 普通任务 | 默认配置 | 从队列移除，无需确认 | 可容忍消费进程异常导致任务丢失的轻量工作 |
| 延迟任务 | `setDelayTime()` | 到期后才能消费 | 延迟检查、稍后通知 |
| 可信任务 | `setRetryTimes()` 大于 0 | 必须调用 `confirm()` | 订单处理、发送通知等不能静默丢失的工作 |

延迟和可信是两个独立维度，同一个 Job 可以既延迟执行，又要求消费确认。

## 核心对象关系

```text
Queue（持有驱动模板和当前节点 ID）
├── producer('order') → Producer → push(Job)
└── consumer('order') → Consumer → pop()/listen()/confirm()
```

传给 `producer()`、`consumer()` 的字符串是 topic 名。`Queue` 会按 topic 缓存 Producer 和 Consumer；第一次访问某个 topic 时，会克隆驱动并调用 `init()`。

## 最小示例

下面使用 Redis 单机驱动。代码必须在协程环境中执行：

```php
<?php

use EasySwoole\Queue\Driver\Redis\Config;
use EasySwoole\Queue\Driver\Redis\Redis as RedisDriver;
use EasySwoole\Queue\Job;
use EasySwoole\Queue\Queue;
use Swoole\Coroutine;

require __DIR__ . '/vendor/autoload.php';

Coroutine::set(['hook_flags' => SWOOLE_HOOK_TCP]);

Coroutine\run(function (): void {
    $config = new Config();
    $config->setHost('127.0.0.1');
    $config->setPort(6379);
    $config->setMinObjectNum(1);
    $config->setMaxObjectNum(20);

    $queue = new Queue(new RedisDriver($config));

    $job = new Job();
    $job->setJobData(['orderId' => 1001]);
    $queue->producer('order')->push($job);

    $job = $queue->consumer('order')->pop(1.0);
    if ($job !== null) {
        var_dump($job->getJobData());
    }
});
```

输出类似：

```text
array(1) {
  ["orderId"]=>
  int(1001)
}
```

## 如何选择驱动

| 需求 | 建议 |
| --- | --- |
| 项目已有 Redis，希望快速接入 | Redis 单机 |
| Redis 已采用 Cluster | Redis Cluster |
| 需要 Broker 持久化、AMQP 运维能力 | RabbitMQ |
| 延迟时间差异很大且要求严格到点 | 优先评估 Redis；RabbitMQ TTL 队列存在队首阻塞特点 |

无论选择哪个驱动，可信任务都是“至少投递一次”，不是“恰好一次”。网络在确认临界点中断时，业务可能再次收到同一个任务，因此消费逻辑必须幂等。

下一章：[Redis 驱动](/Library/Queue/redis.md)。

## 源码依据

- [Queue 5.x](https://github.com/easy-swoole/queue/tree/5.x)
- [Queue 核心类](https://github.com/easy-swoole/queue/blob/5.x/src/Queue.php)
