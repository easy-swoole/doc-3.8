# 并行任务 ParallelJob

`ParallelJob` 用于“单协程持续拉取任务，多协程并行消费”的场景。

```text
setTaskProducer 回调
      ↓ 单个生产协程持续取任务
内部 Channel 队列
      ↓
多个消费协程并行执行 setTaskHandler 回调
```

它适合任务不能一次性全部载入内存，需要从分页接口、生成器或其他任务源持续取出的场景。

## 完整示例

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\Component\CoroutineRunner\ParallelJob;

Co\run(function (): void {
    $jobs = new SplQueue();
    $jobs->enqueue(0);
    $jobs->enqueue(1001);
    $jobs->enqueue(1002);

    $parallel = new ParallelJob(maxQueueSize: 128);

    $parallel->setTaskProducer(function () use ($jobs): ?int {
        if ($jobs->isEmpty()) {
            return null;
        }

        return $jobs->dequeue();
    });

    $parallel->setTaskHandler(function (int $job): void {
        echo "处理任务 {$job}" . PHP_EOL;
    });

    $parallel->setOnException(
        function (Throwable $throwable, ?int $job = null): void {
            error_log(sprintf(
                'job %s failed: %s',
                $job === null ? 'producer' : (string) $job,
                $throwable->getMessage()
            ));
        }
    );

    $finished = $parallel->sync(
        coroutineNum: 8,
        maxJobTry: 3,
        timeOut: 30
    );

    if (!$finished) {
        // 达到整体等待超时，调度已被 interrupt。
    }
});
```

## 构造参数与队列

```php
$parallel = new ParallelJob(maxQueueSize: 1024);
```

`maxQueueSize` 是内部 Channel 最多缓存的待消费任务数，默认 `1024`。队列满时，生产协程每隔约 1 毫秒检查一次，直到出现可写空间。

队列容量不是消费者数量。消费者数量由 `exec()` 或 `sync()` 的 `coroutineNum` 参数决定。

## 定义任务来源

`setTaskProducer()` 注册生产回调。组件会在单独一个协程中反复调用它，每次取得一个任务：

```php
$parallel->setTaskProducer(function (): mixed {
    return fetchNextJob();
});
```

只有返回 `null` 才表示“本次没有任务”。其他返回值都会写入内部队列并交给处理回调，包括：

```php
false
0
'0'
''
[]
```

例如上面的完整示例会把任务 `0` 交给消费者，而不会把它当成任务结束。如果业务本身需要处理 `null`，可把它包装到数组或对象中再返回。

`maxJobTry` 表示生产回调连续返回 `null` 多少次后，认定任务源已经结束：

```php
$parallel->exec(
    coroutineNum: 8,
    maxJobTry: 3
);
```

取得任何非 `null` 任务（包括 `false`、`0` 和空数组）后，连续空结果计数会清零。生产回调应自行处理分页游标，并避免在“暂时没有任务但后续还会出现”的长驻队列场景中过早达到该阈值。这里的重试是重新调用**生产回调**寻找下一项任务，不是失败任务的重试次数。

## 定义消费逻辑

`setTaskHandler()` 注册任务处理回调：

```php
$parallel->setTaskHandler(function (array $job): void {
    handleJob($job);
});
```

组件最多创建 `coroutineNum` 个消费协程。每个协程不断从队列取任务并调用回调，直到调度结束。

`jobWaitTime` 是消费者从空队列等待任务的时间，单位为秒，默认 `0.01`：

```php
$parallel->jobWaitTime = 0.05;
```

该属性影响空队列轮询频率，不是单个业务任务的执行超时。

`coroutineNum` 应大于 0。设置为 0 时没有消费者，队列中的任务无法处理，调度可能无法自然结束。

## 异常处理

```php
$parallel->setOnException(
    function (Throwable $throwable, mixed $job = null): void {
        if ($job === null) {
            // 生产回调异常。
        } else {
            // 消费该任务时异常。
        }
    }
);
```

回调参数取决于异常来源：

- `setTaskProducer()` 抛出异常时，只传入 `$throwable`。
- `setTaskHandler()` 抛出异常时，传入 `$throwable` 和当前 `$job`。

因此，异常处理器的第二个参数应提供默认值。没有设置 `onException` 时，异常会从对应协程继续抛出。

异常任务不会自动重试。生产回调持续抛出异常时，空任务计数也不会增加，可能形成高频异常循环；异常处理器应记录问题并根据业务决定是否调用 `interrupt()`。

## exec：异步启动

```php
$parallel->exec(
    coroutineNum: 8,
    maxJobTry: 3
);
```

`exec()` 创建生产协程、完成监控协程和消费协程后立即返回，不等待任务队列处理完毕。可以通过 `isFinish()` 查询调度是否结束：

```php
while (!$parallel->isFinish()) {
    Co::sleep(0.05);
}
```

调用前必须同时设置 `addTaskCall` 和 `taskCall`，否则抛出 `Exception`。

## sync：启动并等待

```php
$finished = $parallel->sync(
    coroutineNum: 8,
    maxJobTry: 3,
    timeOut: 30
);
```

- `timeOut` 单位为秒。
- 默认 `-1` 表示不设置整体等待超时。
- 自然结束时返回 `true`。
- 超时后调用 `interrupt()` 并返回 `false`。

整体超时不会中断已经进入 `setTaskHandler()` 的业务回调。数据库、HTTP 等 I/O 仍需分别设置超时。

### sync 返回 true 的准确含义

当前源码在“生产回调连续返回 `null` 达到指定次数，并且内部待消费队列为空”时，把 `isFinish` 设置为 `true`。消费者可能已经从队列取出最后一个任务，但其 `setTaskHandler()` 回调尚未执行完毕。

因此，`sync()` 返回 `true` 表示任务源结束且待消费队列已经取空，不严格保证所有已经取出的业务回调都执行结束。业务必须等所有处理回调完成时，应在 `setTaskHandler()` 外再配合完成计数或 `WaitGroup`，或者选择能够明确等待运行中任务数归零的调度方式。

## interrupt 与 flushJobQueue

手动停止调度：

```php
$parallel->interrupt();
```

`interrupt()` 会把调度标记为结束，让生产和消费循环陆续退出，但不会强制终止当前正在执行的业务回调。

结束后可以清空仍留在内部队列中的任务：

```php
$parallel->interrupt();
$cleared = $parallel->flushJobQueue();
```

`flushJobQueue()` 只有在 `isFinish()` 为 `true` 时才清理队列并返回 `true`；仍在运行时返回 `false`。清空队列会丢弃尚未开始处理的任务，应确认业务允许后再调用。

## 对象只能执行一轮

自然完成或调用 `interrupt()` 后，`isFinish` 会保持 `true`。再次调用 `exec()` 会直接返回，不会启动新一轮任务。

每批任务应创建新的 `ParallelJob` 对象：

```php
function runBatch(SplQueue $jobs): bool
{
    $parallel = new ParallelJob(128);
    // 设置回调……

    return $parallel->sync(8, 3, 30);
}
```

## 与 CoroutineRunner 的区别

| 对比项 | `ParallelJob` | `CoroutineRunner` |
| --- | --- | --- |
| 任务提供方式 | 生产回调持续拉取 | 调用 `addTask()` 入队 |
| 任务对象 | 任意非 `null` 值 | 必须是 `Task` 对象 |
| 成功/失败回调 | 没有，由业务自行处理 | Task 提供 success/fail |
| 调度复用 | 完成后不能再次执行 | 正常结束后可处理下一批 |
| 完成判断 | 任务源结束且队列取空 | 队列空且运行计数归零 |

## 常见错误

- 生产回调在尚有任务时返回 `null`，导致连续空结果次数达到 `maxJobTry` 后提前结束。
- 把 `maxQueueSize` 当成消费协程数量。
- 将 `jobWaitTime` 误认为业务任务超时。
- 认为 `interrupt()` 会强制取消正在执行的任务。
- 认为 `sync()` 返回 `true` 一定代表所有 `onTask` 回调已经返回。
- 完成后复用同一个 `ParallelJob` 对象。
- 生产回调持续异常，却没有停止策略。

## 源码依据

- [ParallelJob 2.5.5 源码](https://github.com/easy-swoole/component/blob/2.5.5/src/CoroutineRunner/ParallelJob.php)
- [ParallelJob 2.5.5 README 示例](https://github.com/easy-swoole/component/blob/2.5.5/README.md#paralleljob)
