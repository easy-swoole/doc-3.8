# 可信队列：可信任务与框架接入

可信任务采用“至少投递一次”语义：任务不会因为消费者领取后异常退出而直接消失，但同一个任务可能被执行多次。

## 投递可信任务

```php
use EasySwoole\Queue\Job;

$job = new Job();
$job->setJobId('order-paid-1001');
$job->setJobData(['orderId' => 1001]);
$job->setRetryTimes(3);
$job->setWaitConfirmTime(10);

if (!$queue->producer('order')->push($job)) {
    throw new RuntimeException('任务入队失败');
}
```

`retryTimes=3` 表示任务最多投递 3 次。每次交给业务时 `runTimes` 会增加，达到最大次数后不再重新交给业务处理。

## 消费、确认与重投

```php
$consumer = $queue->consumer('order');
$job = $consumer->pop(3.0);

if ($job !== null) {
    try {
        OrderService::handlePaid($job->getJobData());

        if (!$consumer->confirm($job)) {
            throw new RuntimeException('队列确认失败');
        }
    } catch (Throwable $throwable) {
        // 不确认：等待 waitConfirmTime 到期后重新投递。
        error_log($throwable->__toString());
    }
}
```

流程如下：

```text
push(retryTimes > 0)
        ↓
消费者 pop，runTimes + 1
        ↓
在 waitConfirmTime 内处理业务
  ├── 成功并 confirm → 本次任务完成
  └── 未确认/进程异常 → 到期后重新投递
                              ↓
                    达到 retryTimes 后停止投递
```

`confirm()` 必须接收本次 `pop()` 返回的同一个 Job，因为驱动已经把消费回执写入其中。不要自行创建新 Job 去确认，也不要设置 `queueReceiptId`。

## 幂等处理

“至少一次”意味着以下情况都可能导致重复：

- 业务已经提交数据库事务，但 `confirm()` 前进程退出。
- Broker 已收到确认，客户端却在响应到达前断线。
- 调用方认为 `push()` 失败并重试，但第一次发布实际已经成功。

可以使用业务唯一键保证幂等：

```php
public static function handlePaid(array $data): void
{
    $eventId = (string) $data['eventId'];

    FastDb::getInstance()->transaction(function () use ($eventId, $data): void {
        // queue_event.event_id 建立唯一索引。
        $created = QueueEvent::createIfAbsent($eventId);
        if (!$created) {
            return; // 已处理过，视为成功，随后仍应 confirm。
        }

        Order::markPaid((int) $data['orderId']);
    });
}
```

幂等记录与业务变更应尽量放在同一个数据库事务中。任务重复但业务已完成时，应把它当作成功并执行 `confirm()`，否则它会持续重投直到耗尽次数。

## 在配置文件中保存连接参数

编辑 `dev.php` 和 `produce.php`，加入项目自己的队列配置：

```php
'QUEUE' => [
    'REDIS' => [
        'host' => '127.0.0.1',
        'port' => 6379,
        'password' => null,
        'database' => 0,
        'poolMin' => 1,
        'poolMax' => 20,
    ],
],
```

生产环境密码建议通过环境变量或密钥服务注入，不要提交到 Git。

## 建立队列工厂

新建 `App/Queue/QueueFactory.php`。队列对象应在实际 Worker 或自定义进程中创建，不要在 Master 进程提前建立网络连接后再 fork：

```php
<?php

namespace App\Queue;

use EasySwoole\EasySwoole\Config as FrameworkConfig;
use EasySwoole\Queue\Driver\Redis\Config;
use EasySwoole\Queue\Driver\Redis\Redis as RedisDriver;
use EasySwoole\Queue\Queue;

final class QueueFactory
{
    private static ?Queue $queue = null;

    public static function getInstance(): Queue
    {
        if (self::$queue !== null) {
            return self::$queue;
        }

        $data = FrameworkConfig::getInstance()->getConf('QUEUE.REDIS');

        $config = new Config();
        $config->setHost((string) $data['host']);
        $config->setPort((int) $data['port']);
        $config->setPassword($data['password']);
        $config->setDatabase((int) $data['database']);
        $config->setMinObjectNum((int) $data['poolMin']);
        $config->setMaxObjectNum((int) $data['poolMax']);

        return self::$queue = new Queue(new RedisDriver($config));
    }
}
```

静态属性只在当前进程内共享：每个 HTTP Worker 和自定义消费进程都会创建自己的 Queue 及连接池，这符合 Swoole 多进程模型。

## 在控制器中生产任务

```php
use App\Queue\QueueFactory;
use EasySwoole\Queue\Job;

public function create(): void
{
    $orderId = 1001;

    $job = new Job();
    $job->setJobId('order-created-' . $orderId);
    $job->setJobData([
        'eventId' => 'order-created-' . $orderId,
        'orderId' => $orderId,
    ]);
    $job->setRetryTimes(3);
    $job->setWaitConfirmTime(30);

    $success = QueueFactory::getInstance()
        ->producer('order')
        ->push($job);

    $this->writeJson($success ? 200 : 503, ['queued' => $success]);
}
```

入队成功只表示驱动已经接受任务，不表示业务已经消费完成。需要向客户端返回最终处理结果时，应使用业务状态表、轮询或回调，而不是阻塞 HTTP 请求等待消费者。

## 使用自定义进程消费

新建 `App/Process/OrderQueueConsumer.php`：

```php
<?php

namespace App\Process;

use App\Queue\QueueFactory;
use App\Service\FailedQueueService;
use App\Service\OrderService;
use EasySwoole\Component\Process\AbstractProcess;
use EasySwoole\Queue\Job;

class OrderQueueConsumer extends AbstractProcess
{
    private bool $running = true;

    protected function run($arg): void
    {
        $consumer = QueueFactory::getInstance()->consumer('order');

        while ($this->running) {
            $job = null;

            try {
                $job = $consumer->pop(1.0);
                if (!$job instanceof Job) {
                    continue;
                }

                OrderService::handlePaid($job->getJobData());

                if ($job->getRetryTimes() > 0 && !$consumer->confirm($job)) {
                    throw new \RuntimeException('队列确认失败');
                }
            } catch (\Throwable $throwable) {
                $this->onException($throwable, $job);

                if ($job instanceof Job && $job->getRunTimes() >= $job->getRetryTimes()) {
                    // 当前已经是最后一次业务投递：把任务和异常写入项目自己的失败表，
                    // 交给告警或人工补偿流程处理。
                    FailedQueueService::record($job, $throwable);
                }

                // 可信任务不确认，等待超时重投。
            }
        }
    }

    protected function onSigTerm(): void
    {
        $this->running = false;
    }

    protected function onException(\Throwable $throwable, ...$args): void
    {
        error_log($throwable->__toString());
    }
}
```

然后在 `EasySwooleEvent.php` 的 `mainServerCreate()` 中注册：

```php
use App\Process\OrderQueueConsumer;
use EasySwoole\Component\Process\Config;
use EasySwoole\Component\Process\Manager;

public static function mainServerCreate(EventRegister $register)
{
    $config = new Config();
    $config->setProcessName('OrderQueueConsumer');
    $config->setProcessGroup('QueueConsumer');
    $config->setEnableCoroutine(true);
    $config->setPipeType(Config::PIPE_TYPE_NONE);

    Manager::getInstance()->addProcess(
        new OrderQueueConsumer($config)
    );
}
```

修改自定义进程注册或连接配置后应完整重启服务。普通 `server reload` 只替换 Worker，不会重新创建已经运行的自定义进程。

## 上线检查

- 为 `jobId/eventId` 建立业务唯一约束，验证重复任务不会产生重复副作用。
- `waitConfirmTime` 必须大于正常业务耗时和依赖超时总和，否则任务仍在执行时就可能被再次投递。
- `retryTimes` 耗尽的任务不会继续投递。组件不会自动建立一张业务死信表，应在最后一次处理失败时记录任务内容和异常，并接入告警或人工补偿流程。
- 监控入队失败、消费异常、重试次数、队列积压和最老任务等待时间。
- 处理 `SIGTERM`，让消费循环停止并给正在执行的任务合理的退出时间。
- 多个消费进程会并发处理任务，不能依赖普通 PHP 变量实现全局锁。

## 源码依据

- [Queue README](https://github.com/easy-swoole/queue/blob/5.x/README.md)
- [Consumer](https://github.com/easy-swoole/queue/blob/5.x/src/Consumer.php)
- [Redis 驱动](https://github.com/easy-swoole/queue/blob/5.x/src/Driver/Redis/Redis.php)
- [RabbitMQ 驱动](https://github.com/easy-swoole/queue/blob/5.x/src/Driver/RabbitMQ/RabbitMQ.php)
