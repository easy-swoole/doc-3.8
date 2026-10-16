# 可信队列：生产、消费与延迟任务

本章假设 `$queue` 已按照前两章完成初始化。Redis 与 RabbitMQ 使用相同的 `Queue`、`Producer`、`Consumer` 和 `Job` API。

## Job 字段

```php
use EasySwoole\Queue\Job;

$job = new Job();
$job->setJobData(['orderId' => 1001]);
$job->setJobId('order-paid-1001'); // 可选；不设置时由 Producer 生成
$job->setDelayTime(5);             // 延迟秒数
$job->setRetryTimes(3);            // 大于 0 即为可信任务
$job->setWaitConfirmTime(10);      // 本次消费等待确认的秒数
```

| 字段 | 说明 |
| --- | --- |
| `jobData` | 业务数据，可以是数组、字符串等可序列化值 |
| `jobId` | 任务业务标识；为空时 Producer 自动生成 |
| `delayTime` | 延迟秒数，默认 0 |
| `retryTimes` | 最大投递次数，默认 0；大于 0 时要求确认 |
| `runTimes` | 已投递次数，由驱动维护 |
| `waitConfirmTime` | 可信任务等待本次确认的时间，默认 10 秒 |
| `queueReceiptId` | 驱动内部回执，业务代码不要设置 |

如果传给 `setDelayTime()` 的值小于或等于 0，当前实现会改为 3 秒。无需延迟时不要调用该方法。

## 生产普通任务

```php
use EasySwoole\Queue\Job;

$job = new Job();
$job->setJobData([
    'orderId' => 1001,
    'event' => 'paid',
]);

$success = $queue->producer('order')->push($job);
if (!$success) {
    throw new RuntimeException('订单任务入队失败');
}
```

同一个 `$queue->producer('order')` 会被缓存并复用。不同 topic 应使用不同名称：

```php
$queue->producer('order')->push($orderJob);
$queue->producer('email')->push($emailJob);
```

## 消费一条任务

```php
$consumer = $queue->consumer('order');
$job = $consumer->pop(3.0);

if ($job === null) {
    // 3 秒内没有取到任务。
    return;
}

$data = $job->getJobData();
OrderService::handlePaid((int) $data['orderId']);
```

普通任务在被成功取出后即从 Redis 删除，或在进入 RabbitMQ 本地缓冲区后 ACK，不需要也不能依靠 `confirm()` 保证重投。不能丢失的任务应使用可信任务。

## 延迟任务

```php
$job = new Job();
$job->setJobData(['orderId' => 1001]);
$job->setDelayTime(300); // 5 分钟后可消费

$queue->producer('order-check')->push($job);
```

延迟时间表示“至少等待这么久才可见”，不保证消费者会在该秒立刻执行。实际执行时间还受轮询间隔、队列积压、消费者数量和业务耗时影响。

## 持续消费

```php
use EasySwoole\Queue\Job;

$consumer = $queue->consumer('order');
$consumer->setBreakTime(0.1);
$consumer->setOnBreak(function (): void {
    // 当前没有任务。不要在这里执行耗时工作。
});

$consumer->listen(
    function (Job $job) use ($consumer): void {
        $data = $job->getJobData();
        OrderService::handlePaid((int) $data['orderId']);

        if ($job->getRetryTimes() > 0) {
            $consumer->confirm($job);
        }
    },
    [],
    function (Throwable $throwable, ?Job $job): void {
        error_log($throwable->__toString());
    }
);
```

`listen()` 会持续循环，适合放在自定义进程中，不要直接放进控制器 Action。`setBreakTime()` 控制没有任务时的休眠时间；未设置 `onBreak` 时，组件会自动执行协程 sleep，避免空循环占满 CPU。

停止循环可以调用：

```php
$consumer->stopListen();
```

下一章：[可信任务与框架接入](/Library/Queue/reliable.md)。
